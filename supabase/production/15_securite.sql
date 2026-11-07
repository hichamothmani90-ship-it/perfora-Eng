-- ===== 15_securite.sql — copie générée de supabase/securite.sql (empreinte d10eada719ba719b) : ne pas modifier ici =====
-- GMAO terrain — étape 6 « sécurité » (7 nov. 2026). APRÈS fichiers.sql (avant demo.sql dans la séquence). Rejouable.
-- 1. Double authentification (MFA) de l'administrateur plateforme : ses droits ne valent que dans une session
--    confirmée par un code d'application d'authentification (niveau « aal2 » du jeton). Vérifié par le serveur :
--    console, fonctions pf_*, règles de lecture (RLS) qui utilisent est_admin_plateforme().
-- 2. Journal des actions sur les tables de la plateforme (entreprises, abonnements, sites, tarifs, imports…) :
--    ajout seulement, lisible par l'administrateur seul.
-- 3. Limites d'envoi : invitations et demandes de support par heure (anti-abus).
-- 4. Remontée des erreurs de l'appli (et des refus du serveur) pour l'onglet « Technique » du centre de contrôle.

-- ---------- 1. MFA administrateur ----------
alter table public.admins_plateforme add column if not exists mfa_obligatoire boolean;
-- Administrateurs déjà inscrits (recette) : MFA activée par eux-mêmes depuis la console (pf_mfa_activer), pour ne pas
-- se retrouver bloqués. Tout nouvel administrateur (production) : obligatoire d'emblée.
update public.admins_plateforme set mfa_obligatoire = false where mfa_obligatoire is null;
alter table public.admins_plateforme alter column mfa_obligatoire set default true;
alter table public.admins_plateforme alter column mfa_obligatoire set not null;

/** Niveau d'authentification de la session : aal2 = mot de passe + code de l'application d'authentification. */
create or replace function public.niveau_session()
returns text language sql stable set search_path = public as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'aal', 'aal1')
$$;
/** Inscrit comme administrateur (quel que soit le niveau de la session). */
create or replace function public.admin_inscrit()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins_plateforme where user_id = auth.uid())
$$;
/** Droits d'administrateur : inscrit ET, si la MFA est obligatoire pour lui, session confirmée (aal2). */
create or replace function public.est_admin_plateforme()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins_plateforme a where a.user_id = auth.uid()
                 and (not a.mfa_obligatoire or public.niveau_session() = 'aal2'))
$$;
/** Après la première vérification d'un code : la MFA devient obligatoire pour cet administrateur. */
create or replace function public.pf_mfa_activer()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_inscrit() then raise exception 'Réservé à l''administrateur plateforme' using errcode = '42501'; end if;
  if public.niveau_session() <> 'aal2' then raise exception 'Confirmez d''abord un code de l''application d''authentification' using errcode = '42501'; end if;
  update admins_plateforme set mfa_obligatoire = true where user_id = auth.uid();
  return jsonb_build_object('mfaObligatoire', true);
end $$;
revoke all on function public.niveau_session() from public, anon;
revoke all on function public.admin_inscrit() from public, anon;
grant execute on function public.admin_inscrit() to authenticated;   -- dit seulement si l'appelant est inscrit (utile aux déclencheurs)
revoke all on function public.pf_mfa_activer() from public, anon;
grant execute on function public.niveau_session() to authenticated;
grant execute on function public.pf_mfa_activer() to authenticated;

-- mon_profil (version de plateforme.sql) + état MFA de l'administrateur.
create or replace function public.mon_profil()
returns jsonb language plpgsql security definer set search_path = public as $$
declare p profils; pid text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  select * into p from profils where user_id = auth.uid();
  if not found then raise exception 'Compte sans profil' using errcode = '42501'; end if;
  if p.entreprise_id is null then raise exception 'Compte non rattaché à une entreprise : contactez votre responsable' using errcode = '42501'; end if;
  if p.personne_id is null or not exists (select 1 from fiches where id = p.personne_id) then
    pid := 'p' || replace(p.user_id::text, '-', '');
    insert into fiches (id, type, data, auteur, entreprise_id) values (pid, 'personnes', jsonb_build_object(
      'id', pid, 'nom', coalesce(p.nom, p.email), 'role', p.role, 'actif', p.actif, 'email', p.email,
      'creeLe', maintenant, 'creePar', 'serveur', 'modifieLe', maintenant, 'modifiePar', 'serveur'), auth.uid(), p.entreprise_id)
    on conflict (id) do nothing;
    update profils set personne_id = pid where user_id = p.user_id;
    p.personne_id := pid;
  end if;
  return jsonb_build_object(
    'userId', p.user_id, 'email', p.email, 'nom', p.nom, 'role', p.role, 'personneId', p.personne_id, 'actif', p.actif,
    'entreprise', (select jsonb_build_object('id', e.id, 'code', e.code, 'nom', e.nom, 'statut', e.statut, 'demo', e.demo, 'reinitLe', e.reinit_le) from entreprises e where e.id = p.entreprise_id),
    'sites', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'nom', s.nom) order by s.nom)
                       from sites s where s.id in (select public.mes_sites())), '[]'::jsonb),
    'siteDefaut', p.site_defaut,
    'abonnement', public.droits_entreprise(p.entreprise_id),
    'adminPlateforme', public.est_admin_plateforme(),
    -- inscrit mais session sans code : la console demande le code (ou l'inscription de l'application d'authentification)
    'adminMfa', case when not public.admin_inscrit() then null
                     else (select jsonb_build_object('obligatoire', a.mfa_obligatoire, 'niveau', public.niveau_session())
                           from admins_plateforme a where a.user_id = auth.uid()) end);
end $$;
revoke all on function public.mon_profil() from public, anon;
grant execute on function public.mon_profil() to authenticated;

-- ---------- 2. journal des actions de la plateforme ----------
create table if not exists public.pf_journal_admin (
  id          bigserial primary key,
  le          timestamptz not null default now(),
  acteur      uuid,                 -- null : SQL Editor ou service (clé secrète)
  acteur_email text,
  niveau      text,                 -- aal1 / aal2 (double authentification)
  fonction    text,                 -- fonction appelante (pf_creer_entreprise…), si appel par l'API
  table_nom   text not null,
  operation   text not null,        -- INSERT / UPDATE / DELETE
  cle         text,
  avant       jsonb,
  apres       jsonb
);
create index if not exists pf_journal_admin_le on public.pf_journal_admin (le desc);
alter table public.pf_journal_admin enable row level security;   -- aucune règle : lecture par pf_journal_admin_lire seulement
revoke all on public.pf_journal_admin from anon, authenticated;

/** Valeur journalisée : les champs volumineux sont résumés (jamais de contenu de fichier dans le journal). */
create or replace function public.pf_journal_reduire(j jsonb)
returns jsonb language sql immutable set search_path = public as $$
  select coalesce(jsonb_object_agg(k, case when length(v::text) > 1000 then to_jsonb('[' || length(v::text) || ' caractères]') else v end), '{}'::jsonb)
  from jsonb_each(j) as x(k, v)
$$;

create or replace function public.pf_journaliser()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  a jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  n jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  r jsonb := coalesce(n, a); ctx text; fn text; cle text; diff_a jsonb; diff_n jsonb;
begin
  -- Profils et affectations : seulement quand c'est l'administrateur ou un accès direct (le responsable a son propre journal).
  if tg_table_name in ('profils', 'profil_sites') and auth.uid() is not null and not public.admin_inscrit() then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(k, a->k), jsonb_object_agg(k, n->k) into diff_a, diff_n
    from jsonb_object_keys(n) k where (a->k) is distinct from (n->k);
    if diff_n is null then return null; end if;   -- rien n'a changé
  else
    diff_a := a; diff_n := n;
  end if;
  get diagnostics ctx = pg_context;
  ctx := regexp_replace(ctx, 'PL/pgSQL function (public\.)?pf_journaliser\(\)[^
]*', '', 'g');   -- sans le déclencheur lui-même
  fn := substring(ctx from 'function (?:public\.)?(pf_[a-z_0-9]+|preparer_invitation|finaliser_invitation|definir_profil|affecter_sites|support_creer|push_fiches)\(');
  cle := coalesce(r->>'id', r->>'entreprise_id', r->>'user_id', r->>'code', r->>'pack');
  if tg_table_name = 'profil_sites' then cle := (r->>'user_id') || ' / ' || (r->>'site_id'); end if;
  insert into pf_journal_admin (acteur, acteur_email, niveau, fonction, table_nom, operation, cle, avant, apres)
  values (auth.uid(), (select email from profils where user_id = auth.uid()), case when auth.uid() is null then null else public.niveau_session() end,
          fn, tg_table_name, tg_op, cle, public.pf_journal_reduire(diff_a), public.pf_journal_reduire(diff_n));
  return null;
end $$;
revoke all on function public.pf_journaliser() from public, anon, authenticated;
revoke all on function public.pf_journal_reduire(jsonb) from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['entreprises', 'abonnements', 'sites', 'admins_plateforme', 'packs', 'pf_tarifs', 'pf_annonces',
                           'pf_lots_import', 'pf_mise_en_service', 'profils', 'profil_sites'] loop
    execute format('drop trigger if exists gmao_journal_admin on public.%I', t);
    execute format('create trigger gmao_journal_admin after insert or update or delete on public.%I for each row execute function public.pf_journaliser()', t);
  end loop;
  -- pf_objets (prospects, tickets, échanges, modèles) : changements faits par l'administrateur seulement (les tickets des clients sont déjà datés).
  drop trigger if exists gmao_journal_admin on public.pf_objets;
  create trigger gmao_journal_admin after insert or update or delete on public.pf_objets for each row
    when (public.admin_inscrit() or auth.uid() is null) execute function public.pf_journaliser();
end $$;

-- Ajout seulement : personne (pas même un administrateur par l'API) ne modifie ni n'efface le journal.
create or replace function public.pf_journal_intouchable()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'Le journal des actions ne se modifie pas' using errcode = '42501';
end $$;
revoke all on function public.pf_journal_intouchable() from public, anon, authenticated;
drop trigger if exists gmao_journal_intouchable on public.pf_journal_admin;
create trigger gmao_journal_intouchable before update or delete on public.pf_journal_admin for each row execute function public.pf_journal_intouchable();

create or replace function public.pf_journal_admin_lire(p_limite integer default 200, p_avant bigint default null, p_table text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(to_jsonb(j) order by j.id desc) from (
    select * from pf_journal_admin
    where (p_avant is null or id < p_avant) and (p_table is null or table_nom = p_table)
    order by id desc limit least(greatest(coalesce(p_limite, 200), 1), 500)) j), '[]'::jsonb);
end $$;
revoke all on function public.pf_journal_admin_lire(integer, bigint, text) from public, anon;
grant execute on function public.pf_journal_admin_lire(integer, bigint, text) to authenticated;

-- ---------- 3. limites d'envoi ----------
create table if not exists public.pf_limites (cle text not null, le timestamptz not null default now());
create index if not exists pf_limites_cle_le on public.pf_limites (cle, le);
alter table public.pf_limites enable row level security;
revoke all on public.pf_limites from anon, authenticated;

/** Refuse au-delà de p_max actions de même clé sur la fenêtre ; sinon compte l'action. */
create or replace function public.limiter(p_cle text, p_max integer, p_fenetre interval, p_message text)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from pf_limites where le < now() - interval '2 days';   -- ménage
  if (select count(*) from pf_limites where cle = p_cle and le > now() - p_fenetre) >= p_max then
    raise exception '%', p_message using errcode = '54000';
  end if;
  insert into pf_limites (cle) values (p_cle);
end $$;
revoke all on function public.limiter(text, integer, interval, text) from public, anon, authenticated;

-- Invitations (version de plateforme.sql + limite) : 20 par heure et par entreprise ; 50 par heure pour l'administrateur.
create or replace function public.preparer_invitation(p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  perform public.limiter('invitation:' || public.mon_entreprise(), 20, interval '1 hour', 'Trop d''invitations en une heure : réessayez plus tard');
  return public.controle_invitation(public.mon_entreprise(), p_email, p_role, p_sites);
end $$;
revoke all on function public.preparer_invitation(text, text, uuid[]) from public, anon;
grant execute on function public.preparer_invitation(text, text, uuid[]) to authenticated;

create or replace function public.pf_preparer_invitation(p_entreprise uuid, p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  perform public.limiter('invitation-admin:' || auth.uid(), 50, interval '1 hour', 'Trop d''invitations en une heure : réessayez plus tard');
  return public.controle_invitation(p_entreprise, p_email, p_role, p_sites);
end $$;
revoke all on function public.pf_preparer_invitation(uuid, text, text, uuid[]) from public, anon;
grant execute on function public.pf_preparer_invitation(uuid, text, text, uuid[]) to authenticated;

-- Support (version de centre_controle_cc2.sql + limites) : 5 par heure et par compte, 15 par heure et par entreprise.
create or replace function public.support_creer(p_nature text, p_sujet text, p_message text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); p profils; i text := 'ticket-' || replace(gen_random_uuid()::text, '-', ''); ref text;
begin
  if ent is null or public.mon_role() is null then raise exception 'Compte sans entreprise' using errcode = '42501'; end if;
  if coalesce(p_nature, '') not in ('question', 'anomalie', 'evolution', 'facturation') then raise exception 'Nature de la demande inconnue'; end if;
  if coalesce(trim(p_sujet), '') = '' or coalesce(trim(p_message), '') = '' then raise exception 'Sujet et message obligatoires'; end if;
  if length(p_message) > 3000 or length(p_sujet) > 150 then raise exception 'Message trop long'; end if;
  if (select count(*) from pf_objets where type = 'ticket' and entreprise_id = ent and data->>'statut' in ('ouverte', 'en_cours', 'en_attente_client')) >= 20 then
    raise exception 'Trop de demandes ouvertes : le support vous recontacte';
  end if;
  perform public.limiter('support:' || auth.uid(), 5, interval '1 hour', 'Trop de demandes en une heure : réessayez plus tard ou appelez le support');
  perform public.limiter('support-entreprise:' || ent, 15, interval '1 hour', 'Trop de demandes en une heure pour votre entreprise : réessayez plus tard');
  select * into p from profils where user_id = auth.uid();
  ref := 'SUP-' || lpad(nextval('pf_tickets_seq')::text, 4, '0');
  insert into pf_objets (id, type, entreprise_id, data, par) values (i, 'ticket', ent, jsonb_build_object(
    'ref', ref, 'nature', p_nature, 'sujet', trim(p_sujet), 'description', trim(p_message), 'statut', 'ouverte', 'priorite', 'normale',
    'source', 'appli', 'demandeur', jsonb_build_object('nom', p.nom, 'email', p.email, 'role', p.role)), auth.uid());
  return jsonb_build_object('ref', ref);
end $$;
revoke all on function public.support_creer(text, text, text) from public, anon;
grant execute on function public.support_creer(text, text, text) to authenticated;

-- ---------- 4. erreurs de l'appli ----------
create table if not exists public.pf_erreurs (
  id            bigserial primary key,
  premier_le    timestamptz not null default now(),
  dernier_le    timestamptz not null default now(),
  nb            integer not null default 1,
  user_id       uuid,
  entreprise_id uuid,
  nature        text not null,      -- erreur (JavaScript), refus (serveur), synchro
  message       text not null,
  detail        text,               -- pile d'appels ou fiche refusée (abrégée)
  page          text,
  version       text,
  appareil      text
);
create index if not exists pf_erreurs_dernier on public.pf_erreurs (dernier_le desc);
alter table public.pf_erreurs enable row level security;
revoke all on public.pf_erreurs from anon, authenticated;

/** Erreurs envoyées par l'appli (par lots) : regroupées par compte et message sur 24 h, tronquées, limitées. */
create or replace function public.erreurs_signaler(p_erreurs jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare x jsonb; ent uuid := public.mon_entreprise(); n integer := 0; msg text; nat text;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire' using errcode = '42501'; end if;
  if jsonb_typeof(p_erreurs) <> 'array' then raise exception 'Liste attendue'; end if;
  perform public.limiter('erreurs:' || auth.uid(), 30, interval '1 hour', 'Trop d''erreurs signalées');
  delete from pf_erreurs where dernier_le < now() - interval '90 days';   -- ménage
  for x in select * from jsonb_array_elements(p_erreurs) limit 20 loop
    msg := left(coalesce(nullif(trim(x->>'message'), ''), '(sans message)'), 300);
    nat := case when x->>'nature' in ('erreur', 'refus', 'synchro') then x->>'nature' else 'erreur' end;
    update pf_erreurs set nb = nb + greatest(coalesce((x->>'nb')::int, 1), 1), dernier_le = now(), version = left(x->>'version', 20), page = left(x->>'page', 120)
      where user_id = auth.uid() and message = msg and nature = nat and dernier_le > now() - interval '24 hours';
    if not found then
      insert into pf_erreurs (user_id, entreprise_id, nature, message, detail, page, version, appareil, nb)
      values (auth.uid(), ent, nat, msg, left(x->>'detail', 1500), left(x->>'page', 120), left(x->>'version', 20), left(x->>'appareil', 150),
              greatest(coalesce((x->>'nb')::int, 1), 1));
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.erreurs_signaler(jsonb) from public, anon;
grant execute on function public.erreurs_signaler(jsonb) to authenticated;

create or replace function public.pf_erreurs_lire(p_jours integer default 7)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'premierLe', e.premier_le, 'dernierLe', e.dernier_le, 'nb', e.nb, 'nature', e.nature,
      'message', e.message, 'detail', e.detail, 'page', e.page, 'version', e.version, 'appareil', e.appareil,
      'email', p.email, 'role', p.role, 'entreprise', en.nom, 'entrepriseCode', en.code) order by e.dernier_le desc)
    from pf_erreurs e left join profils p on p.user_id = e.user_id left join entreprises en on en.id = e.entreprise_id
    where e.dernier_le > now() - make_interval(days => least(greatest(coalesce(p_jours, 7), 1), 90))), '[]'::jsonb);
end $$;
revoke all on function public.pf_erreurs_lire(integer) from public, anon;
grant execute on function public.pf_erreurs_lire(integer) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
