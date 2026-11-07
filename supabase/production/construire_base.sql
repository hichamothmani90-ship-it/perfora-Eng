-- Perfora — construction complète d'une base neuve (Supabase → SQL Editor, en une fois).
-- FICHIER GÉNÉRÉ par scripts/assembler_sql.py : ne pas modifier à la main.
-- Ensuite : désigner l'administrateur plateforme (voir docs/PRODUCTION_ET_SAUVEGARDE.md).

-- ===== 01_schema.sql — copie générée de supabase/schema.sql (empreinte fa48df188f3c8239) : ne pas modifier ici =====
-- GMAO terrain — schéma de synchronisation (prototype, lot 1)
-- À exécuter une fois dans Supabase : SQL Editor → New query → coller → Run.
--
-- Principe : chaque appareil garde ses données en local (offline-first) et envoie des
-- « patchs » (champs modifiés). Le serveur fusionne champ par champ et numérote chaque
-- changement (seq) pour que les autres appareils récupèrent ce qui est nouveau.
-- Aucune suppression possible : pas de règle DELETE.

create sequence if not exists public.fiches_seq;

create table if not exists public.fiches (
  id       text primary key,
  type     text not null check (type in ('localisations','equipements','personnes','demandes','ots',
                                         'programmes','articles','mouvements','journal','photos')),
  data     jsonb not null,
  seq      bigint not null default nextval('public.fiches_seq'),
  recu_le  timestamptz not null default now(),   -- heure serveur (repère de synchro, pas l'heure des faits)
  auteur   uuid default auth.uid()
);
create index if not exists fiches_seq_idx on public.fiches (seq);

alter table public.fiches enable row level security;

-- Prototype : un seul site, toute personne connectée lit et écrit.
-- (Lot 1 étape 2 : rôles et périmètres par entreprise / site.)
drop policy if exists "lecture equipe" on public.fiches;
drop policy if exists "creation equipe" on public.fiches;
drop policy if exists "modification equipe" on public.fiches;
create policy "lecture equipe" on public.fiches for select to authenticated using (true);
create policy "creation equipe" on public.fiches for insert to authenticated with check (true);
create policy "modification equipe" on public.fiches for update to authenticated using (true) with check (true);

revoke all on public.fiches from anon;
grant select, insert, update on public.fiches to authenticated;
grant usage, select on sequence public.fiches_seq to authenticated;

-- Réception d'un lot de patchs : [{ "id", "type", "patch" }, ...] dans l'ordre de saisie.
-- Fiches « append-only » (journal, mouvements, photos) : jamais modifiées après création.
-- Autres fiches : fusion champ par champ (data || patch), le dernier arrivé gagne pour un même champ.
create or replace function public.push_fiches(lot jsonb)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  f jsonb;
  n integer := 0;
begin
  for f in select value from jsonb_array_elements(lot) loop
    if f->>'type' in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data) values (f->>'id', f->>'type', f->'patch')
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data) values (f->>'id', f->>'type', f->'patch')
      on conflict (id) do update
        set data = fiches.data || excluded.data,
            seq = nextval('public.fiches_seq'),
            recu_le = now(),
            auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- ===== 02_roles.sql — copie générée de supabase/roles.sql (empreinte b24732eb200b2488) : ne pas modifier ici =====
-- GMAO terrain — rôles et droits contrôlés par le serveur (lot 1, étape 2).
-- À exécuter APRÈS schema.sql. Rejouable sans risque (idempotent).
--
-- Principe : les écritures ne passent plus que par push_fiches(), qui vérifie le rôle du
-- compte connecté pour chaque fiche. Une écriture interdite est refusée (et signalée à l'appli),
-- les autres du même lot passent. Lecture : réservée aux comptes actifs.
--
-- Matrice (V3 §24) :
--   responsable  : tout (configuration, rouvrir / corriger une intervention clôturée)
--   technicien   : demandes, interventions (sauf clôturées), photos, sorties de pièces sur intervention
--   prestataire  : comme technicien
--   magasinier   : demandes, photos, articles, tous mouvements de stock
--   exploitation : demandes et photos
--   pilote       : lecture seule

-- ---------- profils (un par compte) ----------
create table if not exists public.profils (
  user_id     uuid primary key,
  email       text,
  nom         text,
  role        text not null default 'technicien'
              check (role in ('responsable','technicien','prestataire','magasinier','exploitation','pilote')),
  personne_id text,
  actif       boolean not null default true,
  cree_le     timestamptz not null default now()
);
alter table public.profils enable row level security;

create or replace function public.mon_role()
returns text language sql stable security definer set search_path = public as $$
  select role from profils where user_id = auth.uid() and actif
$$;
revoke all on function public.mon_role() from public, anon;
grant execute on function public.mon_role() to authenticated;

revoke all on public.profils from anon, authenticated;
grant select on public.profils to authenticated;
drop policy if exists "profil lisible" on public.profils;
create policy "profil lisible" on public.profils for select to authenticated
  using (user_id = auth.uid() or public.mon_role() = 'responsable');

-- Nouveau compte (invitation) => profil technicien par défaut
create or replace function public.creer_profil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profils (user_id, email, nom) values (new.id, new.email, split_part(new.email, '@', 1))
  on conflict (user_id) do nothing;
  return new;
end $$;
drop trigger if exists gmao_creer_profil on auth.users;
create trigger gmao_creer_profil after insert on auth.users
  for each row execute function public.creer_profil();
insert into public.profils (user_id, email, nom)
  select id, email, split_part(email, '@', 1) from auth.users
  on conflict (user_id) do nothing;

-- ---------- lecture des fiches : comptes actifs seulement ----------
drop policy if exists "lecture equipe" on public.fiches;
drop policy if exists "creation equipe" on public.fiches;
drop policy if exists "modification equipe" on public.fiches;
create policy "lecture equipe" on public.fiches for select to authenticated using (public.mon_role() is not null);
revoke insert, update, delete on public.fiches from authenticated;   -- écriture : push_fiches uniquement
grant select on public.fiches to authenticated;

-- ---------- règles d'écriture ----------
create or replace function public.peut_ecrire(r text, t text)
returns boolean language sql immutable as $$
  select case
    when r is null or r = 'pilote' then false
    when r = 'responsable' then true
    when t in ('demandes', 'journal', 'photos') then true
    when t = 'ots' then r in ('technicien', 'prestataire')
    when t = 'articles' then r = 'magasinier'
    when t = 'mouvements' then r in ('magasinier', 'technicien', 'prestataire')
    else false
  end
$$;

drop function if exists public.push_fiches(jsonb);
create function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; t text; cible text; motif text; statut_actuel text;
  r text := public.mon_role();
  n integer := 0;
  refus jsonb := '[]'::jsonb;
  refuses text[] := '{}';
begin
  if r is null then
    raise exception 'Compte sans droits (profil absent ou désactivé)' using errcode = '42501';
  end if;
  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type';
    cible := case when t = 'journal' then f->'patch'->>'entite' else t end;
    motif := null;
    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos') then
      motif := 'type inconnu';
    elsif t = 'journal' and (f->'patch'->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'mouvements' and r in ('technicien', 'prestataire') and coalesce(f->'patch'->>'otId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'ots' and r <> 'responsable' then
      statut_actuel := null;
      select data->>'statut' into statut_actuel from fiches where id = f->>'id';
      if statut_actuel = 'cloturee' then motif := 'intervention clôturée : modification réservée au responsable'; end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    if t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur) values (f->>'id', t, f->'patch', auth.uid())
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur) values (f->>'id', t, f->'patch', auth.uid())
      on conflict (id) do update
        set data = fiches.data || excluded.data, seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- ---------- profil du compte connecté (crée sa fiche « personne » au besoin) ----------
create or replace function public.mon_profil()
returns jsonb language plpgsql security definer set search_path = public as $$
declare p profils; pid text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  select * into p from profils where user_id = auth.uid();
  if not found then raise exception 'Compte sans profil' using errcode = '42501'; end if;
  if p.personne_id is null then
    pid := 'p' || replace(p.user_id::text, '-', '');
    insert into fiches (id, type, data, auteur) values (pid, 'personnes', jsonb_build_object(
      'id', pid, 'nom', coalesce(p.nom, p.email), 'role', p.role, 'actif', p.actif, 'email', p.email,
      'creeLe', maintenant, 'creePar', 'serveur', 'modifieLe', maintenant, 'modifiePar', 'serveur'), auth.uid())
    on conflict (id) do nothing;
    update profils set personne_id = pid where user_id = p.user_id;
    p.personne_id := pid;
  end if;
  return jsonb_build_object('userId', p.user_id, 'email', p.email, 'nom', p.nom, 'role', p.role, 'personneId', p.personne_id, 'actif', p.actif);
end $$;
revoke all on function public.mon_profil() from public, anon;
grant execute on function public.mon_profil() to authenticated;

-- ---------- gestion de l'équipe (responsable) ----------
create or replace function public.definir_profil(cible uuid, nouveau_role text, nouveau_nom text, est_actif boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.mon_role() is distinct from 'responsable' then
    raise exception 'Réservé au responsable' using errcode = '42501';
  end if;
  if cible = auth.uid() and (nouveau_role <> 'responsable' or not est_actif) then
    raise exception 'Vous ne pouvez pas retirer vos propres droits de responsable';
  end if;
  update profils set role = coalesce(nouveau_role, role), nom = coalesce(nullif(trim(nouveau_nom), ''), nom),
    actif = coalesce(est_actif, actif) where user_id = cible;
  -- la fiche « personne » suit (nom, rôle, actif), et se propage aux appareils
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'nom', p.nom, 'actif', p.actif),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = p.personne_id;
end $$;
revoke all on function public.definir_profil(uuid, text, text, boolean) from public, anon;
grant execute on function public.definir_profil(uuid, text, text, boolean) to authenticated;

-- Premier responsable : à adapter puis exécuter une fois.
-- update public.profils set role = 'responsable' where email = 'votre.email@exemple.com';

-- ===== 03_multitenant.sql — copie générée de supabase/multitenant.sql (empreinte 82fc83cbdfaf1cf6) : ne pas modifier ici =====
-- GMAO terrain — Volet A, étape A1 : multi-entreprise, sites, packs (rejouable).
-- À exécuter APRÈS schema.sql et roles.sql. Voir docs/VOLET_A_CONCEPTION.md.
--
-- Principe : chaque fiche appartient à une entreprise (posée par le serveur) et, sauf
-- référentiels communs (personnes, articles), à un site. Lecture limitée à son entreprise et à
-- ses sites autorisés ; écriture via push_fiches qui vérifie entreprise, site, module du pack,
-- abonnement et rôle. Compatible avec les appareils qui n'envoient pas encore de site
-- (site par défaut du compte).

-- ---------- référentiel plateforme ----------
create table if not exists public.entreprises (
  id      uuid primary key default gen_random_uuid(),
  code    text not null unique,
  nom     text not null,
  statut  text not null default 'actif' check (statut in ('essai','actif','suspendu','resilie')),
  cree_le timestamptz not null default now()
);
create table if not exists public.sites (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references public.entreprises(id),
  code          text not null,
  nom           text not null,
  fuseau        text not null default 'Africa/Casablanca',
  actif         boolean not null default true,
  cree_le       timestamptz not null default now(),
  unique (entreprise_id, code)
);
create table if not exists public.packs (
  code                   text primary key,
  nom                    text not null,
  max_sites              integer,
  max_utilisateurs_site  integer,
  max_utilisateurs_total integer,
  modules                text[] not null,
  stockage_photos_mo     integer
);
insert into public.packs values
  ('essentiel',  'Essentiel',  1,    5,    5,    array['base','preventif'], 500),
  ('pro',        'Pro',        3,    15,   45,   array['base','preventif','magasin','rapports'], 5000),
  ('entreprise', 'Entreprise', null, null, null, array['base','preventif','magasin','rapports','achats','energie','imports'], null)
on conflict (code) do update set nom = excluded.nom, max_sites = excluded.max_sites,
  max_utilisateurs_site = excluded.max_utilisateurs_site, max_utilisateurs_total = excluded.max_utilisateurs_total,
  modules = excluded.modules, stockage_photos_mo = excluded.stockage_photos_mo;

create table if not exists public.abonnements (
  entreprise_id          uuid primary key references public.entreprises(id),
  pack                   text not null references public.packs(code),
  debut                  date not null default current_date,
  fin                    date,
  statut                 text not null default 'actif' check (statut in ('essai','actif','suspendu','resilie')),
  -- dérogations négociées (null = valeur du pack)
  max_sites              integer,
  max_utilisateurs_site  integer,
  max_utilisateurs_total integer,
  modules                text[]
);
create table if not exists public.profil_sites (
  user_id uuid not null references public.profils(user_id) on delete cascade,
  site_id uuid not null references public.sites(id),
  primary key (user_id, site_id)
);
create table if not exists public.admins_plateforme (user_id uuid primary key);

alter table public.profils add column if not exists entreprise_id uuid references public.entreprises(id);
alter table public.profils add column if not exists site_defaut uuid references public.sites(id);
alter table public.fiches add column if not exists entreprise_id uuid references public.entreprises(id);
alter table public.fiches add column if not exists site_id uuid references public.sites(id);
create index if not exists fiches_entreprise_seq_idx on public.fiches (entreprise_id, seq);

-- ---------- fonctions de périmètre ----------
create or replace function public.uuid_ou_null(t text)
returns uuid language sql immutable as $$
  select case when t ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then t::uuid end
$$;
create or replace function public.mon_entreprise()
returns uuid language sql stable security definer set search_path = public as $$
  select entreprise_id from profils where user_id = auth.uid() and actif
$$;
create or replace function public.est_admin_plateforme()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins_plateforme where user_id = auth.uid())
$$;
-- Sites autorisés : tous les sites actifs pour le responsable, sinon ceux affectés.
create or replace function public.mes_sites()
returns setof uuid language sql stable security definer set search_path = public as $$
  select s.id from sites s join profils p on p.entreprise_id = s.entreprise_id
  where p.user_id = auth.uid() and p.actif and s.actif
    and (p.role = 'responsable' or exists (select 1 from profil_sites ps where ps.user_id = p.user_id and ps.site_id = s.id))
$$;
-- Limites effectives (pack + dérogations) et droit d'écrire selon l'abonnement.
create or replace function public.droits_entreprise(ent uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pack', a.pack, 'packNom', p.nom, 'statut', a.statut, 'fin', a.fin,
    'ecriture', (a.statut in ('essai','actif') and (a.fin is null or a.fin >= current_date) and e.statut in ('essai','actif')),
    'modules', to_jsonb(coalesce(a.modules, p.modules)),
    'maxSites', coalesce(a.max_sites, p.max_sites),
    'maxUtilisateursSite', coalesce(a.max_utilisateurs_site, p.max_utilisateurs_site),
    'maxUtilisateursTotal', coalesce(a.max_utilisateurs_total, p.max_utilisateurs_total))
  from entreprises e join abonnements a on a.entreprise_id = e.id join packs p on p.code = a.pack
  where e.id = ent
$$;
create or replace function public.module_de(t text)
returns text language sql immutable as $$
  select case when t in ('articles', 'mouvements') then 'magasin' when t = 'programmes' then 'preventif' else 'base' end
$$;
revoke all on function public.mon_entreprise(), public.est_admin_plateforme(), public.mes_sites(), public.droits_entreprise(uuid) from public, anon;
grant execute on function public.mon_entreprise(), public.est_admin_plateforme(), public.mes_sites(), public.droits_entreprise(uuid) to authenticated;

-- ---------- lecture (RLS) ----------
alter table public.entreprises enable row level security;
alter table public.sites enable row level security;
alter table public.packs enable row level security;
alter table public.abonnements enable row level security;
alter table public.profil_sites enable row level security;
alter table public.admins_plateforme enable row level security;
revoke all on public.entreprises, public.sites, public.packs, public.abonnements, public.profil_sites, public.admins_plateforme from anon, authenticated;
grant select on public.entreprises, public.sites, public.packs, public.abonnements, public.profil_sites to authenticated;

drop policy if exists "mon entreprise" on public.entreprises;
create policy "mon entreprise" on public.entreprises for select to authenticated using (id = public.mon_entreprise() or public.est_admin_plateforme());
drop policy if exists "sites de mon entreprise" on public.sites;
create policy "sites de mon entreprise" on public.sites for select to authenticated using (entreprise_id = public.mon_entreprise() or public.est_admin_plateforme());
drop policy if exists "packs lisibles" on public.packs;
create policy "packs lisibles" on public.packs for select to authenticated using (true);
drop policy if exists "mon abonnement" on public.abonnements;
create policy "mon abonnement" on public.abonnements for select to authenticated using (entreprise_id = public.mon_entreprise() or public.est_admin_plateforme());
drop policy if exists "affectations visibles" on public.profil_sites;
create policy "affectations visibles" on public.profil_sites for select to authenticated using (
  user_id = auth.uid() or public.est_admin_plateforme()
  or (public.mon_role() = 'responsable' and exists (select 1 from profils p where p.user_id = profil_sites.user_id and p.entreprise_id = public.mon_entreprise())));

drop policy if exists "profil lisible" on public.profils;
create policy "profil lisible" on public.profils for select to authenticated using (
  user_id = auth.uid() or public.est_admin_plateforme()
  or (public.mon_role() = 'responsable' and entreprise_id = public.mon_entreprise()));

drop policy if exists "lecture equipe" on public.fiches;
create policy "lecture equipe" on public.fiches for select to authenticated using (
  public.mon_role() is not null
  and entreprise_id = public.mon_entreprise()
  and (site_id is null or site_id in (select public.mes_sites())));

-- ---------- écriture : push_fiches à périmètre ----------
create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type';
    cible := case when t = 'journal' then f->'patch'->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (f->'patch'->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? public.module_de(cible)) then
      motif := 'module « ' || public.module_de(cible) || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'mouvements' and r in ('technicien', 'prestataire') and coalesce(f->'patch'->>'otId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    end if;

    -- site : envoyé, existant, hérité (journal, photo) ou site par défaut du compte
    if motif is null and t not in ('personnes', 'articles') then
      s := coalesce(
        public.uuid_ou_null(f->'patch'->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = f->'patch'->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = f->'patch'->>'parentId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, f->'patch' || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, f->'patch' || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- ---------- profil enrichi (entreprise, sites, abonnement) ----------
create or replace function public.mon_profil()
returns jsonb language plpgsql security definer set search_path = public as $$
declare p profils; pid text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  select * into p from profils where user_id = auth.uid();
  if not found then raise exception 'Compte sans profil' using errcode = '42501'; end if;
  if p.entreprise_id is null then raise exception 'Compte non rattaché à une entreprise : contactez votre responsable' using errcode = '42501'; end if;
  if p.personne_id is null then
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
    'entreprise', (select jsonb_build_object('id', e.id, 'code', e.code, 'nom', e.nom, 'statut', e.statut) from entreprises e where e.id = p.entreprise_id),
    'sites', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'nom', s.nom) order by s.nom)
                       from sites s where s.id in (select public.mes_sites())), '[]'::jsonb),
    'siteDefaut', p.site_defaut,
    'abonnement', public.droits_entreprise(p.entreprise_id),
    'adminPlateforme', public.est_admin_plateforme());
end $$;
revoke all on function public.mon_profil() from public, anon;
grant execute on function public.mon_profil() to authenticated;

-- ---------- gestion d'équipe limitée à sa propre entreprise ----------
create or replace function public.definir_profil(cible uuid, nouveau_role text, nouveau_nom text, est_actif boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.mon_role() is distinct from 'responsable' then
    raise exception 'Réservé au responsable' using errcode = '42501';
  end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = public.mon_entreprise()) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if cible = auth.uid() and (nouveau_role <> 'responsable' or not est_actif) then
    raise exception 'Vous ne pouvez pas retirer vos propres droits de responsable';
  end if;
  update profils set role = coalesce(nouveau_role, role), nom = coalesce(nullif(trim(nouveau_nom), ''), nom),
    actif = coalesce(est_actif, actif) where user_id = cible;
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'nom', p.nom, 'actif', p.actif),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = p.personne_id;
end $$;
revoke all on function public.definir_profil(uuid, text, text, boolean) from public, anon;
grant execute on function public.definir_profil(uuid, text, text, boolean) to authenticated;

-- ---------- migration de l'existant : entreprise « Perfora Démo », site « Site Tanger » ----------
do $$
declare ent uuid; site uuid;
begin
  insert into entreprises (code, nom, statut) values ('DEMO', 'Perfora Démo', 'actif') on conflict (code) do nothing;
  select id into ent from entreprises where code = 'DEMO';
  insert into sites (entreprise_id, code, nom) values (ent, 'TNG', 'Site Tanger') on conflict (entreprise_id, code) do nothing;
  select id into site from sites where entreprise_id = ent and code = 'TNG';
  insert into abonnements (entreprise_id, pack, statut) values (ent, 'pro', 'actif') on conflict (entreprise_id) do nothing;

  update profils set entreprise_id = ent where entreprise_id is null;
  update profils set site_defaut = site where site_defaut is null and entreprise_id = ent;
  insert into profil_sites (user_id, site_id) select user_id, site from profils where entreprise_id = ent on conflict do nothing;

  update fiches set entreprise_id = ent where entreprise_id is null;
  update fiches set site_id = site, data = data || jsonb_build_object('siteId', site)
    where entreprise_id = ent and site_id is null and type not in ('personnes', 'articles');
end $$;
alter table public.fiches alter column entreprise_id set not null;

-- Administrateur plateforme (à adapter) :
-- insert into public.admins_plateforme (user_id) select id from auth.users where email = 'votre.email@exemple.com' on conflict do nothing;

-- ===== 04_quotas.sql — copie générée de supabase/quotas.sql (empreinte d71d058d79dbab3c) : ne pas modifier ici =====
-- GMAO terrain — Volet A, étape A3 : quotas, invitations, affectation des sites (rejouable).
-- À exécuter APRÈS multitenant.sql. Voir docs/VOLET_A_CONCEPTION.md §3.5 et §3.6.
--
-- Les quotas sont des DÉCLENCHEURS : ils s'appliquent à toute écriture (appli, fonction
-- d'invitation, tableau de bord Supabase, SQL). Limites = pack + dérogations (droits_entreprise).
-- Un compte actif compte une fois dans l'entreprise et une fois sur chaque site affecté.

-- ---------- comptage ----------
create or replace function public.nb_actifs_entreprise(ent uuid, sauf uuid)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from profils where entreprise_id = ent and actif and user_id is distinct from sauf
$$;
create or replace function public.nb_actifs_site(site uuid, sauf uuid)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from profil_sites ps join profils p on p.user_id = ps.user_id
  where ps.site_id = site and p.actif and ps.user_id is distinct from sauf
$$;

-- ---------- déclencheurs de quotas ----------
create or replace function public.quota_profils()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim jsonb; mx integer; s record;
begin
  if not new.actif or new.entreprise_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.actif and old.entreprise_id is not distinct from new.entreprise_id then return new; end if;
  lim := public.droits_entreprise(new.entreprise_id);
  mx := (lim->>'maxUtilisateursTotal')::int;
  if mx is not null and public.nb_actifs_entreprise(new.entreprise_id, new.user_id) + 1 > mx then
    raise exception 'Quota atteint : % utilisateur(s) actif(s) maximum pour l''entreprise (pack %)', mx, lim->>'packNom' using errcode = 'P0001';
  end if;
  mx := (lim->>'maxUtilisateursSite')::int;
  if mx is not null then
    for s in select ps.site_id, si.nom from profil_sites ps join sites si on si.id = ps.site_id where ps.user_id = new.user_id loop
      if public.nb_actifs_site(s.site_id, new.user_id) + 1 > mx then
        raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, s.nom using errcode = 'P0001';
      end if;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists gmao_quota_profils on public.profils;
create trigger gmao_quota_profils before insert or update of actif, entreprise_id on public.profils
  for each row execute function public.quota_profils();

create or replace function public.quota_profil_sites()
returns trigger language plpgsql security definer set search_path = public as $$
declare p profils; si sites; mx integer;
begin
  select * into p from profils where user_id = new.user_id;
  select * into si from sites where id = new.site_id;
  if p.entreprise_id is null or si.entreprise_id is distinct from p.entreprise_id then
    raise exception 'Site hors de l''entreprise du compte' using errcode = 'P0001';
  end if;
  if not p.actif then return new; end if;
  mx := (public.droits_entreprise(p.entreprise_id)->>'maxUtilisateursSite')::int;
  if mx is not null and public.nb_actifs_site(new.site_id, new.user_id) + 1 > mx then
    raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, si.nom using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists gmao_quota_profil_sites on public.profil_sites;
create trigger gmao_quota_profil_sites before insert on public.profil_sites
  for each row execute function public.quota_profil_sites();

create or replace function public.quota_sites()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim jsonb; mx integer;
begin
  if not new.actif then return new; end if;
  if tg_op = 'UPDATE' and old.actif then return new; end if;
  lim := public.droits_entreprise(new.entreprise_id);
  mx := (lim->>'maxSites')::int;
  if mx is not null and (select count(*) from sites where entreprise_id = new.entreprise_id and actif and id <> new.id) + 1 > mx then
    raise exception 'Quota atteint : % site(s) maximum (pack %)', mx, lim->>'packNom' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists gmao_quota_sites on public.sites;
create trigger gmao_quota_sites before insert or update of actif on public.sites
  for each row execute function public.quota_sites();

-- ---------- utilisation (écran Équipe) ----------
create or replace function public.utilisation()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); lim jsonb;
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  lim := public.droits_entreprise(ent);
  return jsonb_build_object(
    'actifs', public.nb_actifs_entreprise(ent, null), 'maxTotal', lim->'maxUtilisateursTotal',
    'maxSite', lim->'maxUtilisateursSite', 'maxSites', lim->'maxSites',
    'sites', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nom', s.nom, 'actifs', public.nb_actifs_site(s.id, null)) order by s.nom)
                       from sites s where s.entreprise_id = ent and s.actif), '[]'::jsonb),
    'affectations', coalesce((select jsonb_agg(jsonb_build_object('userId', ps.user_id, 'siteId', ps.site_id))
                              from profil_sites ps join profils p on p.user_id = ps.user_id where p.entreprise_id = ent), '[]'::jsonb));
end $$;
revoke all on function public.utilisation() from public, anon;
grant execute on function public.utilisation() to authenticated;

-- ---------- affectation des sites d'un membre (responsable) ----------
create or replace function public.affecter_sites(cible uuid, liste uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); s uuid;
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = ent) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if coalesce(array_length(liste, 1), 0) = 0 then raise exception 'Choisissez au moins un site'; end if;
  if exists (select 1 from unnest(liste) x where x not in (select id from sites where entreprise_id = ent and actif)) then
    raise exception 'Site inconnu ou inactif';
  end if;
  delete from profil_sites where user_id = cible and site_id <> all (liste);
  foreach s in array liste loop
    insert into profil_sites (user_id, site_id) values (cible, s) on conflict do nothing;   -- quota vérifié par déclencheur
  end loop;
  update profils set site_defaut = liste[1] where user_id = cible and (site_defaut is null or site_defaut <> all (liste));
end $$;
revoke all on function public.affecter_sites(uuid, uuid[]) from public, anon;
grant execute on function public.affecter_sites(uuid, uuid[]) to authenticated;

-- ---------- invitation : contrôle (au nom du responsable) puis rattachement (fonction serveur) ----------
create or replace function public.preparer_invitation(p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); lim jsonb; mx integer; existant uuid; p profils; s record; v_email text := lower(trim(p_email));
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  lim := public.droits_entreprise(ent);
  if not coalesce((lim->>'ecriture')::boolean, false) then raise exception 'Abonnement suspendu ou expiré'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Adresse e-mail invalide'; end if;
  if p_role not in ('responsable','technicien','prestataire','magasinier','exploitation','pilote') then raise exception 'Rôle inconnu'; end if;
  if coalesce(array_length(p_sites, 1), 0) = 0 then raise exception 'Choisissez au moins un site'; end if;
  if exists (select 1 from unnest(p_sites) x where x not in (select id from sites where entreprise_id = ent and actif)) then
    raise exception 'Site inconnu ou inactif';
  end if;
  select u.id into existant from auth.users u where lower(u.email) = v_email limit 1;
  if existant is not null then
    select * into p from profils where user_id = existant;
    if p.entreprise_id = ent then raise exception 'Ce compte fait déjà partie de l''équipe'; end if;
    if p.entreprise_id is not null then raise exception 'Ce compte est rattaché à une autre entreprise'; end if;
  end if;
  mx := (lim->>'maxUtilisateursTotal')::int;
  if mx is not null and public.nb_actifs_entreprise(ent, null) + 1 > mx then
    raise exception 'Quota atteint : % utilisateur(s) actif(s) maximum (pack %). Désactivez un compte ou changez de pack.', mx, lim->>'packNom';
  end if;
  mx := (lim->>'maxUtilisateursSite')::int;
  if mx is not null then
    for s in select id, nom from sites where id = any (p_sites) loop
      if public.nb_actifs_site(s.id, null) + 1 > mx then
        raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, s.nom;
      end if;
    end loop;
  end if;
  return jsonb_build_object('entreprise_id', ent, 'invite_par', auth.uid(), 'user_id_existant', existant);
end $$;
revoke all on function public.preparer_invitation(text, text, uuid[]) from public, anon;
grant execute on function public.preparer_invitation(text, text, uuid[]) to authenticated;

-- Appelée uniquement par la fonction serveur « inviter » (clé secrète), jamais par l'appli.
create or replace function public.finaliser_invitation(p_user uuid, p_entreprise uuid, p_role text, p_nom text, p_sites uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_email text; s uuid;
begin
  select u.email into v_email from auth.users u where u.id = p_user;
  insert into profils (user_id, email, nom) values (p_user, v_email, coalesce(nullif(trim(p_nom), ''), split_part(v_email, '@', 1)))
    on conflict (user_id) do nothing;
  update profils set entreprise_id = p_entreprise, role = p_role, actif = true,
    nom = coalesce(nullif(trim(p_nom), ''), nom), site_defaut = p_sites[1] where user_id = p_user;   -- quota total : déclencheur
  foreach s in array p_sites loop
    insert into profil_sites (user_id, site_id) values (p_user, s) on conflict do nothing;      -- quota site : déclencheur
  end loop;
end $$;
revoke all on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) from public, anon, authenticated;
grant execute on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) to service_role;

-- Pour que la liste d'équipe montre les sites de chacun.
grant select on public.profil_sites to authenticated;

-- ===== 05_plateforme.sql — copie générée de supabase/plateforme.sql (empreinte 71ba3cdbc0aac34f) : ne pas modifier ici =====
-- GMAO terrain — Volet A, étape A4 : console plateforme (rejouable). À exécuter APRÈS quotas.sql.
-- Toutes les fonctions pf_* sont réservées à l'administrateur plateforme (table admins_plateforme)
-- et contournent volontairement le périmètre « mon entreprise » pour gérer les clients.
-- Démo commerciale : seule une entreprise marquée demo = true peut être réinitialisée
-- (ses fiches sont effacées puis rechargées ; les appareils se resynchronisent d'eux-mêmes).

alter table public.entreprises add column if not exists demo boolean not null default false;
alter table public.entreprises add column if not exists reinit_le timestamptz;

create or replace function public.exiger_admin()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_admin_plateforme() then raise exception 'Réservé à l''administrateur plateforme' using errcode = '42501'; end if;
end $$;

-- ---------- contrôle d'invitation commun (responsable ou plateforme) ----------
create or replace function public.controle_invitation(ent uuid, p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim jsonb; mx integer; existant uuid; p profils; s record; v_email text := lower(trim(p_email));
begin
  lim := public.droits_entreprise(ent);
  if lim is null then raise exception 'Entreprise sans abonnement'; end if;
  if not coalesce((lim->>'ecriture')::boolean, false) then raise exception 'Abonnement suspendu ou expiré'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Adresse e-mail invalide'; end if;
  if p_role not in ('responsable','technicien','prestataire','magasinier','exploitation','pilote') then raise exception 'Rôle inconnu'; end if;
  if coalesce(array_length(p_sites, 1), 0) = 0 then raise exception 'Choisissez au moins un site'; end if;
  if exists (select 1 from unnest(p_sites) x where x not in (select id from sites where entreprise_id = ent and actif)) then
    raise exception 'Site inconnu ou inactif';
  end if;
  select u.id into existant from auth.users u where lower(u.email) = v_email limit 1;
  if existant is not null then
    select * into p from profils where user_id = existant;
    if p.entreprise_id = ent then raise exception 'Ce compte fait déjà partie de l''équipe'; end if;
    if p.entreprise_id is not null then raise exception 'Ce compte est rattaché à une autre entreprise'; end if;
  end if;
  mx := (lim->>'maxUtilisateursTotal')::int;
  if mx is not null and public.nb_actifs_entreprise(ent, null) + 1 > mx then
    raise exception 'Quota atteint : % utilisateur(s) actif(s) maximum (pack %). Désactivez un compte ou changez de pack.', mx, lim->>'packNom';
  end if;
  mx := (lim->>'maxUtilisateursSite')::int;
  if mx is not null then
    for s in select id, nom from sites where id = any (p_sites) loop
      if public.nb_actifs_site(s.id, null) + 1 > mx then raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, s.nom; end if;
    end loop;
  end if;
  return jsonb_build_object('entreprise_id', ent, 'invite_par', auth.uid(), 'user_id_existant', existant);
end $$;
revoke all on function public.controle_invitation(uuid, text, text, uuid[]) from public, anon, authenticated;

create or replace function public.preparer_invitation(p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  return public.controle_invitation(public.mon_entreprise(), p_email, p_role, p_sites);
end $$;
revoke all on function public.preparer_invitation(text, text, uuid[]) from public, anon;
grant execute on function public.preparer_invitation(text, text, uuid[]) to authenticated;

create or replace function public.pf_preparer_invitation(p_entreprise uuid, p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return public.controle_invitation(p_entreprise, p_email, p_role, p_sites);
end $$;
revoke all on function public.pf_preparer_invitation(uuid, text, text, uuid[]) from public, anon;
grant execute on function public.pf_preparer_invitation(uuid, text, text, uuid[]) to authenticated;

-- ---------- liste des clients et usage ----------
create or replace function public.pf_entreprises()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(x order by x->>'nom') from (
    select jsonb_build_object(
      'id', e.id, 'code', e.code, 'nom', e.nom, 'statut', e.statut, 'demo', e.demo, 'creeLe', e.cree_le, 'reinitLe', e.reinit_le,
      'abonnement', public.droits_entreprise(e.id),
      'derogations', jsonb_build_object('maxSites', a.max_sites, 'maxUtilisateursSite', a.max_utilisateurs_site, 'maxUtilisateursTotal', a.max_utilisateurs_total),
      'actifs', public.nb_actifs_entreprise(e.id, null),
      'sites', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'nom', s.nom, 'actif', s.actif, 'actifs', public.nb_actifs_site(s.id, null)) order by s.nom), '[]'::jsonb) from sites s where s.entreprise_id = e.id),
      'responsables', (select coalesce(jsonb_agg(p.email order by p.email), '[]'::jsonb) from profils p where p.entreprise_id = e.id and p.role = 'responsable' and p.actif),
      'fiches', (select count(*) from fiches f where f.entreprise_id = e.id),
      'photos', (select count(*) from fiches f where f.entreprise_id = e.id and f.type = 'photos'),
      'derniereActivite', (select max(recu_le) from fiches f where f.entreprise_id = e.id)) x
    from entreprises e left join abonnements a on a.entreprise_id = e.id) q), '[]'::jsonb);
end $$;
revoke all on function public.pf_entreprises() from public, anon;
grant execute on function public.pf_entreprises() to authenticated;

-- ---------- création d'un client (entreprise + abonnement + premier site) ----------
create or replace function public.pf_creer_entreprise(p_code text, p_nom text, p_pack text, p_statut text, p_site_code text, p_site_nom text, p_demo boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ent uuid; site uuid; v_code text := upper(trim(p_code));
begin
  perform public.exiger_admin();
  if v_code !~ '^[A-Z0-9-]{2,20}$' then raise exception 'Code entreprise : 2 à 20 lettres majuscules, chiffres ou tirets'; end if;
  if coalesce(trim(p_nom), '') = '' or coalesce(trim(p_site_nom), '') = '' then raise exception 'Nom de l''entreprise et du site obligatoires'; end if;
  if not exists (select 1 from packs where code = p_pack) then raise exception 'Pack inconnu'; end if;
  if exists (select 1 from entreprises e2 where e2.code = v_code) then raise exception 'Ce code entreprise existe déjà'; end if;
  insert into entreprises (code, nom, statut, demo) values (v_code, trim(p_nom), coalesce(p_statut, 'essai'), coalesce(p_demo, false)) returning id into ent;
  insert into abonnements (entreprise_id, pack, statut) values (ent, p_pack, coalesce(p_statut, 'essai'));
  insert into sites (entreprise_id, code, nom) values (ent, upper(coalesce(nullif(trim(p_site_code), ''), 'S1')), trim(p_site_nom)) returning id into site;
  return jsonb_build_object('entrepriseId', ent, 'siteId', site);
end $$;
revoke all on function public.pf_creer_entreprise(text, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.pf_creer_entreprise(text, text, text, text, text, text, boolean) to authenticated;

-- ---------- abonnement : pack, statut, échéance, dérogations ----------
create or replace function public.pf_modifier_abonnement(p_entreprise uuid, p_pack text, p_statut text, p_fin date,
  p_max_sites integer, p_max_utilisateurs_site integer, p_max_utilisateurs_total integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  if p_statut not in ('essai','actif','suspendu','resilie') then raise exception 'Statut inconnu'; end if;
  if not exists (select 1 from packs where code = p_pack) then raise exception 'Pack inconnu'; end if;
  update abonnements set pack = p_pack, statut = p_statut, fin = p_fin, max_sites = p_max_sites,
    max_utilisateurs_site = p_max_utilisateurs_site, max_utilisateurs_total = p_max_utilisateurs_total
  where entreprise_id = p_entreprise;
  if not found then raise exception 'Entreprise sans abonnement'; end if;
  update entreprises set statut = p_statut where id = p_entreprise;
end $$;
revoke all on function public.pf_modifier_abonnement(uuid, text, text, date, integer, integer, integer) from public, anon;
grant execute on function public.pf_modifier_abonnement(uuid, text, text, date, integer, integer, integer) to authenticated;

create or replace function public.pf_ajouter_site(p_entreprise uuid, p_code text, p_nom text)
returns uuid language plpgsql security definer set search_path = public as $$
declare site uuid;
begin
  perform public.exiger_admin();
  if coalesce(trim(p_nom), '') = '' then raise exception 'Nom du site obligatoire'; end if;
  insert into sites (entreprise_id, code, nom) values (p_entreprise, upper(trim(p_code)), trim(p_nom)) returning id into site;   -- quota : déclencheur
  return site;
end $$;
revoke all on function public.pf_ajouter_site(uuid, text, text) from public, anon;
grant execute on function public.pf_ajouter_site(uuid, text, text) to authenticated;

-- ---------- démo commerciale réinitialisable ----------
create or replace function public.pf_j(j integer, hm text default null)
returns text language sql stable as $$
  select to_char((now() at time zone 'Africa/Casablanca')::date + j, 'YYYY-MM-DD') || coalesce('T' || hm, '')
$$;

-- Version d'origine (volets A-B) : remplacée par supabase/demo.sql (volet C), à exécuter après achats.sql.
create or replace function public.pf_reinitialiser_demo(p_entreprise uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  e entreprises; site uuid; k text; maint text := public.pf_j(0, to_char(now() at time zone 'Africa/Casablanca', 'HH24:MI'));
  l_site text; l_at text; l_li text; l_ut text; presse text; emb text; conv text; comp text;
  resp text; ta text; tb text; mag text; a1 text; a2 text; a3 text; a4 text; b3 text; b4 text; d1 text; d3 text; o1 text; o3 text; m1 text;
begin
  perform public.exiger_admin();
  select * into e from entreprises where id = p_entreprise;
  if not found or not e.demo then raise exception 'Seule une entreprise de démonstration peut être réinitialisée'; end if;
  select id into site from sites where entreprise_id = e.id and actif order by cree_le limit 1;
  if site is null then raise exception 'La démo n''a aucun site actif'; end if;

  delete from fiches where entreprise_id = e.id;   -- démo uniquement : rien d'autre n'est jamais supprimé
  k := substr(md5(e.id::text || clock_timestamp()::text), 1, 8);
  l_site := k || '-loc0'; l_at := k || '-loc1'; l_li := k || '-loc2'; l_ut := k || '-loc3';
  presse := k || '-eq1'; emb := k || '-eq2'; conv := k || '-eq3'; comp := k || '-eq4';
  resp := k || '-p1'; ta := k || '-p2'; tb := k || '-p3'; mag := k || '-p4';
  a1 := k || '-a1'; a2 := k || '-a2'; a3 := k || '-a3'; d1 := k || '-d1'; d3 := k || '-d3'; o1 := k || '-o1'; m1 := k || '-m1';
  a4 := k || '-a4'; b3 := k || '-b3'; b4 := k || '-b4'; o3 := k || '-o3';

  insert into fiches (id, type, entreprise_id, site_id, data)
  select v.id, v.type, e.id, case when v.type in ('personnes','articles') then null else site end,
         v.data || jsonb_build_object('id', v.id, 'creeLe', coalesce(v.data->>'creeLe', maint), 'creePar', coalesce(v.data->>'creePar', 'Démo'), 'modifieLe', maint, 'modifiePar', 'Démo')
                || case when v.type in ('personnes','articles') then '{}'::jsonb else jsonb_build_object('siteId', site) end
  from (values
    (l_site, 'localisations', jsonb_build_object('code', 'SITE', 'nom', 'Usine', 'parentId', null)),
    (l_at, 'localisations', jsonb_build_object('code', 'AT-PR', 'nom', 'Atelier presses', 'parentId', l_site)),
    (l_li, 'localisations', jsonb_build_object('code', 'LG-CD', 'nom', 'Ligne conditionnement', 'parentId', l_site)),
    (l_ut, 'localisations', jsonb_build_object('code', 'UT', 'nom', 'Utilités', 'parentId', l_site)),
    (presse, 'equipements', jsonb_build_object('code', 'PRESSE-01', 'designation', 'Presse hydraulique 200 t', 'localisationId', l_at, 'famille', 'presse', 'criticite', '4', 'actif', true)),
    (emb, 'equipements', jsonb_build_object('code', 'EMB-02', 'designation', 'Emballeuse ligne 2', 'localisationId', l_li, 'famille', 'emballage', 'criticite', '3', 'actif', true)),
    (conv, 'equipements', jsonb_build_object('code', 'CONV-03', 'designation', 'Convoyeur sortie ligne 2', 'localisationId', l_li, 'famille', 'convoyage', 'criticite', '2', 'actif', true)),
    (comp, 'equipements', jsonb_build_object('code', 'COMP-01', 'designation', 'Compresseur d’air 55 kW', 'localisationId', l_ut, 'famille', 'utilité', 'criticite', '4', 'actif', true)),
    (resp, 'personnes', jsonb_build_object('nom', 'Responsable maintenance', 'role', 'responsable', 'actif', true)),
    (ta, 'personnes', jsonb_build_object('nom', 'Technicien A (mécanique)', 'role', 'technicien', 'actif', true)),
    (tb, 'personnes', jsonb_build_object('nom', 'Technicien B (automatisme)', 'role', 'technicien', 'actif', true)),
    (mag, 'personnes', jsonb_build_object('nom', 'Magasinier', 'role', 'magasinier', 'actif', true)),
    (a1, 'articles', jsonb_build_object('ref', 'J-VER-80', 'designation', 'Joint de vérin Ø80', 'unite', 'u', 'stockMin', 2, 'actif', true)),
    (a2, 'articles', jsonb_build_object('ref', 'HUI-HV46', 'designation', 'Huile hydraulique HV46', 'unite', 'L', 'stockMin', 20, 'actif', true)),
    (a3, 'articles', jsonb_build_object('ref', 'FIL-AIR', 'designation', 'Filtre à air compresseur', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (a4, 'articles', jsonb_build_object('ref', 'ROUL-TD-50', 'designation', 'Rouleau tendeur convoyeur Ø50', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (k || '-m0d', 'mouvements', jsonb_build_object('articleId', a4, 'type', 'entree', 'qte', 2, 'otId', null, 'le', public.pf_j(0, '09:15'), 'motif', 'Livraison fournisseur')),
    -- volet B : le convoyeur attend un rouleau (demande urgente, en stock) ; 2 L d'huile pris en urgence, à vérifier
    (b3, 'besoins', jsonb_build_object('ref', 'BES-DEMO-0001', 'otId', o3, 'equipementId', conv, 'articleId', a4, 'qte', 1, 'unite', 'u', 'urgent', true, 'statut', 'demande', 'note', 'Arrêt ligne 2', 'demandeur', 'Technicien B (automatisme)', 'demandeLe', public.pf_j(0, '08:30'), 'creeLe', public.pf_j(0, '08:30'))),
    (b4, 'besoins', jsonb_build_object('ref', 'BES-DEMO-0002', 'otId', o3, 'equipementId', conv, 'articleId', a2, 'qte', 2, 'unite', 'L', 'urgent', true, 'statut', 'demande', 'note', 'Retrait urgent', 'demandeur', 'Technicien B (automatisme)', 'demandeLe', public.pf_j(0, '08:10'), 'creeLe', public.pf_j(0, '08:10'))),
    (k || '-m4', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'remise', 'qte', -2, 'urgent', true, 'aVerifier', true, 'besoinId', b4, 'otId', o3, 'le', public.pf_j(0, '08:10'), 'motif', 'Retrait urgent OT-DEMO-0003', 'creePar', 'Technicien B (automatisme)')),
    (k || '-m0a', 'mouvements', jsonb_build_object('articleId', a1, 'type', 'entree', 'qte', 3, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0b', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'entree', 'qte', 60, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0c', 'mouvements', jsonb_build_object('articleId', a3, 'type', 'entree', 'qte', 1, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (m1, 'mouvements', jsonb_build_object('articleId', a1, 'type', 'sortie', 'qte', -1, 'otId', o1, 'le', public.pf_j(-3, '09:00'), 'motif', null)),
    (d1, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0001', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Opérateur presse', 'service', 'Production'), 'equipementId', presse, 'besoin', 'corriger', 'constat', 'Le vérin ne tient plus la position', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(-3, '08:00'), 'precisionHeure', 'exacte', 'statut', 'traitement_organise', 'priseEnChargePar', ta, 'priseEnChargeLe', public.pf_j(-3, '08:05'), 'creeLe', public.pf_j(-3, '08:03'))),
    (k || '-d2', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0002', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Chef de ligne', 'service', 'Conditionnement'), 'equipementId', emb, 'besoin', 'verifier', 'constat', 'Bruit anormal au niveau du convoyeur d’entrée', 'etat', 'degrade', 'impact', 'aucun_constate', 'heureFait', public.pf_j(-1, '14:20'), 'precisionHeure', 'estimee', 'statut', 'a_examiner', 'creeLe', public.pf_j(-1, '14:35'))),
    (d3, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0003', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie, frottement côté moteur', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(0, '07:40'), 'precisionHeure', 'estimee', 'statut', 'traitement_organise', 'priseEnChargePar', tb, 'priseEnChargeLe', public.pf_j(0, '07:50'), 'creeLe', public.pf_j(0, '07:45'))),
    (k || '-d4', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0004', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie', 'etat', 'degrade', 'impact', 'reduit', 'precisionHeure', 'inconnue', 'statut', 'close_sans_travail', 'motifClassement', 'Recentrage par l’opérateur', 'creeLe', public.pf_j(-12, '10:00'))),
    (o1, 'ots', jsonb_build_object('ref', 'OT-DEMO-0001', 'demandeIds', jsonb_build_array(d1), 'equipementId', presse, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'cloturee',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i1', 'personneId', ta, 'role', 'intervenant', 'depuis', public.pf_j(-3, '08:10'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic', 'remplacement'), 'travaux', 'Remplacement du joint de vérin, purge du circuit.', 'resultat', 'resolu', 'cause', 'Joint de vérin usé', 'certitudeCause', 'probable', 'familleDefaut', 'hydraulique',
        'avecArret', 'oui', 'arretDebut', public.pf_j(-3, '08:00'), 'arretFin', public.pf_j(-3, '10:30'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc1', 'articleId', a1, 'qte', 1, 'mouvementId', m1, 'annulee', false)), 'reserves', '[]'::jsonb, 'attentes', '[]'::jsonb,
        'clotureLe', public.pf_j(-3, '11:20'), 'cloturePar', 'Responsable maintenance', 'creeLe', public.pf_j(-3, '08:05'))),
    (o3, 'ots', jsonb_build_object('ref', 'OT-DEMO-0003', 'demandeIds', jsonb_build_array(d3), 'equipementId', conv, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'suspendue',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i3', 'personneId', tb, 'role', 'intervenant', 'depuis', public.pf_j(0, '07:50'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic'), 'travaux', 'Rouleau tendeur grippé.', 'familleDefaut', 'mecanique', 'avecArret', 'oui', 'arretDebut', public.pf_j(0, '07:40'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc3', 'besoinId', b4, 'articleId', a2, 'qte', 2, 'mouvementId', null, 'annulee', false)), 'reserves', '[]'::jsonb,
        'attentes', jsonb_build_array(jsonb_build_object('id', k || '-at3', 'motif', 'piece', 'besoinId', b3, 'detail', 'Rouleau tendeur convoyeur Ø50', 'depuis', public.pf_j(0, '08:30'), 'fin', null, 'responsableId', mag)),
        'creeLe', public.pf_j(0, '07:50'))),
    (k || '-pg1', 'programmes', jsonb_build_object('equipementId', comp, 'libelle', 'Vidange et filtre compresseur', 'modele', 'entretien', 'periodiciteJours', 90, 'prochaineEcheance', public.pf_j(-2), 'regle', 'fixe', 'instruction', 'Consigner selon procédure site, vidanger, remplacer le filtre à air, essai à vide puis en charge.', 'actif', true)),
    (k || '-pg2', 'programmes', jsonb_build_object('equipementId', presse, 'libelle', 'Contrôle niveau et fuites hydrauliques', 'modele', 'inspection', 'periodiciteJours', 30, 'prochaineEcheance', public.pf_j(5), 'regle', 'apres_realisation', 'instruction', 'Niveau bâche, état flexibles, traces de fuite.', 'actif', true))
  ) as v(id, type, data);

  update entreprises set reinit_le = now() where id = e.id;
  return jsonb_build_object('fiches', (select count(*) from fiches where entreprise_id = e.id), 'reinitLe', now());
end $$;
revoke all on function public.pf_reinitialiser_demo(uuid) from public, anon;
grant execute on function public.pf_reinitialiser_demo(uuid) to authenticated;

-- ---------- profil : date de réinitialisation (les appareils se resynchronisent) ----------
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
    'adminPlateforme', public.est_admin_plateforme());
end $$;
revoke all on function public.mon_profil() from public, anon;
grant execute on function public.mon_profil() to authenticated;

-- ===== 06_durcissement.sql — copie générée de supabase/durcissement.sql (empreinte 89506e1ee37bfa6a) : ne pas modifier ici =====
-- GMAO terrain — durcissement (recette A5, 6 nov. 2026). Rejouable.
-- Les fonctions internes ne sont appelées que depuis d'autres fonctions SECURITY DEFINER
-- (exécutées avec les droits du propriétaire) : aucune raison de les exposer à l'API.
-- Constat : nb_actifs_entreprise / nb_actifs_site (SECURITY DEFINER) étaient appelables sans compte
-- et révélaient le nombre d'utilisateurs actifs d'une entreprise dont on connaîtrait l'identifiant.
revoke execute on function public.nb_actifs_entreprise(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.nb_actifs_site(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.exiger_admin() from public, anon, authenticated;
revoke execute on function public.peut_ecrire(text, text) from public, anon, authenticated;
revoke execute on function public.module_de(text) from public, anon, authenticated;
revoke execute on function public.uuid_ou_null(text) from public, anon, authenticated;
revoke execute on function public.pf_j(integer, text) from public, anon, authenticated;

-- Contrôle : aucune fonction du schéma public ne doit rester appelable sans compte.
select p.proname as encore_ouverte_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');

-- Conseiller sécurité Supabase (recette A5) :
-- 1) chemin de recherche fixé pour les fonctions utilitaires
alter function public.peut_ecrire(text, text) set search_path = public;
alter function public.module_de(text) set search_path = public;
alter function public.uuid_ou_null(text) set search_path = public;
alter function public.pf_j(integer, text) set search_path = public;
-- 2) fonctions de déclencheurs : jamais appelées directement (les déclencheurs fonctionnent sans ce droit)
revoke execute on function public.creer_profil() from public, anon, authenticated;
revoke execute on function public.quota_profils() from public, anon, authenticated;
revoke execute on function public.quota_profil_sites() from public, anon, authenticated;
revoke execute on function public.quota_sites() from public, anon, authenticated;
-- 3) droits_entreprise(ent) : utilisée seulement par d'autres fonctions ; pas d'appel direct
--    (sinon un compte connecté pourrait lire le pack d'une autre entreprise dont il connaîtrait l'id).
revoke execute on function public.droits_entreprise(uuid) from public, anon, authenticated;
-- Restent appelables par un compte connecté (avertissements acceptés : chaque fonction vérifie
-- elle-même rôle, entreprise et site) : push_fiches, mon_profil, definir_profil, affecter_sites,
-- utilisation, preparer_invitation, pf_* (administrateur plateforme), et mon_role / mon_entreprise /
-- mes_sites / est_admin_plateforme, nécessaires aux règles de lecture (RLS).

-- ===== 07_magasin.sql — copie générée de supabase/magasin.sql (empreinte 9ec381d44a2c2442) : ne pas modifier ici =====
-- GMAO terrain — Volet B, étape B2 : magasin relié au terrain (rejouable). APRÈS durcissement.sql.
-- Voir docs/VOLET_B_CONCEPTION.md. Nouveau type de fiche « besoins » (par site, module magasin).
-- Règles ajoutées à push_fiches :
--   besoins   : technicien / prestataire créent, complètent la description, annulent ; seuls magasinier
--               et responsable réservent (qteReservee), annoncent un délai ou déclarent « indisponible ».
--   mouvements: technicien / prestataire → uniquement retrait urgent (remise urgente) et retour, toujours
--               rattachés à une intervention ou un besoin ; réception, ajustement, remise normale = magasin.
--               Un mouvement n'est jamais modifié, sauf sa vérification (verifieLe / verifiePar) par le magasin.
--   site      : un besoin hérite du site de son intervention ; un mouvement de celui de son besoin / intervention.

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in ('localisations','equipements','personnes',
  'demandes','ots','programmes','articles','mouvements','journal','photos','besoins'));

create or replace function public.module_de(t text)
returns text language sql immutable set search_path = public as $$
  select case when t in ('articles', 'mouvements', 'besoins') then 'magasin' when t = 'programmes' then 'preventif' else 'base' end
$$;
create or replace function public.peut_ecrire(r text, t text)
returns boolean language sql immutable set search_path = public as $$
  select case
    when r is null or r = 'pilote' then false
    when r = 'responsable' then true
    when t in ('demandes', 'journal', 'photos') then true
    when t = 'ots' then r in ('technicien', 'prestataire')
    when t = 'articles' then r = 'magasinier'
    when t in ('mouvements', 'besoins') then r in ('magasinier', 'technicien', 'prestataire')
    else false
  end
$$;
revoke execute on function public.module_de(text) from public, anon, authenticated;
revoke execute on function public.peut_ecrire(text, text) from public, anon, authenticated;

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- Renvoi identique d'un mouvement déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t = 'mouvements' and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? public.module_de(cible)) then
      motif := 'module « ' || public.module_de(cible) || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    end if;

    if motif is null and t not in ('personnes', 'articles') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- ===== 08_achats.sql — copie générée de supabase/achats.sql (empreinte bec7170b8c2dd45c) : ne pas modifier ici =====
-- GMAO terrain — Volet C, étape C2 : seuils, achats et valorisation (rejouable). APRÈS magasin.sql.
-- Voir docs/VOLET_C_CONCEPTION.md.
--   seuils        : module magasin ; le magasinier propose, le responsable valide.
--   achats        : module achats ; magasinier / responsable rédigent ; seul le responsable valide, refuse ou
--                   demande de compléter ; le rôle « achats » renseigne la commande externe d'une demande validée.
--   valorisations : module achats ; prix d'une entrée de stock ; correction réservée au responsable.
--   Les prix ne sont lisibles que par responsable, magasinier, achats et pilote : fiches achats / valorisations
--   ET lignes de journal qui les concernent (sinon l'historique « avant / après » révélerait les montants).
--   Rôle facultatif « achats » (V3 §24).

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in ('localisations','equipements','personnes',
  'demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations'));

alter table public.profils drop constraint if exists profils_role_check;
alter table public.profils add constraint profils_role_check
  check (role in ('responsable','technicien','prestataire','magasinier','achats','exploitation','pilote'));

create or replace function public.module_de(t text)
returns text language sql immutable set search_path = public as $$
  select case when t in ('articles', 'mouvements', 'besoins', 'seuils') then 'magasin'
              when t in ('achats', 'valorisations') then 'achats'
              when t = 'programmes' then 'preventif' else 'base' end
$$;
create or replace function public.peut_ecrire(r text, t text)
returns boolean language sql immutable set search_path = public as $$
  select case
    when r is null or r = 'pilote' then false
    when r = 'responsable' then true
    when t in ('demandes', 'journal', 'photos') then true
    when t = 'ots' then r in ('technicien', 'prestataire')
    when t in ('articles', 'seuils') then r = 'magasinier'
    when t in ('mouvements', 'besoins') then r in ('magasinier', 'technicien', 'prestataire')
    when t in ('achats', 'valorisations') then r in ('magasinier', 'achats')
    else false
  end
$$;
revoke execute on function public.module_de(text) from public, anon, authenticated;
revoke execute on function public.peut_ecrire(text, text) from public, anon, authenticated;

-- Qui peut voir les montants (V3 §24 : prix masqués aux techniciens, y compris par l'API).
create or replace function public.voit_couts()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.mon_role() in ('responsable', 'magasinier', 'achats', 'pilote'), false)
$$;
revoke all on function public.voit_couts() from public, anon;
grant execute on function public.voit_couts() to authenticated;

drop policy if exists "lecture equipe" on public.fiches;
create policy "lecture equipe" on public.fiches for select to authenticated using (
  public.mon_role() is not null
  and entreprise_id = public.mon_entreprise()
  and (site_id is null or site_id in (select public.mes_sites()))
  and (public.voit_couts()
       or not (type in ('achats', 'valorisations') or (type = 'journal' and data->>'entite' in ('achats', 'valorisations')))));

create or replace function public.controle_invitation(ent uuid, p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim jsonb; mx integer; existant uuid; p profils; s record; v_email text := lower(trim(p_email));
begin
  lim := public.droits_entreprise(ent);
  if lim is null then raise exception 'Entreprise sans abonnement'; end if;
  if not coalesce((lim->>'ecriture')::boolean, false) then raise exception 'Abonnement suspendu ou expiré'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Adresse e-mail invalide'; end if;
  if p_role not in ('responsable','technicien','prestataire','magasinier','achats','exploitation','pilote') then raise exception 'Rôle inconnu'; end if;
  if coalesce(array_length(p_sites, 1), 0) = 0 then raise exception 'Choisissez au moins un site'; end if;
  if exists (select 1 from unnest(p_sites) x where x not in (select id from sites where entreprise_id = ent and actif)) then
    raise exception 'Site inconnu ou inactif';
  end if;
  select u.id into existant from auth.users u where lower(u.email) = v_email limit 1;
  if existant is not null then
    select * into p from profils where user_id = existant;
    if p.entreprise_id = ent then raise exception 'Ce compte fait déjà partie de l''équipe'; end if;
    if p.entreprise_id is not null then raise exception 'Ce compte est rattaché à une autre entreprise'; end if;
  end if;
  mx := (lim->>'maxUtilisateursTotal')::int;
  if mx is not null and public.nb_actifs_entreprise(ent, null) + 1 > mx then
    raise exception 'Quota atteint : % utilisateur(s) actif(s) maximum (pack %). Désactivez un compte ou changez de pack.', mx, lim->>'packNom';
  end if;
  mx := (lim->>'maxUtilisateursSite')::int;
  if mx is not null then
    for s in select id, nom from sites where id = any (p_sites) loop
      if public.nb_actifs_site(s.id, null) + 1 > mx then raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, s.nom; end if;
    end loop;
  end if;
  return jsonb_build_object('entreprise_id', ent, 'invite_par', auth.uid(), 'user_id_existant', existant);
end $$;
revoke all on function public.controle_invitation(uuid, text, text, uuid[]) from public, anon, authenticated;

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- Renvoi identique d'un mouvement déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t = 'mouvements' and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? public.module_de(cible)) then
      motif := 'module « ' || public.module_de(cible) || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    end if;

    if motif is null and t not in ('personnes', 'articles') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- ===== 09_energie.sql — copie générée de supabase/energie.sql (empreinte c790cb7436e182ad) : ne pas modifier ici =====
-- GMAO terrain — Volet D, étape D2 : énergie et eau + réglages de l'entreprise (rejouable). APRÈS achats.sql.
-- Voir docs/VOLET_D_CONCEPTION.md.
--   compteurs        : module energie ; référentiel du responsable. Un compteur déjà relevé ne change ni de mode,
--                      ni d'unité, ni de coefficient : on déclare une rupture (relevé de nature « rupture »).
--   releves          : module energie ; saisis par technicien, prestataire, exploitation (et responsable). Jamais
--                      modifiés : une correction est un nouveau relevé (remplaceId) ; seul le responsable qualifie
--                      (decision confirme / invalide, motif). Site = celui du compteur.
--   factures_energie : module energie ; saisies par le responsable ou les achats ; lecture restreinte comme les prix
--                      (voit_couts), y compris le journal et les pièces jointes (photos dont parentType = factures_energie).
--   parametres       : module base ; une fiche par entreprise (id « parametres-<entreprise> »), responsable seul.
--                      clotureParResponsable = true : seul le responsable clôture une intervention.

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres'));

create or replace function public.module_de(t text)
returns text language sql immutable set search_path = public as $$
  select case when t in ('articles', 'mouvements', 'besoins', 'seuils') then 'magasin'
              when t in ('achats', 'valorisations') then 'achats'
              when t in ('compteurs', 'releves', 'factures_energie') then 'energie'
              when t = 'programmes' then 'preventif' else 'base' end
$$;
create or replace function public.peut_ecrire(r text, t text)
returns boolean language sql immutable set search_path = public as $$
  select case
    when r is null or r = 'pilote' then false
    when r = 'responsable' then true
    when t in ('demandes', 'journal', 'photos') then true
    when t = 'ots' then r in ('technicien', 'prestataire')
    when t in ('articles', 'seuils') then r = 'magasinier'
    when t in ('mouvements', 'besoins') then r in ('magasinier', 'technicien', 'prestataire')
    when t in ('achats', 'valorisations') then r in ('magasinier', 'achats')
    when t = 'releves' then r in ('technicien', 'prestataire', 'exploitation')
    when t = 'factures_energie' then r = 'achats'
    else false
  end
$$;
revoke execute on function public.module_de(text) from public, anon, authenticated;
revoke execute on function public.peut_ecrire(text, text) from public, anon, authenticated;

create or replace function public.cloture_par_responsable(ent uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select (data->>'clotureParResponsable')::boolean from fiches
                   where id = 'parametres-' || ent::text and type = 'parametres' and entreprise_id = ent), false)
$$;
revoke all on function public.cloture_par_responsable(uuid) from public, anon, authenticated;

drop policy if exists "lecture equipe" on public.fiches;
create policy "lecture equipe" on public.fiches for select to authenticated using (
  public.mon_role() is not null
  and entreprise_id = public.mon_entreprise()
  and (site_id is null or site_id in (select public.mes_sites()))
  and (public.voit_couts()
       or not (type in ('achats', 'valorisations', 'factures_energie')
               or (type = 'journal' and data->>'entite' in ('achats', 'valorisations', 'factures_energie'))
               or (type = 'photos' and data->>'parentType' = 'factures_energie'))));

create index if not exists fiches_releves_compteur on public.fiches ((data->>'compteurId')) where type = 'releves';

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? public.module_de(cible)) then
      motif := 'module « ' || public.module_de(cible) || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    elsif t = 'ots' and r <> 'responsable' and p->>'statut' = 'cloturee' and public.cloture_par_responsable(ent) then
      motif := 'clôture réservée au responsable (réglage de l''entreprise) : terminez l''intervention, le responsable la clôture';
    -- réglages de l'entreprise : une seule fiche, d'identifiant fixe
    elsif t = 'parametres' and f->>'id' <> ('parametres-' || ent::text) then
      motif := 'paramètres : identifiant réservé à l''entreprise';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    -- volet D : compteurs (référentiel du responsable), relevés jamais modifiés, factures à lecture restreinte
    elsif t = 'compteurs' and ex.id is not null
          and ((p ? 'mode' and p->'mode' is distinct from ex.data->'mode') or (p ? 'unite' and p->'unite' is distinct from ex.data->'unite')
               or (p ? 'coefficient' and p->'coefficient' is distinct from ex.data->'coefficient'))
          and exists (select 1 from fiches x where x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = ex.id) then
      motif := 'compteur déjà relevé : mode, unité et coefficient ne changent que par une rupture déclarée';
    elsif t = 'releves' and ex.id is null and not exists (select 1 from fiches c where c.id = p->>'compteurId' and c.type = 'compteurs' and c.entreprise_id = ent) then
      motif := 'un relevé se rattache à un compteur connu';
    elsif t = 'releves' and ex.id is null and r <> 'responsable' and (p ? 'decision' or p ? 'decidePar' or p ? 'decideLe') then
      motif := 'qualification d''un relevé : réservée au responsable';
    elsif t = 'releves' and ex.id is null and coalesce(p->>'remplaceId', '') <> '' and not exists (
            select 1 from fiches x where x.id = p->>'remplaceId' and x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = p->>'compteurId') then
      motif := 'une correction remplace un relevé du même compteur';
    elsif t = 'releves' and ex.id is not null and (r <> 'responsable' or exists (
            select 1 from jsonb_object_keys(p) k where k not in ('decision', 'motifDecision', 'decideLe', 'decidePar', 'modifieLe', 'modifiePar'))) then
      motif := 'un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)';
    end if;

    if motif is null and t not in ('personnes', 'articles', 'parametres') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        case when t = 'releves' then (select site_id from fiches where id = p->>'compteurId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- ===== 10_mise_en_service.sql — copie générée de supabase/mise_en_service.sql (empreinte 6c8c210c16e06f31) : ne pas modifier ici =====
-- GMAO terrain — mise en service des clients + D2 bis (rejouable). APRÈS energie.sql.
-- Voir docs/DISCUSSION_MODELE_DONNEES.md (§3 compteurs, §5 démarrage d'un client) et docs/CLASSIFICATION_PARC.md.
--   D2 bis       : le module d'un compteur dépend de son usage : « equipement » (heures, cycles) → preventif (pack Pro),
--                  « ressource » → energie (pack Entreprise) ; idem pour ses relevés et son journal. Usage figé après
--                  le premier relevé.
--   fournisseurs : liste commune à l'entreprise (module magasin) ; écrite par responsable, magasinier, achats.
--   Reprise      : pf_referentiel, pf_importer (vérification à blanc ou import, tout ou rien, lot annulable),
--                  pf_annuler_lot (seulement si le client n'a rien saisi depuis), pf_mes_lire / pf_mes_etape (étapes de
--                  mise en service). Réservé à l'administrateur plateforme.

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs'));

create or replace function public.module_de(t text)
returns text language sql immutable set search_path = public as $$
  select case when t in ('articles', 'mouvements', 'besoins', 'seuils', 'fournisseurs') then 'magasin'
              when t in ('achats', 'valorisations') then 'achats'
              when t in ('compteurs', 'releves', 'factures_energie') then 'energie'
              when t = 'programmes' then 'preventif' else 'base' end
$$;
create or replace function public.peut_ecrire(r text, t text)
returns boolean language sql immutable set search_path = public as $$
  select case
    when r is null or r = 'pilote' then false
    when r = 'responsable' then true
    when t in ('demandes', 'journal', 'photos') then true
    when t = 'ots' then r in ('technicien', 'prestataire')
    when t in ('articles', 'seuils') then r = 'magasinier'
    when t in ('mouvements', 'besoins') then r in ('magasinier', 'technicien', 'prestataire')
    when t in ('achats', 'valorisations') then r in ('magasinier', 'achats')
    when t = 'fournisseurs' then r in ('magasinier', 'achats')
    when t = 'releves' then r in ('technicien', 'prestataire', 'exploitation')
    when t = 'factures_energie' then r = 'achats'
    else false
  end
$$;
revoke execute on function public.module_de(text) from public, anon, authenticated;
revoke execute on function public.peut_ecrire(text, text) from public, anon, authenticated;

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean; mod text; u text;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- D2 bis : un compteur d'équipement (heures, cycles) relève du préventif, un compteur de ressource de l'énergie.
    mod := public.module_de(cible);
    if cible in ('compteurs', 'releves') then
      u := case
        when t = 'compteurs' then coalesce(p->>'usage', ex.data->>'usage')
        when t = 'releves' then (select c.data->>'usage' from fiches c where c.id = coalesce(p->>'compteurId', ex.data->>'compteurId') and c.entreprise_id = ent)
        else (select case when x.type = 'compteurs' then x.data->>'usage'
                          else (select c.data->>'usage' from fiches c where c.id = x.data->>'compteurId' and c.entreprise_id = ent) end
              from fiches x where x.id = p->>'entiteId' and x.entreprise_id = ent)
      end;
      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? mod) then
      motif := 'module « ' || mod || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    elsif t = 'ots' and r <> 'responsable' and p->>'statut' = 'cloturee' and public.cloture_par_responsable(ent) then
      motif := 'clôture réservée au responsable (réglage de l''entreprise) : terminez l''intervention, le responsable la clôture';
    -- réglages de l'entreprise : une seule fiche, d'identifiant fixe
    elsif t = 'parametres' and f->>'id' <> ('parametres-' || ent::text) then
      motif := 'paramètres : identifiant réservé à l''entreprise';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    -- volet D : compteurs (référentiel du responsable), relevés jamais modifiés, factures à lecture restreinte
    elsif t = 'compteurs' and ex.id is not null
          and ((p ? 'mode' and p->'mode' is distinct from ex.data->'mode') or (p ? 'unite' and p->'unite' is distinct from ex.data->'unite')
               or (p ? 'coefficient' and p->'coefficient' is distinct from ex.data->'coefficient')
               or (p ? 'usage' and p->'usage' is distinct from ex.data->'usage'))
          and exists (select 1 from fiches x where x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = ex.id) then
      motif := 'compteur déjà relevé : usage, mode, unité et coefficient ne changent plus (rupture déclarée ou nouveau compteur)';
    elsif t = 'releves' and ex.id is null and not exists (select 1 from fiches c where c.id = p->>'compteurId' and c.type = 'compteurs' and c.entreprise_id = ent) then
      motif := 'un relevé se rattache à un compteur connu';
    elsif t = 'releves' and ex.id is null and r <> 'responsable' and (p ? 'decision' or p ? 'decidePar' or p ? 'decideLe') then
      motif := 'qualification d''un relevé : réservée au responsable';
    elsif t = 'releves' and ex.id is null and coalesce(p->>'remplaceId', '') <> '' and not exists (
            select 1 from fiches x where x.id = p->>'remplaceId' and x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = p->>'compteurId') then
      motif := 'une correction remplace un relevé du même compteur';
    elsif t = 'releves' and ex.id is not null and (r <> 'responsable' or exists (
            select 1 from jsonb_object_keys(p) k where k not in ('decision', 'motifDecision', 'decideLe', 'decidePar', 'modifieLe', 'modifiePar'))) then
      motif := 'un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)';
    end if;

    if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        case when t = 'releves' then (select site_id from fiches where id = p->>'compteurId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- ---------- reprise des données d'un client (console plateforme) ----------
create table if not exists public.pf_lots_import (
  id            text primary key,
  entreprise_id uuid not null references public.entreprises(id),
  cree_le       timestamptz not null default now(),
  par           uuid,
  fichier       text,
  resume        jsonb not null default '{}'::jsonb,
  seq_fin       bigint,                       -- dernière fiche du lot : toute fiche reçue après = activité
  annule_le     timestamptz
);
alter table public.pf_lots_import add column if not exists seq_fin bigint;
alter table public.pf_lots_import enable row level security;     -- aucune politique : accès par les fonctions pf_* seulement
create table if not exists public.pf_mise_en_service (
  entreprise_id uuid primary key references public.entreprises(id),
  etapes        jsonb not null default '{}'::jsonb,
  maj_le        timestamptz not null default now()
);
alter table public.pf_mise_en_service enable row level security;

-- Codes déjà présents chez le client (pour relier le kit à l'existant et refuser les doublons).
create or replace function public.pf_referentiel(p_entreprise uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return jsonb_build_object(
    'sites', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', code, 'nom', nom) order by code), '[]'::jsonb) from sites where entreprise_id = p_entreprise and actif),
    'localisations', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', data->>'code', 'siteId', site_id)), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'localisations'),
    'equipements', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', data->>'code', 'siteId', site_id)), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'equipements'),
    'compteurs', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', data->>'code', 'siteId', site_id, 'unite', data->>'unite')), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'compteurs'),
    'articles', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ref', data->>'ref')), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'articles'),
    'fournisseurs', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nom', data->>'nom')), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'fournisseurs'),
    'personnes', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nom', data->>'nom')), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'personnes'));
end $$;
revoke all on function public.pf_referentiel(uuid) from public, anon;
grant execute on function public.pf_referentiel(uuid) to authenticated;

-- Import d'un lot : tout ou rien. p_essai = vérification à blanc (même contrôles, rien n'est gardé).
create or replace function public.pf_importer(p_entreprise uuid, p_lot text, p_fichier text, p_fiches jsonb, p_essai boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; t text; d jsonb; s uuid; motif text; n integer := 0;
  refus jsonb := '[]'::jsonb; resume jsonb := '{}'::jsonb;
  admis constant text[] := array['localisations','equipements','compteurs','releves','fournisseurs','articles','mouvements','valorisations','programmes','personnes'];
  communs constant text[] := array['articles','fournisseurs','personnes'];
begin
  perform public.exiger_admin();
  if not exists (select 1 from entreprises where id = p_entreprise) then raise exception 'Entreprise inconnue'; end if;
  if coalesce(p_lot, '') !~ '^[A-Za-z0-9-]{6,64}$' then raise exception 'Identifiant de lot invalide'; end if;
  if exists (select 1 from pf_lots_import where id = p_lot) then raise exception 'Ce lot a déjà été importé'; end if;
  if jsonb_typeof(p_fiches) is distinct from 'array' or jsonb_array_length(p_fiches) = 0 then raise exception 'Aucune fiche à importer'; end if;
  if jsonb_array_length(p_fiches) > 20000 then raise exception 'Lot trop volumineux (20 000 fiches maximum) : découpez le kit'; end if;
  begin
    for f in select value from jsonb_array_elements(p_fiches) loop
      t := f->>'type'; motif := null; s := null;
      d := coalesce(f->'data', '{}'::jsonb) || jsonb_build_object('id', f->>'id', 'lotImport', p_lot);
      if not (t = any (admis)) then motif := 'type non importable';
      elsif coalesce(f->>'id', '') = '' then motif := 'identifiant manquant';
      elsif exists (select 1 from fiches where id = f->>'id') then motif := 'identifiant déjà utilisé';
      elsif not (t = any (communs)) then
        s := public.uuid_ou_null(d->>'siteId');
        if s is null or not exists (select 1 from sites where id = s and entreprise_id = p_entreprise) then motif := 'site absent ou d''une autre entreprise'; end if;
      end if;
      if motif is null then
        motif := case
          when t = 'equipements' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and upper(x.data->>'code') = upper(d->>'code')) then 'code équipement déjà utilisé'
          when t = 'compteurs' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and upper(x.data->>'code') = upper(d->>'code')) then 'code compteur déjà utilisé'
          when t = 'localisations' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and x.site_id = s and upper(x.data->>'code') = upper(d->>'code')) then 'code de lieu déjà utilisé sur ce site'
          when t = 'articles' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and upper(x.data->>'ref') = upper(d->>'ref')) then 'référence d''article déjà utilisée'
          when t = 'fournisseurs' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and lower(x.data->>'nom') = lower(d->>'nom')) then 'fournisseur déjà présent'
          when t in ('equipements', 'compteurs', 'localisations') and coalesce(d->>'code', '') = '' then 'code manquant'
          when t = 'articles' and coalesce(d->>'ref', '') = '' then 'référence manquante'
        end;
      end if;
      if motif is not null then
        refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
        continue;
      end if;
      insert into fiches (id, type, data, auteur, entreprise_id, site_id) values (f->>'id', t, d, auth.uid(), p_entreprise, s);
      n := n + 1;
      resume := jsonb_set(resume, array[t], to_jsonb(coalesce((resume->>t)::int, 0) + 1));
    end loop;
    -- Références : chaque lien pointe vers une fiche du bon type, dans la même entreprise (lot ou existant).
    refus := refus || coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'type', x.type, 'motif', 'référence introuvable (' || r.k || ')'))
      from fiches x cross join lateral (values ('localisationId', 'localisations'), ('parentId', x.type), ('equipementId', 'equipements'),
        ('compteurId', 'compteurs'), ('articleId', 'articles'), ('mouvementId', 'mouvements'), ('fournisseurId', 'fournisseurs')) as r(k, cible)
      where x.entreprise_id = p_entreprise and x.data->>'lotImport' = p_lot and coalesce(x.data->>r.k, '') <> ''
        and not exists (select 1 from fiches y where y.id = x.data->>r.k and y.entreprise_id = p_entreprise and y.type = r.cible)), '[]'::jsonb);
    if p_essai or jsonb_array_length(refus) > 0 then raise exception 'pf_essai'; end if;
  exception when raise_exception then
    if sqlerrm <> 'pf_essai' then raise; end if;   -- annule les insertions du bloc ; les compteurs restent
  end;
  if not p_essai and jsonb_array_length(refus) = 0 then
    insert into pf_lots_import (id, entreprise_id, par, fichier, resume, seq_fin)
    values (p_lot, p_entreprise, auth.uid(), left(p_fichier, 200), resume,
            (select max(seq) from fiches where entreprise_id = p_entreprise and data->>'lotImport' = p_lot));
  end if;
  return jsonb_build_object('essai', p_essai, 'acceptes', n, 'refus', refus, 'resume', resume,
    'importe', not p_essai and jsonb_array_length(refus) = 0);
end $$;
revoke all on function public.pf_importer(uuid, text, text, jsonb, boolean) from public, anon;
grant execute on function public.pf_importer(uuid, text, text, jsonb, boolean) to authenticated;

-- Annulation d'un lot : seulement si rien n'a été reçu pour ce client depuis (ni nouvelle fiche, ni modification d'une
-- fiche importée) ; sinon : correction fiche par fiche.
create or replace function public.pf_annuler_lot(p_entreprise uuid, p_lot text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l pf_lots_import; n integer;
begin
  perform public.exiger_admin();
  select * into l from pf_lots_import where id = p_lot and entreprise_id = p_entreprise;
  if l.id is null then raise exception 'Lot inconnu pour cette entreprise'; end if;
  if l.annule_le is not null then raise exception 'Lot déjà annulé'; end if;
  if exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.seq > coalesce(l.seq_fin, 0) and x.type <> 'parametres') then
    raise exception 'Le client (ou un lot plus récent) a enregistré des données depuis cet import : annulation impossible, corrigez fiche par fiche';
  end if;
  delete from fiches where entreprise_id = p_entreprise and data->>'lotImport' = p_lot;
  get diagnostics n = row_count;
  update pf_lots_import set annule_le = now() where id = p_lot;
  return jsonb_build_object('supprimees', n);
end $$;
revoke all on function public.pf_annuler_lot(uuid, text) from public, anon;
grant execute on function public.pf_annuler_lot(uuid, text) to authenticated;

create or replace function public.pf_mes_lire(p_entreprise uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return jsonb_build_object(
    'etapes', coalesce((select etapes from pf_mise_en_service where entreprise_id = p_entreprise), '{}'::jsonb),
    'lots', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'creeLe', cree_le, 'fichier', fichier, 'resume', resume, 'annuleLe', annule_le) order by cree_le desc), '[]'::jsonb)
             from pf_lots_import where entreprise_id = p_entreprise));
end $$;
revoke all on function public.pf_mes_lire(uuid) from public, anon;
grant execute on function public.pf_mes_lire(uuid) to authenticated;

create or replace function public.pf_mes_etape(p_entreprise uuid, p_cle text, p_fait boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e jsonb;
begin
  perform public.exiger_admin();
  if p_cle not in ('kit_envoye', 'kit_recu', 'import', 'responsable_invite', 'qr_imprimes', 'equipe_invitee', 'mise_en_service') then raise exception 'Étape inconnue'; end if;
  if not exists (select 1 from entreprises where id = p_entreprise) then raise exception 'Entreprise inconnue'; end if;
  insert into pf_mise_en_service (entreprise_id) values (p_entreprise) on conflict (entreprise_id) do nothing;
  update pf_mise_en_service
     set etapes = case when p_fait then etapes || jsonb_build_object(p_cle, now()) else etapes - p_cle end, maj_le = now()
   where entreprise_id = p_entreprise
  returning etapes into e;
  return e;
end $$;
revoke all on function public.pf_mes_etape(uuid, text, boolean) from public, anon;
grant execute on function public.pf_mes_etape(uuid, text, boolean) to authenticated;

-- ===== 11_centre_controle.sql — copie générée de supabase/centre_controle.sql (empreinte d914ec7cc7249993) : ne pas modifier ici =====
-- GMAO terrain — centre de contrôle, étape CC1 : fiches clients, conditions d'abonnement, grille tarifaire (rejouable).
-- APRÈS mise_en_service.sql. Voir docs/CENTRE_CONTROLE_CONCEPTION.md.
-- Données de plateforme : jamais visibles des clients (règles d'accès actives, aucune politique de lecture) ;
-- lecture et écriture uniquement par les fonctions pf_* réservées à l'administrateur plateforme.

-- ---------- conditions commerciales de l'abonnement ----------
alter table public.abonnements add column if not exists prix numeric(12, 2);           -- HT, MAD, par période
alter table public.abonnements add column if not exists periodicite text not null default 'mensuel';
alter table public.abonnements add column if not exists remise_pct numeric(5, 2) not null default 0;
alter table public.abonnements add column if not exists conditions text;               -- notes contractuelles
alter table public.abonnements drop constraint if exists abonnements_periodicite_check;
alter table public.abonnements add constraint abonnements_periodicite_check check (periodicite in ('mensuel', 'annuel'));
alter table public.abonnements drop constraint if exists abonnements_remise_check;
alter table public.abonnements add constraint abonnements_remise_check check (remise_pct >= 0 and remise_pct <= 100);
alter table public.abonnements drop constraint if exists abonnements_prix_check;
alter table public.abonnements add constraint abonnements_prix_check check (prix is null or prix >= 0);

-- ---------- grille tarifaire (prix publics HT par pack) ----------
create table if not exists public.pf_tarifs (
  pack         text primary key references public.packs(code),
  prix_mensuel numeric(12, 2) check (prix_mensuel is null or prix_mensuel >= 0),
  prix_annuel  numeric(12, 2) check (prix_annuel is null or prix_annuel >= 0),
  note         text,
  maj_le       timestamptz not null default now()
);
alter table public.pf_tarifs enable row level security;
insert into public.pf_tarifs (pack) select code from public.packs on conflict (pack) do nothing;

-- ---------- objets de plateforme (fiche client ; prospects, support, échanges… en CC2) ----------
create table if not exists public.pf_objets (
  id            text primary key,
  type          text not null,
  entreprise_id uuid references public.entreprises(id),
  data          jsonb not null default '{}'::jsonb,
  cree_le       timestamptz not null default now(),
  maj_le        timestamptz not null default now(),
  par           uuid
);
alter table public.pf_objets enable row level security;
create index if not exists pf_objets_type on public.pf_objets (type, entreprise_id);

-- ---------- lecture : tous les clients avec usage, abonnement et fiche ----------
create or replace function public.pf_clients()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(x order by x->>'nom') from (
    select jsonb_build_object(
      'id', e.id, 'code', e.code, 'nom', e.nom, 'statut', e.statut, 'demo', e.demo, 'creeLe', e.cree_le,
      'abonnement', public.droits_entreprise(e.id) || jsonb_build_object('debut', a.debut, 'prix', a.prix, 'periodicite', a.periodicite,
        'remisePct', a.remise_pct, 'conditions', a.conditions, 'statutAbonnement', a.statut,
        'derogations', jsonb_build_object('maxSites', a.max_sites, 'maxUtilisateursSite', a.max_utilisateurs_site, 'maxUtilisateursTotal', a.max_utilisateurs_total)),
      'actifs', public.nb_actifs_entreprise(e.id, null),
      'sites', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'nom', s.nom, 'actif', s.actif) order by s.nom), '[]'::jsonb) from sites s where s.entreprise_id = e.id),
      'responsables', (select coalesce(jsonb_agg(p.email order by p.email), '[]'::jsonb) from profils p where p.entreprise_id = e.id and p.role = 'responsable' and p.actif),
      'fiches', (select count(*) from fiches f where f.entreprise_id = e.id),
      'activite7j', (select count(*) from fiches f where f.entreprise_id = e.id and f.recu_le > now() - interval '7 days' and f.data->>'lotImport' is null),
      'derniereActivite', (select max(f.recu_le) from fiches f where f.entreprise_id = e.id and f.data->>'lotImport' is null),
      'miseEnService', (select etapes from pf_mise_en_service m where m.entreprise_id = e.id),
      'fiche', (select o.data from pf_objets o where o.id = 'client-' || e.id::text)) x
    from entreprises e left join abonnements a on a.entreprise_id = e.id) q), '[]'::jsonb);
end $$;
revoke all on function public.pf_clients() from public, anon;
grant execute on function public.pf_clients() to authenticated;

-- ---------- fiche client : identité et contacts (raison sociale, ICE, adresse, contacts, secteur, notes) ----------
create or replace function public.pf_client_maj(p_entreprise uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  perform public.exiger_admin();
  if not exists (select 1 from entreprises where id = p_entreprise) then raise exception 'Entreprise inconnue'; end if;
  if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Fiche invalide'; end if;
  if coalesce(p_data->>'ice', '') <> '' and p_data->>'ice' !~ '^[0-9]{15}$' then raise exception 'ICE : 15 chiffres'; end if;
  if p_data ? 'contacts' and jsonb_typeof(p_data->'contacts') is distinct from 'array' then raise exception 'Contacts : liste attendue'; end if;
  insert into pf_objets (id, type, entreprise_id, data, par) values ('client-' || p_entreprise::text, 'fiche_client', p_entreprise, p_data, auth.uid())
  on conflict (id) do update set data = excluded.data, maj_le = now(), par = auth.uid()
  returning data into d;
  return d;
end $$;
revoke all on function public.pf_client_maj(uuid, jsonb) from public, anon;
grant execute on function public.pf_client_maj(uuid, jsonb) to authenticated;

-- ---------- conditions d'abonnement (prix convenu, périodicité, remise, début, notes) ----------
create or replace function public.pf_abonnement_conditions(p_entreprise uuid, p_prix numeric, p_periodicite text, p_remise numeric, p_debut date, p_conditions text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  if p_periodicite not in ('mensuel', 'annuel') then raise exception 'Périodicité : mensuel ou annuel'; end if;
  if p_prix is not null and p_prix < 0 then raise exception 'Prix négatif'; end if;
  if coalesce(p_remise, 0) < 0 or coalesce(p_remise, 0) > 100 then raise exception 'Remise entre 0 et 100 %%'; end if;
  update abonnements set prix = p_prix, periodicite = p_periodicite, remise_pct = coalesce(p_remise, 0),
    debut = coalesce(p_debut, debut), conditions = nullif(trim(coalesce(p_conditions, '')), '')
  where entreprise_id = p_entreprise;
  if not found then raise exception 'Entreprise sans abonnement'; end if;
end $$;
revoke all on function public.pf_abonnement_conditions(uuid, numeric, text, numeric, date, text) from public, anon;
grant execute on function public.pf_abonnement_conditions(uuid, numeric, text, numeric, date, text) to authenticated;

-- ---------- grille tarifaire ----------
create or replace function public.pf_tarifs_lire()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return (select coalesce(jsonb_agg(jsonb_build_object('pack', p.code, 'packNom', p.nom, 'modules', p.modules, 'maxSites', p.max_sites,
    'maxUtilisateursSite', p.max_utilisateurs_site, 'maxUtilisateursTotal', p.max_utilisateurs_total,
    'prixMensuel', t.prix_mensuel, 'prixAnnuel', t.prix_annuel, 'note', t.note) order by coalesce(p.max_utilisateurs_total, 1000000)), '[]'::jsonb)
    from packs p left join pf_tarifs t on t.pack = p.code);
end $$;
revoke all on function public.pf_tarifs_lire() from public, anon;
grant execute on function public.pf_tarifs_lire() to authenticated;

create or replace function public.pf_tarif_maj(p_pack text, p_prix_mensuel numeric, p_prix_annuel numeric, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  if not exists (select 1 from packs where code = p_pack) then raise exception 'Pack inconnu'; end if;
  if coalesce(p_prix_mensuel, 0) < 0 or coalesce(p_prix_annuel, 0) < 0 then raise exception 'Prix négatif'; end if;
  insert into pf_tarifs (pack, prix_mensuel, prix_annuel, note) values (p_pack, p_prix_mensuel, p_prix_annuel, nullif(trim(coalesce(p_note, '')), ''))
  on conflict (pack) do update set prix_mensuel = excluded.prix_mensuel, prix_annuel = excluded.prix_annuel, note = excluded.note, maj_le = now();
end $$;
revoke all on function public.pf_tarif_maj(text, numeric, numeric, text) from public, anon;
grant execute on function public.pf_tarif_maj(text, numeric, numeric, text) to authenticated;

-- ===== 12_centre_controle_cc2.sql — copie générée de supabase/centre_controle_cc2.sql (empreinte 8310155231f61cca) : ne pas modifier ici =====
-- GMAO terrain — centre de contrôle, étape CC2 : prospects, support, échanges, modèles de messages, annonces (rejouable).
-- APRÈS centre_controle.sql. Voir docs/CENTRE_CONTROLE_CONCEPTION.md.
--   pf_objets (table de CC1) porte les types : prospect, ticket (demande de support), echange (journal), modele (message).
--   pf_annonces : bandeau affiché dans l'appli (tous les clients ou un seul), lu par les utilisateurs via mes_annonces().
--   support_creer : un utilisateur connecté (responsable…) envoie une demande au support depuis l'appli.

create sequence if not exists public.pf_tickets_seq;

-- ---------- lecture / écriture des objets (administrateur) ----------
create or replace function public.pf_objets_lire(p_type text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  if p_type not in ('prospect', 'ticket', 'echange', 'modele') then raise exception 'Type inconnu'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'type', o.type, 'entrepriseId', o.entreprise_id, 'creeLe', o.cree_le, 'majLe', o.maj_le)
                    || o.data order by o.cree_le desc) from pf_objets o where o.type = p_type), '[]'::jsonb);
end $$;
revoke all on function public.pf_objets_lire(text) from public, anon;
grant execute on function public.pf_objets_lire(text) to authenticated;

create or replace function public.pf_objet_enregistrer(p_id text, p_type text, p_entreprise uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); ex pf_objets; id_ text := nullif(trim(coalesce(p_id, '')), '');
begin
  perform public.exiger_admin();
  if p_type not in ('prospect', 'ticket', 'echange', 'modele') then raise exception 'Type inconnu'; end if;
  if jsonb_typeof(d) is distinct from 'object' then raise exception 'Données invalides'; end if;
  if p_entreprise is not null and not exists (select 1 from entreprises where id = p_entreprise) then raise exception 'Entreprise inconnue'; end if;
  d := d - 'id' - 'type' - 'entrepriseId' - 'creeLe' - 'majLe';
  if id_ is not null then
    select * into ex from pf_objets where id = id_;
    if ex.id is not null and ex.type <> p_type then raise exception 'Identifiant déjà utilisé par un autre type'; end if;
  end if;
  -- règles par type
  if p_type = 'prospect' then
    if coalesce(trim(d->>'nom'), '') = '' and coalesce(trim(d->>'societe'), '') = '' then raise exception 'Prospect : nom ou société obligatoire'; end if;
    if coalesce(d->>'etape', 'nouveau') not in ('nouveau', 'contacte', 'demo_prevue', 'demo_faite', 'essai', 'gagne', 'perdu') then raise exception 'Étape inconnue'; end if;
    if d->>'etape' = 'perdu' and coalesce(trim(d->>'motifPerte'), '') = '' then raise exception 'Prospect perdu : motif obligatoire'; end if;
  elsif p_type = 'ticket' then
    if p_entreprise is null then raise exception 'Demande de support : client obligatoire'; end if;
    if coalesce(trim(d->>'sujet'), '') = '' then raise exception 'Demande de support : sujet obligatoire'; end if;
    if coalesce(d->>'statut', 'ouverte') not in ('ouverte', 'en_cours', 'en_attente_client', 'resolue', 'fermee') then raise exception 'Statut inconnu'; end if;
    if coalesce(d->>'priorite', 'normale') not in ('basse', 'normale', 'haute', 'urgente') then raise exception 'Priorité inconnue'; end if;
    if coalesce(d->>'nature', 'question') not in ('question', 'anomalie', 'evolution', 'facturation') then raise exception 'Nature de la demande inconnue'; end if;
    if ex.id is null then d := d || jsonb_build_object('ref', 'SUP-' || lpad(nextval('pf_tickets_seq')::text, 4, '0')); else d := d || jsonb_build_object('ref', ex.data->>'ref'); end if;
  elsif p_type = 'echange' then
    if coalesce(d->>'canal', '') not in ('whatsapp', 'email', 'telephone', 'rencontre', 'autre') then raise exception 'Canal inconnu'; end if;
    if coalesce(trim(d->>'resume'), '') = '' then raise exception 'Échange : résumé obligatoire'; end if;
    if p_entreprise is null and coalesce(d->>'prospectId', '') = '' then raise exception 'Échange : client ou prospect obligatoire'; end if;
    if ex.id is not null then raise exception 'Un échange noté ne se modifie pas : ajoutez-en un autre'; end if;
  elsif p_type = 'modele' then
    if coalesce(trim(d->>'nom'), '') = '' or coalesce(trim(d->>'texte'), '') = '' then raise exception 'Modèle : nom et texte obligatoires'; end if;
  end if;
  id_ := coalesce(id_, p_type || '-' || replace(gen_random_uuid()::text, '-', ''));
  insert into pf_objets (id, type, entreprise_id, data, par) values (id_, p_type, p_entreprise, d, auth.uid())
  on conflict (id) do update set data = excluded.data, entreprise_id = excluded.entreprise_id, maj_le = now(), par = auth.uid();
  return (select jsonb_build_object('id', o.id, 'type', o.type, 'entrepriseId', o.entreprise_id, 'creeLe', o.cree_le, 'majLe', o.maj_le) || o.data from pf_objets o where o.id = id_);
end $$;
revoke all on function public.pf_objet_enregistrer(text, text, uuid, jsonb) from public, anon;
grant execute on function public.pf_objet_enregistrer(text, text, uuid, jsonb) to authenticated;

-- Suppression : modèles de messages, et prospects (droit d'effacement, loi 09-08) avec leurs échanges.
create or replace function public.pf_objet_supprimer(p_id text)
returns void language plpgsql security definer set search_path = public as $$
declare o pf_objets;
begin
  perform public.exiger_admin();
  select * into o from pf_objets where id = p_id;
  if o.id is null then raise exception 'Introuvable'; end if;
  if o.type not in ('modele', 'prospect') then raise exception 'Seuls un modèle ou un prospect se suppriment (l''historique client est conservé)'; end if;
  if o.type = 'prospect' then delete from pf_objets where type = 'echange' and data->>'prospectId' = p_id; end if;
  delete from pf_objets where id = p_id;
end $$;
revoke all on function public.pf_objet_supprimer(text) from public, anon;
grant execute on function public.pf_objet_supprimer(text) to authenticated;

-- ---------- modèles de messages par défaut (variables : {contact} {entreprise} {fin} {montant} {lien}) ----------
insert into public.pf_objets (id, type, data) values
  ('modele-bienvenue', 'modele', jsonb_build_object('nom', 'Bienvenue', 'cible', 'client', 'texte',
    'Bonjour {contact}, bienvenue sur Perfora ! Votre espace {entreprise} est prêt : {lien}. Je reste disponible pour toute question. Hicham')),
  ('modele-relance-essai', 'modele', jsonb_build_object('nom', 'Relance fin d''essai', 'cible', 'client', 'texte',
    'Bonjour {contact}, votre essai Perfora se termine le {fin}. Comment se passe la prise en main par vos équipes ? Je vous propose un point de 15 minutes pour faire le bilan.')),
  ('modele-echeance', 'modele', jsonb_build_object('nom', 'Rappel d''échéance', 'cible', 'client', 'texte',
    'Bonjour {contact}, l''abonnement Perfora de {entreprise} arrive à échéance le {fin} ({montant}). Merci de prévoir le règlement pour éviter le passage en lecture seule.')),
  ('modele-demo', 'modele', jsonb_build_object('nom', 'Proposition de démo', 'cible', 'prospect', 'texte',
    'Bonjour {contact}, suite à votre intérêt pour Perfora (GMAO terrain, utilisable sans réseau), je vous propose une démonstration de 20 minutes. Quel créneau vous conviendrait ?')),
  ('modele-parrainage', 'modele', jsonb_build_object('nom', 'Parrainage', 'cible', 'client', 'texte',
    'Bonjour {contact}, merci pour votre confiance. Si un confrère directeur pourrait être intéressé par Perfora, n''hésitez pas à lui transmettre mon numéro : un mois vous sera offert à sa souscription.'))
on conflict (id) do nothing;

-- ---------- annonces dans l'appli ----------
create table if not exists public.pf_annonces (
  id            uuid primary key default gen_random_uuid(),
  titre         text not null,
  texte         text not null,
  niveau        text not null default 'info' check (niveau in ('info', 'attention')),
  entreprise_id uuid references public.entreprises(id),     -- null = tous les clients
  debut         timestamptz not null default now(),
  fin           timestamptz,
  actif         boolean not null default true,
  cree_le       timestamptz not null default now()
);
alter table public.pf_annonces enable row level security;

create or replace function public.pf_annonces_lire()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'titre', titre, 'texte', texte, 'niveau', niveau, 'entrepriseId', entreprise_id,
    'debut', debut, 'fin', fin, 'actif', actif, 'creeLe', cree_le) order by cree_le desc) from pf_annonces), '[]'::jsonb);
end $$;
revoke all on function public.pf_annonces_lire() from public, anon;
grant execute on function public.pf_annonces_lire() to authenticated;

create or replace function public.pf_annonce_enregistrer(p_id uuid, p_titre text, p_texte text, p_niveau text, p_entreprise uuid, p_debut timestamptz, p_fin timestamptz, p_actif boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare i uuid;
begin
  perform public.exiger_admin();
  if coalesce(trim(p_titre), '') = '' or coalesce(trim(p_texte), '') = '' then raise exception 'Titre et texte obligatoires'; end if;
  if length(p_texte) > 500 then raise exception 'Texte trop long (500 caractères)'; end if;
  if p_fin is not null and p_fin <= coalesce(p_debut, now()) then raise exception 'La fin doit suivre le début'; end if;
  if p_id is null then
    insert into pf_annonces (titre, texte, niveau, entreprise_id, debut, fin, actif)
    values (trim(p_titre), trim(p_texte), coalesce(p_niveau, 'info'), p_entreprise, coalesce(p_debut, now()), p_fin, coalesce(p_actif, true)) returning id into i;
  else
    update pf_annonces set titre = trim(p_titre), texte = trim(p_texte), niveau = coalesce(p_niveau, 'info'), entreprise_id = p_entreprise,
      debut = coalesce(p_debut, debut), fin = p_fin, actif = coalesce(p_actif, true) where id = p_id returning id into i;
    if i is null then raise exception 'Annonce introuvable'; end if;
  end if;
  return i;
end $$;
revoke all on function public.pf_annonce_enregistrer(uuid, text, text, text, uuid, timestamptz, timestamptz, boolean) from public, anon;
grant execute on function public.pf_annonce_enregistrer(uuid, text, text, text, uuid, timestamptz, timestamptz, boolean) to authenticated;

-- Annonces en cours pour le compte connecté (toutes entreprises, ou la sienne).
create or replace function public.mes_annonces()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'titre', titre, 'texte', texte, 'niveau', niveau) order by debut desc), '[]'::jsonb)
  from pf_annonces
  where actif and debut <= now() and (fin is null or fin > now())
    and (entreprise_id is null or entreprise_id = public.mon_entreprise())
    and public.mon_role() is not null
$$;
revoke all on function public.mes_annonces() from public, anon;
grant execute on function public.mes_annonces() to authenticated;

-- ---------- demande au support depuis l'appli ----------
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
  select * into p from profils where user_id = auth.uid();
  ref := 'SUP-' || lpad(nextval('pf_tickets_seq')::text, 4, '0');
  insert into pf_objets (id, type, entreprise_id, data, par) values (i, 'ticket', ent, jsonb_build_object(
    'ref', ref, 'nature', p_nature, 'sujet', trim(p_sujet), 'description', trim(p_message), 'statut', 'ouverte', 'priorite', 'normale',
    'source', 'appli', 'demandeur', jsonb_build_object('nom', p.nom, 'email', p.email, 'role', p.role)), auth.uid());
  return jsonb_build_object('ref', ref);
end $$;
revoke all on function public.support_creer(text, text, text) from public, anon;
grant execute on function public.support_creer(text, text, text) to authenticated;

-- ===== 13_references.sql — copie générée de supabase/references.sql (empreinte 10bd4e33877e7825) : ne pas modifier ici =====
-- GMAO terrain — intégrité des références (rejouable). APRÈS centre_controle_cc2.sql.
-- Une demande, une intervention ou un programme préventif ne peut être créé que sur un équipement connu de l'entreprise
-- (constat du 7 nov. 2026 : une demande saisie sur un équipement créé hors connexion, refusé, restait orpheline).

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean; mod text; u text;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- D2 bis : un compteur d'équipement (heures, cycles) relève du préventif, un compteur de ressource de l'énergie.
    mod := public.module_de(cible);
    if cible in ('compteurs', 'releves') then
      u := case
        when t = 'compteurs' then coalesce(p->>'usage', ex.data->>'usage')
        when t = 'releves' then (select c.data->>'usage' from fiches c where c.id = coalesce(p->>'compteurId', ex.data->>'compteurId') and c.entreprise_id = ent)
        else (select case when x.type = 'compteurs' then x.data->>'usage'
                          else (select c.data->>'usage' from fiches c where c.id = x.data->>'compteurId' and c.entreprise_id = ent) end
              from fiches x where x.id = p->>'entiteId' and x.entreprise_id = ent)
      end;
      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? mod) then
      motif := 'module « ' || mod || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    elsif t = 'ots' and r <> 'responsable' and p->>'statut' = 'cloturee' and public.cloture_par_responsable(ent) then
      motif := 'clôture réservée au responsable (réglage de l''entreprise) : terminez l''intervention, le responsable la clôture';
    -- réglages de l'entreprise : une seule fiche, d'identifiant fixe
    elsif t = 'parametres' and f->>'id' <> ('parametres-' || ent::text) then
      motif := 'paramètres : identifiant réservé à l''entreprise';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    -- intégrité : une fiche rattachée à un équipement exige un équipement connu de l'entreprise (lot en cours compris)
    elsif t in ('demandes', 'ots', 'programmes') and ex.id is null and coalesce(p->>'equipementId', '') <> ''
          and not exists (select 1 from fiches x where x.id = p->>'equipementId' and x.type = 'equipements' and x.entreprise_id = ent) then
      motif := 'équipement inconnu de l''entreprise (créé hors connexion ou supprimé ?)';
    -- volet D : compteurs (référentiel du responsable), relevés jamais modifiés, factures à lecture restreinte
    elsif t = 'compteurs' and ex.id is not null
          and ((p ? 'mode' and p->'mode' is distinct from ex.data->'mode') or (p ? 'unite' and p->'unite' is distinct from ex.data->'unite')
               or (p ? 'coefficient' and p->'coefficient' is distinct from ex.data->'coefficient')
               or (p ? 'usage' and p->'usage' is distinct from ex.data->'usage'))
          and exists (select 1 from fiches x where x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = ex.id) then
      motif := 'compteur déjà relevé : usage, mode, unité et coefficient ne changent plus (rupture déclarée ou nouveau compteur)';
    elsif t = 'releves' and ex.id is null and not exists (select 1 from fiches c where c.id = p->>'compteurId' and c.type = 'compteurs' and c.entreprise_id = ent) then
      motif := 'un relevé se rattache à un compteur connu';
    elsif t = 'releves' and ex.id is null and r <> 'responsable' and (p ? 'decision' or p ? 'decidePar' or p ? 'decideLe') then
      motif := 'qualification d''un relevé : réservée au responsable';
    elsif t = 'releves' and ex.id is null and coalesce(p->>'remplaceId', '') <> '' and not exists (
            select 1 from fiches x where x.id = p->>'remplaceId' and x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = p->>'compteurId') then
      motif := 'une correction remplace un relevé du même compteur';
    elsif t = 'releves' and ex.id is not null and (r <> 'responsable' or exists (
            select 1 from jsonb_object_keys(p) k where k not in ('decision', 'motifDecision', 'decideLe', 'decidePar', 'modifieLe', 'modifiePar'))) then
      motif := 'un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)';
    end if;

    if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        case when t = 'releves' then (select site_id from fiches where id = p->>'compteurId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- ===== 14_fichiers.sql — copie générée de supabase/fichiers.sql (empreinte 6a2a3f29721b1996) : ne pas modifier ici =====
-- GMAO terrain — fichiers joints (photos et PDF) dans Supabase Storage (rejouable). APRÈS references.sql.
-- Voir docs/PLANNING_ACTUALISE.md (1.2). Les fichiers ne sont plus dans la base : la fiche « photos » garde seulement
-- la description (chemin, type, taille, nom) et l'appli envoie le fichier lui-même dans l'espace « fichiers ».
--
-- Chemin d'un fichier : <entreprise>/<site ou « commun »>/<catégorie>/<identifiant>.<extension>
--   catégorie : photos | documents | couts (pièces jointes de factures et d'achats : lecture restreinte comme les prix)
-- Règles : on ne lit et n'écrit que dans son entreprise et ses sites ; « couts » réservé aux rôles qui voient les coûts ;
-- écriture refusée au pilote et si l'abonnement est en lecture seule ; un fichier déposé ne se remplace ni ne s'efface
-- (aucune règle de modification ni de suppression).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fichiers', 'fichiers', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.fichier_autorise(p_nom text, p_ecrire boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare d text[] := string_to_array(p_nom, '/'); r text := public.mon_role(); ent uuid := public.mon_entreprise(); site uuid;
begin
  if r is null or ent is null or array_length(d, 1) <> 4 then return false; end if;
  if d[1] <> ent::text then return false; end if;
  if d[3] not in ('photos', 'documents', 'couts') then return false; end if;
  if d[3] = 'couts' and not public.voit_couts() then return false; end if;
  if d[2] <> 'commun' then
    site := public.uuid_ou_null(d[2]);
    if site is null or not (site in (select public.mes_sites())) then return false; end if;
  end if;
  if p_ecrire then
    if r = 'pilote' then return false; end if;
    if not coalesce((public.droits_entreprise(ent)->>'ecriture')::boolean, false) then return false; end if;
    if d[4] !~ '^[A-Za-z0-9_-]{6,80}\.(jpg|jpeg|png|webp|pdf)$' then return false; end if;
  end if;
  return true;
end $$;
revoke all on function public.fichier_autorise(text, boolean) from public, anon;
grant execute on function public.fichier_autorise(text, boolean) to authenticated;

drop policy if exists "fichiers lecture" on storage.objects;
create policy "fichiers lecture" on storage.objects for select to authenticated
  using (bucket_id = 'fichiers' and public.fichier_autorise(name, false));
drop policy if exists "fichiers depot" on storage.objects;
create policy "fichiers depot" on storage.objects for insert to authenticated
  with check (bucket_id = 'fichiers' and public.fichier_autorise(name, true));

-- Occupation par entreprise (centre de contrôle : limite de l'offre gratuite = 1 Go au total).
create or replace function public.pf_stockage()
returns jsonb language plpgsql stable security definer set search_path = public, storage as $$
begin
  perform public.exiger_admin();
  return jsonb_build_object(
    'total', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'fichiers'),
    'parEntreprise', (select coalesce(jsonb_object_agg(e, o), '{}'::jsonb) from (
      select split_part(name, '/', 1) e, sum((metadata->>'size')::bigint) o from storage.objects where bucket_id = 'fichiers' group by 1) z),
    'base', pg_database_size(current_database()));
end $$;
revoke all on function public.pf_stockage() from public, anon;
grant execute on function public.pf_stockage() to authenticated;

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

-- ===== 16_roles_r1.sql — copie générée de supabase/roles_r1.sql (empreinte 9717964d661a9956) : ne pas modifier ici =====
-- GMAO terrain — lot R1 « navigation et droits par rôle » (docs/MAQUETTES_R1.md §5). APRÈS securite.sql. Rejouable.
-- FICHIER GÉNÉRÉ par scripts/generer_roles_r1.py : ne pas modifier à la main.
-- S1 prestataire : ne lit et n'écrit que ses interventions (celles où il est intervenant) et ce qui s'y rattache ;
--    parc, lieux, personnes, articles, compteurs et relevés restent lisibles (signaler, relever).
-- S2 journal d'audit : lu en entier par le responsable, la direction (pilote) et l'administrateur de l'entreprise ;
--    les autres ne lisent que les lignes de leurs propres saisies et de leurs interventions.
-- S3 administrateur de l'entreprise : droit cumulable (profils.admin_client) ; il invite, active, change les rôles et
--    les sites ; les responsables actuels le reçoivent ; le premier compte d'une entreprise l'obtient à l'invitation.

-- ---------- S3 : droit « administrateur de l'entreprise » ----------
alter table public.profils add column if not exists admin_client boolean not null default false;
do $$ begin
  -- migration (une seule fois) : chaque responsable actuel devient administrateur de son entreprise
  if not exists (select 1 from public.profils where admin_client) then
    update public.profils set admin_client = true where role = 'responsable';
  end if;
end $$;

create or replace function public.est_admin_client()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select admin_client and actif from profils where user_id = auth.uid()), false)
$$;
create or replace function public.voit_journal_complet()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mon_role() in ('responsable', 'pilote') or public.est_admin_client()
$$;
create or replace function public.ma_personne()
returns text language sql stable security definer set search_path = public as $$
  select personne_id from profils where user_id = auth.uid()
$$;
revoke all on function public.est_admin_client() from public, anon;
grant execute on function public.est_admin_client() to authenticated;
revoke all on function public.voit_journal_complet() from public, anon;
grant execute on function public.voit_journal_complet() to authenticated;
revoke all on function public.ma_personne() from public, anon, authenticated;

/** Donner ou retirer le droit d'administrateur de l'entreprise (jamais au dernier administrateur actif). */
create or replace function public.definir_admin_client(cible uuid, valeur boolean)
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise();
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = ent) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if not valeur and not exists (select 1 from profils where entreprise_id = ent and admin_client and actif and user_id <> cible) then
    raise exception 'L''entreprise doit garder au moins un administrateur';
  end if;
  update profils set admin_client = valeur where user_id = cible;
end $$;
revoke all on function public.definir_admin_client(uuid, boolean) from public, anon;
grant execute on function public.definir_admin_client(uuid, boolean) to authenticated;

-- ---------- S1 : périmètre du prestataire ----------
/** Intervention confiée à l'appelant (il en est intervenant). */
create or replace function public.ot_a_moi(oid text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(oid, '') <> '' and exists (
    select 1 from fiches o where o.id = oid and o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())))
$$;
revoke all on function public.ot_a_moi(text) from public, anon, authenticated;

/** Lecture autorisée à un prestataire (appelée par la règle de lecture de « fiches »). */
create or replace function public.prestataire_voit(t text, fid text, d jsonb, aut uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  if t in ('equipements', 'localisations', 'personnes', 'articles', 'compteurs', 'releves', 'parametres', 'journal') then return true; end if;
  if t = 'ots' then return public.ot_a_moi(fid); end if;
  if t = 'demandes' then
    return aut = auth.uid() or exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'demandeIds' ? fid and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));
  end if;
  if t in ('besoins', 'mouvements') then return public.ot_a_moi(d->>'otId'); end if;
  if t = 'programmes' then
    return exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise() and o.data->>'programmeId' = fid
      and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));
  end if;
  if t = 'photos' then
    select type, id, data, auteur into x from fiches where id = d->>'parentId' and entreprise_id = public.mon_entreprise();
    return found and x.type <> 'photos' and public.prestataire_voit(x.type, x.id, x.data, x.auteur);
  end if;
  return false;   -- magasin, achats, prix, seuils, factures, fournisseurs…
end $$;
revoke all on function public.prestataire_voit(text, text, jsonb, uuid) from public, anon;
grant execute on function public.prestataire_voit(text, text, jsonb, uuid) to authenticated;   -- appelée par la règle de lecture

/** Motif de refus d'une écriture du prestataire hors de ses interventions (null = accepté). */
create or replace function public.prestataire_refus(t text, fid text, p jsonb, nouvelle boolean)
returns text language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  select type, id, data, auteur into x from fiches where id = fid and entreprise_id = public.mon_entreprise();
  if t = 'ots' then
    if nouvelle then return 'un prestataire ne crée pas d''intervention : signalez, le responsable vous la confie'; end if;
    if not public.ot_a_moi(fid) then return 'intervention qui ne vous est pas confiée'; end if;
  elsif t in ('besoins', 'mouvements') then
    if not public.ot_a_moi(coalesce(p->>'otId', x.data->>'otId')) then return 'pièce hors de vos interventions'; end if;
  elsif t = 'demandes' then
    if not nouvelle and x.auteur is distinct from auth.uid() then return 'demande qui n''est pas la vôtre'; end if;
  elsif t = 'photos' then
    if not public.prestataire_voit(coalesce(p->>'parentType', x.data->>'parentType'),
        coalesce(p->>'parentId', x.data->>'parentId'),
        (select data from fiches where id = coalesce(p->>'parentId', x.data->>'parentId')),
        (select auteur from fiches where id = coalesce(p->>'parentId', x.data->>'parentId'))) then
      return 'fichier hors de vos interventions';
    end if;
  elsif t = 'journal' then
    if (p->>'entite') = 'ots' and not public.ot_a_moi(p->>'entiteId')
       and exists (select 1 from fiches where id = p->>'entiteId') then return 'intervention qui ne vous est pas confiée'; end if;
  end if;
  return null;
end $$;
revoke all on function public.prestataire_refus(text, text, jsonb, boolean) from public, anon, authenticated;

-- ---------- S2 : journal d'audit restreint ----------
/** Ligne du journal lisible par l'appelant. */
create or replace function public.journal_visible(d jsonb, aut uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  if public.voit_journal_complet() or aut = auth.uid() then return true; end if;
  select type, id, data, auteur into x from fiches where id = d->>'entiteId' and entreprise_id = public.mon_entreprise();
  if not found then return false; end if;
  if x.auteur = auth.uid() then return true; end if;                       -- ses propres fiches
  if x.type = 'ots' then return public.ot_a_moi(x.id); end if;             -- ses interventions
  if x.type in ('besoins', 'mouvements') then return public.ot_a_moi(x.data->>'otId'); end if;
  if x.type = 'demandes' then
    return exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'demandeIds' ? x.id and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));
  end if;
  return false;
end $$;
revoke all on function public.journal_visible(jsonb, uuid) from public, anon;
grant execute on function public.journal_visible(jsonb, uuid) to authenticated;   -- appelée par la règle de lecture

-- Règle de lecture des fiches (version de energie.sql + périmètre du prestataire + journal restreint).
drop policy if exists "lecture equipe" on public.fiches;
create policy "lecture equipe" on public.fiches for select to authenticated using (
  public.mon_role() is not null
  and entreprise_id = public.mon_entreprise()
  and (site_id is null or site_id in (select public.mes_sites()))
  and (public.voit_couts()
       or not (type in ('achats', 'valorisations', 'factures_energie')
               or (type = 'journal' and data->>'entite' in ('achats', 'valorisations', 'factures_energie'))
               or (type = 'photos' and data->>'parentType' = 'factures_energie')))
  and (public.mon_role() <> 'prestataire' or public.prestataire_voit(type, id, data, auteur))
  and (type <> 'journal' or public.journal_visible(data, auteur)));
create index if not exists fiches_ots_intervenants on public.fiches using gin ((data->'intervenants')) where type = 'ots';

-- Comptes et affectations : lisibles par l'administrateur de l'entreprise (et le responsable, pour l'affichage).
drop policy if exists "profil lisible" on public.profils;
create policy "profil lisible" on public.profils for select to authenticated using (
  user_id = auth.uid() or public.est_admin_plateforme()
  or ((public.mon_role() = 'responsable' or public.est_admin_client()) and entreprise_id = public.mon_entreprise()));
drop policy if exists "affectations visibles" on public.profil_sites;
create policy "affectations visibles" on public.profil_sites for select to authenticated using (
  user_id = auth.uid() or public.est_admin_plateforme()
  or ((public.mon_role() = 'responsable' or public.est_admin_client())
      and exists (select 1 from profils p where p.user_id = profil_sites.user_id and p.entreprise_id = public.mon_entreprise())));

-- ---------- fonctions mises à jour ----------
create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean; mod text; u text;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- D2 bis : un compteur d'équipement (heures, cycles) relève du préventif, un compteur de ressource de l'énergie.
    mod := public.module_de(cible);
    if cible in ('compteurs', 'releves') then
      u := case
        when t = 'compteurs' then coalesce(p->>'usage', ex.data->>'usage')
        when t = 'releves' then (select c.data->>'usage' from fiches c where c.id = coalesce(p->>'compteurId', ex.data->>'compteurId') and c.entreprise_id = ent)
        else (select case when x.type = 'compteurs' then x.data->>'usage'
                          else (select c.data->>'usage' from fiches c where c.id = x.data->>'compteurId' and c.entreprise_id = ent) end
              from fiches x where x.id = p->>'entiteId' and x.entreprise_id = ent)
      end;
      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? mod) then
      motif := 'module « ' || mod || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    -- R1 : un prestataire n'écrit que sur les interventions qui lui sont confiées (et ce qui s'y rattache).
    elsif r = 'prestataire' and public.prestataire_refus(t, f->>'id', p, ex.id is null) is not null then
      motif := public.prestataire_refus(t, f->>'id', p, ex.id is null);
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    elsif t = 'ots' and r <> 'responsable' and p->>'statut' = 'cloturee' and public.cloture_par_responsable(ent) then
      motif := 'clôture réservée au responsable (réglage de l''entreprise) : terminez l''intervention, le responsable la clôture';
    -- réglages de l'entreprise : une seule fiche, d'identifiant fixe
    elsif t = 'parametres' and f->>'id' <> ('parametres-' || ent::text) then
      motif := 'paramètres : identifiant réservé à l''entreprise';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    -- intégrité : une fiche rattachée à un équipement exige un équipement connu de l'entreprise (lot en cours compris)
    elsif t in ('demandes', 'ots', 'programmes') and ex.id is null and coalesce(p->>'equipementId', '') <> ''
          and not exists (select 1 from fiches x where x.id = p->>'equipementId' and x.type = 'equipements' and x.entreprise_id = ent) then
      motif := 'équipement inconnu de l''entreprise (créé hors connexion ou supprimé ?)';
    -- volet D : compteurs (référentiel du responsable), relevés jamais modifiés, factures à lecture restreinte
    elsif t = 'compteurs' and ex.id is not null
          and ((p ? 'mode' and p->'mode' is distinct from ex.data->'mode') or (p ? 'unite' and p->'unite' is distinct from ex.data->'unite')
               or (p ? 'coefficient' and p->'coefficient' is distinct from ex.data->'coefficient')
               or (p ? 'usage' and p->'usage' is distinct from ex.data->'usage'))
          and exists (select 1 from fiches x where x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = ex.id) then
      motif := 'compteur déjà relevé : usage, mode, unité et coefficient ne changent plus (rupture déclarée ou nouveau compteur)';
    elsif t = 'releves' and ex.id is null and not exists (select 1 from fiches c where c.id = p->>'compteurId' and c.type = 'compteurs' and c.entreprise_id = ent) then
      motif := 'un relevé se rattache à un compteur connu';
    elsif t = 'releves' and ex.id is null and r <> 'responsable' and (p ? 'decision' or p ? 'decidePar' or p ? 'decideLe') then
      motif := 'qualification d''un relevé : réservée au responsable';
    elsif t = 'releves' and ex.id is null and coalesce(p->>'remplaceId', '') <> '' and not exists (
            select 1 from fiches x where x.id = p->>'remplaceId' and x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = p->>'compteurId') then
      motif := 'une correction remplace un relevé du même compteur';
    elsif t = 'releves' and ex.id is not null and (r <> 'responsable' or exists (
            select 1 from jsonb_object_keys(p) k where k not in ('decision', 'motifDecision', 'decideLe', 'decidePar', 'modifieLe', 'modifiePar'))) then
      motif := 'un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)';
    end if;

    if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        case when t = 'releves' then (select site_id from fiches where id = p->>'compteurId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

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
    'adminClient', p.admin_client,
    -- inscrit mais session sans code : la console demande le code (ou l'inscription de l'application d'authentification)
    'adminMfa', case when not public.admin_inscrit() then null
                     else (select jsonb_build_object('obligatoire', a.mfa_obligatoire, 'niveau', public.niveau_session())
                           from admins_plateforme a where a.user_id = auth.uid()) end);
end $$;
revoke all on function public.mon_profil() from public, anon;
grant execute on function public.mon_profil() to authenticated;

create or replace function public.preparer_invitation(p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  perform public.limiter('invitation:' || public.mon_entreprise(), 20, interval '1 hour', 'Trop d''invitations en une heure : réessayez plus tard');
  return public.controle_invitation(public.mon_entreprise(), p_email, p_role, p_sites);
end $$;
revoke all on function public.preparer_invitation(text, text, uuid[]) from public, anon;
grant execute on function public.preparer_invitation(text, text, uuid[]) to authenticated;

create or replace function public.definir_profil(cible uuid, nouveau_role text, nouveau_nom text, est_actif boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.est_admin_client() then
    raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501';
  end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = public.mon_entreprise()) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if cible = auth.uid() and not est_actif then
    raise exception 'Vous ne pouvez pas désactiver votre propre compte';
  end if;
  update profils set role = coalesce(nouveau_role, role), nom = coalesce(nullif(trim(nouveau_nom), ''), nom),
    actif = coalesce(est_actif, actif) where user_id = cible;
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'nom', p.nom, 'actif', p.actif),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = p.personne_id;
end $$;
revoke all on function public.definir_profil(uuid, text, text, boolean) from public, anon;
grant execute on function public.definir_profil(uuid, text, text, boolean) to authenticated;

create or replace function public.affecter_sites(cible uuid, liste uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); s uuid;
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = ent) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if coalesce(array_length(liste, 1), 0) = 0 then raise exception 'Choisissez au moins un site'; end if;
  if exists (select 1 from unnest(liste) x where x not in (select id from sites where entreprise_id = ent and actif)) then
    raise exception 'Site inconnu ou inactif';
  end if;
  delete from profil_sites where user_id = cible and site_id <> all (liste);
  foreach s in array liste loop
    insert into profil_sites (user_id, site_id) values (cible, s) on conflict do nothing;   -- quota vérifié par déclencheur
  end loop;
  update profils set site_defaut = liste[1] where user_id = cible and (site_defaut is null or site_defaut <> all (liste));
end $$;
revoke all on function public.affecter_sites(uuid, uuid[]) from public, anon;
grant execute on function public.affecter_sites(uuid, uuid[]) to authenticated;

create or replace function public.utilisation()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); lim jsonb;
begin
  if not (public.est_admin_client() or public.mon_role() = 'responsable') then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  lim := public.droits_entreprise(ent);
  return jsonb_build_object(
    'actifs', public.nb_actifs_entreprise(ent, null), 'maxTotal', lim->'maxUtilisateursTotal',
    'maxSite', lim->'maxUtilisateursSite', 'maxSites', lim->'maxSites',
    'sites', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nom', s.nom, 'actifs', public.nb_actifs_site(s.id, null)) order by s.nom)
                       from sites s where s.entreprise_id = ent and s.actif), '[]'::jsonb),
    'affectations', coalesce((select jsonb_agg(jsonb_build_object('userId', ps.user_id, 'siteId', ps.site_id))
                              from profil_sites ps join profils p on p.user_id = ps.user_id where p.entreprise_id = ent), '[]'::jsonb));
end $$;
revoke all on function public.utilisation() from public, anon;
grant execute on function public.utilisation() to authenticated;

create or replace function public.finaliser_invitation(p_user uuid, p_entreprise uuid, p_role text, p_nom text, p_sites uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_email text; s uuid;
begin
  select u.email into v_email from auth.users u where u.id = p_user;
  insert into profils (user_id, email, nom) values (p_user, v_email, coalesce(nullif(trim(p_nom), ''), split_part(v_email, '@', 1)))
    on conflict (user_id) do nothing;
  update profils set entreprise_id = p_entreprise, role = p_role, actif = true,
    nom = coalesce(nullif(trim(p_nom), ''), nom), site_defaut = p_sites[1] where user_id = p_user;   -- quota total : déclencheur
  -- R1 : le premier compte d'une entreprise (invité par Perfora) en devient l'administrateur.
  if not exists (select 1 from profils where entreprise_id = p_entreprise and admin_client and actif and user_id <> p_user) then
    update profils set admin_client = true where user_id = p_user;
  end if;
  foreach s in array p_sites loop
    insert into profil_sites (user_id, site_id) values (p_user, s) on conflict do nothing;      -- quota site : déclencheur
  end loop;
end $$;
revoke all on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) from public, anon, authenticated;
grant execute on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) to service_role;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');

-- ===== 17_interventions_r2.sql — copie générée de supabase/interventions_r2.sql (empreinte 1adb58e1a07caded) : ne pas modifier ici =====
-- GMAO terrain — lot R2 « fiche intervention en étapes » (docs/MAQUETTES_R2.md §2, §3, §7). APRÈS roles_r1.sql. Rejouable.
-- FICHIER GÉNÉRÉ par scripts/generer_interventions_r2.py : ne pas modifier à la main.
-- Q6 : le terrain (technicien, prestataire) propose la nature et la priorité ; le responsable valide.
--   Toute nature / priorité écrite par le terrain est rangée en « proposée » (natureProposee, prioriteProposee,
--   qualificationValidee = false) — y compris par une ancienne version de l'appli ; exception : préventif lancé
--   depuis un programme (nature fixée par le programme). Le terrain ne peut ni valider, ni proposer sur une
--   qualification déjà validée par le responsable.
-- Q9 : terminer ou clôturer une intervention avec arrêt non planifié exige la remise à disposition ou « heures
--   inconnues ». Contrôle serveur sur les arrêts saisis depuis R2 (champ arretType présent) ; l'appli contrôle aussi
--   les plus anciens (type déduit de la nature). Les temps des intervenants ne sont jamais demandés.

create or replace function public.r2_qualif_terrain(p jsonb, d jsonb, nouvelle boolean)
returns jsonb language plpgsql immutable set search_path = public as $$
declare q jsonb := p;
begin
  if nouvelle and coalesce(p->>'programmeId', '') <> '' then return p; end if;   -- préventif d'un programme
  if p ? 'nature' and p->>'nature' is distinct from coalesce(d->>'nature', 'a_qualifier') then
    q := (q - 'nature') || jsonb_build_object('natureProposee', p->'nature', 'qualificationValidee', false);
    if nouvelle then q := q || '{"nature":"a_qualifier"}'::jsonb; end if;
  end if;
  if p ? 'priorite' and p->>'priorite' is distinct from coalesce(d->>'priorite', 'a_qualifier') then
    q := (q - 'priorite') || jsonb_build_object('prioriteProposee', p->'priorite', 'qualificationValidee', false);
    if nouvelle then q := q || '{"priorite":"a_qualifier"}'::jsonb; end if;
  end if;
  return q;
end $$;
revoke all on function public.r2_qualif_terrain(jsonb, jsonb, boolean) from public, anon, authenticated;

create or replace function public.r2_arret_incomplet(d jsonb)
returns boolean language sql immutable set search_path = public as $$
  select d->>'avecArret' = 'oui' and d ? 'arretType'
     and coalesce(d->>'arretType',
           case when (case when d->'qualificationValidee' = 'false'::jsonb then coalesce(d->>'natureProposee', d->>'nature') else d->>'nature' end)
                     in ('preventive', 'travaux_techniques') then 'planifie' else 'non_planifie' end) = 'non_planifie'
     and coalesce(d->>'arretFin', '') = ''
     and d->'arretHeuresInconnues' is distinct from 'true'::jsonb
$$;
revoke all on function public.r2_arret_incomplet(jsonb) from public, anon, authenticated;

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean; mod text; u text;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- R2 : nature et priorité écrites par le terrain = proposition (le responsable valide).
    if t = 'ots' and terrain then p := public.r2_qualif_terrain(p, ex.data, ex.id is null); end if;
    -- D2 bis : un compteur d'équipement (heures, cycles) relève du préventif, un compteur de ressource de l'énergie.
    mod := public.module_de(cible);
    if cible in ('compteurs', 'releves') then
      u := case
        when t = 'compteurs' then coalesce(p->>'usage', ex.data->>'usage')
        when t = 'releves' then (select c.data->>'usage' from fiches c where c.id = coalesce(p->>'compteurId', ex.data->>'compteurId') and c.entreprise_id = ent)
        else (select case when x.type = 'compteurs' then x.data->>'usage'
                          else (select c.data->>'usage' from fiches c where c.id = x.data->>'compteurId' and c.entreprise_id = ent) end
              from fiches x where x.id = p->>'entiteId' and x.entreprise_id = ent)
      end;
      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? mod) then
      motif := 'module « ' || mod || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    -- R1 : un prestataire n'écrit que sur les interventions qui lui sont confiées (et ce qui s'y rattache).
    elsif r = 'prestataire' and public.prestataire_refus(t, f->>'id', p, ex.id is null) is not null then
      motif := public.prestataire_refus(t, f->>'id', p, ex.id is null);
    elsif t = 'ots' and terrain and (p->'qualificationValidee' = 'true'::jsonb or p ? 'qualifieePar' or p ? 'qualifieeLe') then
      motif := 'validation de la qualification : réservée au responsable';
    elsif t = 'ots' and terrain and ex.data->'qualificationValidee' = 'true'::jsonb
          and (p ? 'natureProposee' or p ? 'prioriteProposee' or p ? 'qualificationValidee') then
      motif := 'qualification déjà validée par le responsable : demandez-lui de la changer';
    elsif t = 'ots' and p->>'statut' in ('cloturee', 'travail_termine') and coalesce(ex.data->>'statut', '') <> p->>'statut'
          and public.r2_arret_incomplet(coalesce(ex.data, '{}'::jsonb) || p) then
      motif := 'arrêt non planifié : indiquer la remise à disposition ou « heures inconnues »';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    elsif t = 'ots' and r <> 'responsable' and p->>'statut' = 'cloturee' and public.cloture_par_responsable(ent) then
      motif := 'clôture réservée au responsable (réglage de l''entreprise) : terminez l''intervention, le responsable la clôture';
    -- réglages de l'entreprise : une seule fiche, d'identifiant fixe
    elsif t = 'parametres' and f->>'id' <> ('parametres-' || ent::text) then
      motif := 'paramètres : identifiant réservé à l''entreprise';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    -- intégrité : une fiche rattachée à un équipement exige un équipement connu de l'entreprise (lot en cours compris)
    elsif t in ('demandes', 'ots', 'programmes') and ex.id is null and coalesce(p->>'equipementId', '') <> ''
          and not exists (select 1 from fiches x where x.id = p->>'equipementId' and x.type = 'equipements' and x.entreprise_id = ent) then
      motif := 'équipement inconnu de l''entreprise (créé hors connexion ou supprimé ?)';
    -- volet D : compteurs (référentiel du responsable), relevés jamais modifiés, factures à lecture restreinte
    elsif t = 'compteurs' and ex.id is not null
          and ((p ? 'mode' and p->'mode' is distinct from ex.data->'mode') or (p ? 'unite' and p->'unite' is distinct from ex.data->'unite')
               or (p ? 'coefficient' and p->'coefficient' is distinct from ex.data->'coefficient')
               or (p ? 'usage' and p->'usage' is distinct from ex.data->'usage'))
          and exists (select 1 from fiches x where x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = ex.id) then
      motif := 'compteur déjà relevé : usage, mode, unité et coefficient ne changent plus (rupture déclarée ou nouveau compteur)';
    elsif t = 'releves' and ex.id is null and not exists (select 1 from fiches c where c.id = p->>'compteurId' and c.type = 'compteurs' and c.entreprise_id = ent) then
      motif := 'un relevé se rattache à un compteur connu';
    elsif t = 'releves' and ex.id is null and r <> 'responsable' and (p ? 'decision' or p ? 'decidePar' or p ? 'decideLe') then
      motif := 'qualification d''un relevé : réservée au responsable';
    elsif t = 'releves' and ex.id is null and coalesce(p->>'remplaceId', '') <> '' and not exists (
            select 1 from fiches x where x.id = p->>'remplaceId' and x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = p->>'compteurId') then
      motif := 'une correction remplace un relevé du même compteur';
    elsif t = 'releves' and ex.id is not null and (r <> 'responsable' or exists (
            select 1 from jsonb_object_keys(p) k where k not in ('decision', 'motifDecision', 'decideLe', 'decidePar', 'modifieLe', 'modifiePar'))) then
      motif := 'un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)';
    end if;

    if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        case when t = 'releves' then (select site_id from fiches where id = p->>'compteurId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;

revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');

-- ===== 18_membres_r3.sql — copie générée de supabase/membres_r3.sql (empreinte 41d62da7f62651bb) : ne pas modifier ici =====
-- GMAO terrain — lot R3 « membres, équipes, sociétés prestataires » (docs/MAQUETTES_R3.md §1 à §9). APRÈS interventions_r2.sql.
-- Rejouable. FICHIER GÉNÉRÉ par scripts/generer_membres_r3.py : ne pas modifier à la main.
-- Membre = fiche « personnes » (avec ou sans compte) ; le compte (profils.personne_id) y est relié. Nom et rôle d'un membre
--   avec accès : une seule valeur (definir_profil écrit les deux ; le nom changé sur la fiche passe au compte) ; le rôle
--   et la désactivation d'un membre avec accès ne passent pas par la fiche. Retirer l'accès ne rend pas le membre inactif.
-- relier_membre : relie un compte (juste invité) à une fiche membre existante (pas de doublon).
-- Membres, équipes (nouveau type « equipes ») et sociétés prestataires (fiche « fournisseurs » avec prestataire = true,
--   module de base) : écrits par le responsable et l'administrateur ; chacun peut changer son nom et son téléphone.
-- Interventions : equipeId / societeId posés par le responsable (refusés au terrain).
-- Prestataire (Q3 élargi) : voit ses interventions ET celles confiées à sa société (societeId de sa fiche membre), la
--   fiche de sa société et les équipes.
-- Reprise : fiches des comptes alignées (nom, rôle) ; texte libre « societe » → société prestataire + societeId.

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs','equipes'));

/** Société de l'appelant (fiche « fournisseurs » prestataire), lue sur sa fiche membre. */
create or replace function public.ma_societe()
returns text language sql stable security definer set search_path = public as $$
  select nullif(f.data->>'societeId', '') from fiches f
  where f.id = public.ma_personne() and f.type = 'personnes' and f.entreprise_id = public.mon_entreprise()
$$;
revoke all on function public.ma_societe() from public, anon, authenticated;

/** Intervention confiée à l'appelant : il en est intervenant, ou elle est confiée à sa société. */
create or replace function public.ot_a_moi(oid text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(oid, '') <> '' and exists (
    select 1 from fiches o where o.id = oid and o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and (o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne()))
           or (public.ma_societe() is not null and o.data->>'societeId' = public.ma_societe())))
$$;
revoke all on function public.ot_a_moi(text) from public, anon, authenticated;

create or replace function public.prestataire_voit(t text, fid text, d jsonb, aut uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  if t in ('equipements', 'localisations', 'personnes', 'articles', 'compteurs', 'releves', 'parametres', 'journal', 'equipes') then return true; end if;
  if t = 'fournisseurs' then return fid = public.ma_societe(); end if;   -- R3 : sa société seulement
  if t = 'ots' then return public.ot_a_moi(fid); end if;
  if t = 'demandes' then
    return aut = auth.uid() or exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'demandeIds' ? fid and public.ot_a_moi(o.id));
  end if;
  if t in ('besoins', 'mouvements') then return public.ot_a_moi(d->>'otId'); end if;
  if t = 'programmes' then
    return exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise() and o.data->>'programmeId' = fid
      and public.ot_a_moi(o.id));
  end if;
  if t = 'photos' then
    select type, id, data, auteur into x from fiches where id = d->>'parentId' and entreprise_id = public.mon_entreprise();
    return found and x.type <> 'photos' and public.prestataire_voit(x.type, x.id, x.data, x.auteur);
  end if;
  return false;   -- magasin, achats, prix, seuils, factures, fournisseurs…
end $$;

create or replace function public.journal_visible(d jsonb, aut uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  if public.voit_journal_complet() or aut = auth.uid() then return true; end if;
  select type, id, data, auteur into x from fiches where id = d->>'entiteId' and entreprise_id = public.mon_entreprise();
  if not found then return false; end if;
  if x.auteur = auth.uid() then return true; end if;                       -- ses propres fiches
  if x.type = 'ots' then return public.ot_a_moi(x.id); end if;             -- ses interventions
  if x.type in ('besoins', 'mouvements') then return public.ot_a_moi(x.data->>'otId'); end if;
  if x.type = 'demandes' then
    return exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'demandeIds' ? x.id and public.ot_a_moi(o.id));
  end if;
  return false;
end $$;

create or replace function public.definir_profil(cible uuid, nouveau_role text, nouveau_nom text, est_actif boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.est_admin_client() then
    raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501';
  end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = public.mon_entreprise()) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if cible = auth.uid() and not est_actif then
    raise exception 'Vous ne pouvez pas désactiver votre propre compte';
  end if;
  update profils set role = coalesce(nouveau_role, role), nom = coalesce(nullif(trim(nouveau_nom), ''), nom),
    actif = coalesce(est_actif, actif) where user_id = cible;
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'nom', p.nom),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = p.personne_id;
end $$;

revoke all on function public.prestataire_voit(text, text, jsonb, uuid) from public, anon;
grant execute on function public.prestataire_voit(text, text, jsonb, uuid) to authenticated;   -- appelée par la règle de lecture
revoke all on function public.journal_visible(jsonb, uuid) from public, anon;
grant execute on function public.journal_visible(jsonb, uuid) to authenticated;
revoke all on function public.definir_profil(uuid, text, text, boolean) from public, anon;
grant execute on function public.definir_profil(uuid, text, text, boolean) to authenticated;

/** Relier un compte de l'entreprise à une fiche membre existante (après « Donner un accès »). La fiche prend le rôle
    du compte ; le compte prend le nom de la fiche ; l'ancienne fiche du compte, s'il en avait une autre, devient inactive. */
create or replace function public.relier_membre(cible uuid, personne text)
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); ancien text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = ent) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if not exists (select 1 from fiches where id = personne and type = 'personnes' and entreprise_id = ent) then
    raise exception 'Membre inconnu de l''entreprise';
  end if;
  if exists (select 1 from profils where personne_id = personne and user_id <> cible) then
    raise exception 'Ce membre a déjà un autre accès';
  end if;
  select personne_id into ancien from profils where user_id = cible;
  update profils set personne_id = personne,
    nom = coalesce(nullif(trim((select data->>'nom' from fiches where id = personne)), ''), nom) where user_id = cible;
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'email', p.email, 'actif', true,
      'modifieLe', maintenant, 'modifiePar', 'serveur'), seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = personne;
  if ancien is not null and ancien <> personne then
    update fiches set data = data || jsonb_build_object('actif', false, 'remplaceePar', personne, 'modifieLe', maintenant, 'modifiePar', 'serveur'),
      seq = nextval('public.fiches_seq'), recu_le = now()
    where id = ancien and type = 'personnes' and entreprise_id = ent;
  end if;
end $$;
revoke all on function public.relier_membre(uuid, text) from public, anon;
grant execute on function public.relier_membre(uuid, text) to authenticated;

-- ---------- Reprise de l'existant (rejouable : ne refait rien la deuxième fois) ----------
create or replace function public.r3_reprise()
returns void language plpgsql security definer set search_path = public as $$
declare x record; sid text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  -- 1) fiche d'un compte : même nom et même rôle que le compte
  update fiches f set data = f.data || jsonb_build_object('nom', coalesce(nullif(trim(p.nom), ''), f.data->>'nom'), 'role', p.role),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.personne_id = f.id and f.type = 'personnes' and f.entreprise_id = p.entreprise_id
    and (f.data->>'role' is distinct from p.role or (coalesce(trim(p.nom), '') <> '' and f.data->>'nom' is distinct from trim(p.nom)));
  -- 2) texte libre « societe » → société prestataire (même nom sans casse ni accents) + societeId
  for x in select f.id, f.entreprise_id, trim(f.data->>'societe') as nom from fiches f
           where f.type = 'personnes' and coalesce(trim(f.data->>'societe'), '') <> '' and coalesce(f.data->>'societeId', '') = '' loop
    select s.id into sid from fiches s where s.type = 'fournisseurs' and s.entreprise_id = x.entreprise_id
      and lower(translate(trim(s.data->>'nom'), 'ÀÂÄÉÈÊËÎÏÔÖÙÛÜÇàâäéèêëîïôöùûüç', 'AAAEEEEIIOOUUUCaaaeeeeiioouuuc'))
        = lower(translate(x.nom, 'ÀÂÄÉÈÊËÎÏÔÖÙÛÜÇàâäéèêëîïôöùûüç', 'AAAEEEEIIOOUUUCaaaeeeeiioouuuc')) limit 1;
    if sid is null then
      sid := 'soc-' || substr(md5(x.entreprise_id::text || lower(x.nom)), 1, 16);
      insert into fiches (id, type, data, entreprise_id) values (sid, 'fournisseurs', jsonb_build_object('id', sid, 'nom', x.nom,
        'prestataire', true, 'actif', true, 'creeLe', maintenant, 'creePar', 'serveur', 'modifieLe', maintenant, 'modifiePar', 'serveur'), x.entreprise_id)
      on conflict (id) do nothing;
    else
      update fiches set data = data || '{"prestataire":true}'::jsonb, seq = nextval('public.fiches_seq'), recu_le = now()
      where id = sid and data->>'prestataire' is distinct from 'true';
    end if;
    update fiches set data = data || jsonb_build_object('societeId', sid), seq = nextval('public.fiches_seq'), recu_le = now() where id = x.id;
    sid := null;
  end loop;
end $$;
revoke all on function public.r3_reprise() from public, anon, authenticated;
select public.r3_reprise();

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean; mod text; u text; gere boolean; soi boolean; lie boolean;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  gere := r = 'responsable' or public.est_admin_client();   -- R3 : membres, équipes, sociétés prestataires
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- R2 : nature et priorité écrites par le terrain = proposition (le responsable valide).
    if t = 'ots' and terrain then p := public.r2_qualif_terrain(p, ex.data, ex.id is null); end if;
    -- D2 bis : un compteur d'équipement (heures, cycles) relève du préventif, un compteur de ressource de l'énergie.
    mod := public.module_de(cible);
    if cible in ('compteurs', 'releves') then
      u := case
        when t = 'compteurs' then coalesce(p->>'usage', ex.data->>'usage')
        when t = 'releves' then (select c.data->>'usage' from fiches c where c.id = coalesce(p->>'compteurId', ex.data->>'compteurId') and c.entreprise_id = ent)
        else (select case when x.type = 'compteurs' then x.data->>'usage'
                          else (select c.data->>'usage' from fiches c where c.id = x.data->>'compteurId' and c.entreprise_id = ent) end
              from fiches x where x.id = p->>'entiteId' and x.entreprise_id = ent)
      end;
      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
    -- R3 : une société prestataire relève du module de base (pas du magasin).
    if cible = 'fournisseurs' and (t = 'journal' or coalesce(p->>'prestataire', ex.data->>'prestataire', '') = 'true') then mod := 'base'; end if;
    -- R3 : sa propre fiche membre (nom, téléphone) ; fiche reliée à un compte (rôle par l'administrateur).
    soi := cible = 'personnes' and coalesce(case when t = 'journal' then p->>'entiteId' else f->>'id' end, '') = coalesce(public.ma_personne(), '-')
           and (t = 'journal' or (ex.id is not null and not exists (
             select 1 from jsonb_object_keys(p) k where k not in ('nom', 'telephone', 'modifieLe', 'modifiePar'))));
    lie := t = 'personnes' and exists (select 1 from profils x where x.personne_id = f->>'id' and x.entreprise_id = ent);
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs','equipes') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? mod) then
      motif := 'module « ' || mod || ' » non inclus dans l''abonnement';
    elsif cible in ('personnes', 'equipes') and not gere and not soi then
      motif := 'membres et équipes : réservés au responsable et à l''administrateur';
    elsif cible not in ('personnes', 'equipes') and not (cible = 'fournisseurs' and gere) and not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'fournisseurs' and not gere and (p->>'prestataire' = 'true' or ex.data->>'prestataire' = 'true') then
      motif := 'société prestataire : réservée au responsable et à l''administrateur';
    elsif lie and ex.id is not null and ((p ? 'role' and p->'role' is distinct from ex.data->'role')
          or (p ? 'actif' and p->'actif' is distinct from ex.data->'actif' and p->'actif' = 'false'::jsonb)) then
      motif := 'membre avec un accès : rôle et accès se changent par l''administrateur (Membres)';
    elsif t = 'ots' and terrain and ((p ? 'equipeId' and p->'equipeId' is distinct from coalesce(ex.data->'equipeId', 'null'::jsonb) and coalesce(p->>'equipeId', '') <> '')
          or (p ? 'societeId' and p->'societeId' is distinct from coalesce(ex.data->'societeId', 'null'::jsonb) and coalesce(p->>'societeId', '') <> '')) then
      motif := 'intervention confiée à une équipe ou une société : réservé au responsable';
    -- R1 : un prestataire n'écrit que sur les interventions qui lui sont confiées (et ce qui s'y rattache).
    elsif r = 'prestataire' and public.prestataire_refus(t, f->>'id', p, ex.id is null) is not null then
      motif := public.prestataire_refus(t, f->>'id', p, ex.id is null);
    elsif t = 'ots' and terrain and (p->'qualificationValidee' = 'true'::jsonb or p ? 'qualifieePar' or p ? 'qualifieeLe') then
      motif := 'validation de la qualification : réservée au responsable';
    elsif t = 'ots' and terrain and ex.data->'qualificationValidee' = 'true'::jsonb
          and (p ? 'natureProposee' or p ? 'prioriteProposee' or p ? 'qualificationValidee') then
      motif := 'qualification déjà validée par le responsable : demandez-lui de la changer';
    elsif t = 'ots' and p->>'statut' in ('cloturee', 'travail_termine') and coalesce(ex.data->>'statut', '') <> p->>'statut'
          and public.r2_arret_incomplet(coalesce(ex.data, '{}'::jsonb) || p) then
      motif := 'arrêt non planifié : indiquer la remise à disposition ou « heures inconnues »';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    elsif t = 'ots' and r <> 'responsable' and p->>'statut' = 'cloturee' and public.cloture_par_responsable(ent) then
      motif := 'clôture réservée au responsable (réglage de l''entreprise) : terminez l''intervention, le responsable la clôture';
    -- réglages de l'entreprise : une seule fiche, d'identifiant fixe
    elsif t = 'parametres' and f->>'id' <> ('parametres-' || ent::text) then
      motif := 'paramètres : identifiant réservé à l''entreprise';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    -- intégrité : une fiche rattachée à un équipement exige un équipement connu de l'entreprise (lot en cours compris)
    elsif t in ('demandes', 'ots', 'programmes') and ex.id is null and coalesce(p->>'equipementId', '') <> ''
          and not exists (select 1 from fiches x where x.id = p->>'equipementId' and x.type = 'equipements' and x.entreprise_id = ent) then
      motif := 'équipement inconnu de l''entreprise (créé hors connexion ou supprimé ?)';
    -- volet D : compteurs (référentiel du responsable), relevés jamais modifiés, factures à lecture restreinte
    elsif t = 'compteurs' and ex.id is not null
          and ((p ? 'mode' and p->'mode' is distinct from ex.data->'mode') or (p ? 'unite' and p->'unite' is distinct from ex.data->'unite')
               or (p ? 'coefficient' and p->'coefficient' is distinct from ex.data->'coefficient')
               or (p ? 'usage' and p->'usage' is distinct from ex.data->'usage'))
          and exists (select 1 from fiches x where x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = ex.id) then
      motif := 'compteur déjà relevé : usage, mode, unité et coefficient ne changent plus (rupture déclarée ou nouveau compteur)';
    elsif t = 'releves' and ex.id is null and not exists (select 1 from fiches c where c.id = p->>'compteurId' and c.type = 'compteurs' and c.entreprise_id = ent) then
      motif := 'un relevé se rattache à un compteur connu';
    elsif t = 'releves' and ex.id is null and r <> 'responsable' and (p ? 'decision' or p ? 'decidePar' or p ? 'decideLe') then
      motif := 'qualification d''un relevé : réservée au responsable';
    elsif t = 'releves' and ex.id is null and coalesce(p->>'remplaceId', '') <> '' and not exists (
            select 1 from fiches x where x.id = p->>'remplaceId' and x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = p->>'compteurId') then
      motif := 'une correction remplace un relevé du même compteur';
    elsif t = 'releves' and ex.id is not null and (r <> 'responsable' or exists (
            select 1 from jsonb_object_keys(p) k where k not in ('decision', 'motifDecision', 'decideLe', 'decidePar', 'modifieLe', 'modifiePar'))) then
      motif := 'un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)';
    end if;

    if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs', 'equipes') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        case when t = 'releves' then (select site_id from fiches where id = p->>'compteurId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    -- R3 : le nom d'un membre avec accès est aussi celui de son compte.
    if t = 'personnes' and lie and coalesce(trim(p->>'nom'), '') <> '' then
      update profils set nom = trim(p->>'nom') where personne_id = f->>'id' and entreprise_id = ent;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;

revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');

-- ===== 19_stabilite_s1.sql — copie générée de supabase/stabilite_s1.sql (empreinte 89903bcafc20da74) : ne pas modifier ici =====
-- GMAO terrain — lot S1 de stabilisation (docs/AUDIT_STABILITE_MODELE.md §4 A et D). APRÈS membres_r3.sql. Rejouable.
-- FICHIER GÉNÉRÉ par scripts/generer_stabilite_s1.py : ne pas modifier à la main.
-- A : listes fusionnées élément par élément. Une liste dont tous les éléments ont un « id » (intervenants, pièces,
--     réserves, lignes…) ou sont de simples valeurs (activités, demandeIds, membreIds…) n'est plus remplacée en entier :
--     l'appareil décrit ses changements (« $listes » : clés ajoutées ou modifiées, clés retirées) ; le serveur garde ses
--     éléments et n'applique que ces changements. Sans description (ancienne appli) : tous les éléments envoyés
--     comptent comme modifiés, rien n'est retiré. Autres listes : remplacées comme avant.
-- D : version minimale de l'appli (pf_reglages.version_minimale, « v0 » = pas de contrôle) : push_fiches(lot, version)
--     refuse tout le lot d'une version plus ancienne, seulement quand l'appel vient de l'API (pas du SQL Editor).
--     Pour l'imposer : update public.pf_reglages set valeur = 'v39' where cle = 'version_minimale';

create table if not exists public.pf_reglages (cle text primary key, valeur text not null);
alter table public.pf_reglages enable row level security;
revoke all on public.pf_reglages from public, anon, authenticated;
insert into public.pf_reglages (cle, valeur) values ('version_minimale', 'v0') on conflict (cle) do nothing;

create or replace function public.s1_version_num(v text)
returns integer language sql immutable set search_path = public as $$
  select coalesce(nullif(regexp_replace(coalesce(v, ''), '[^0-9]', '', 'g'), '')::integer, 0)
$$;
revoke all on function public.s1_version_num(text) from public, anon, authenticated;

/** Motif de refus si l'appli qui appelle par l'API est plus ancienne que la version minimale (null = accepté). */
create or replace function public.s1_version_refus(version text)
returns text language plpgsql stable security definer set search_path = public as $$
declare mini text := (select valeur from pf_reglages where cle = 'version_minimale');
begin
  if current_setting('request.method', true) is null or current_setting('request.method', true) = '' then return null; end if;
  if public.s1_version_num(version) < public.s1_version_num(mini) then
    return 'Version de l''appli trop ancienne (' || coalesce(version, 'inconnue') || ') : rechargez la page pour passer à la version '
      || mini || ' ou plus récente. Vos saisies restent sur l''appareil.';
  end if;
  return null;
end $$;
revoke all on function public.s1_version_refus(text) from public, anon, authenticated;

/** Clé d'un élément de liste : son « id » (objet), sa valeur (texte, nombre) ; null si l'élément n'a pas de clé. */
create or replace function public.s1_cle(e jsonb)
returns text language sql immutable set search_path = public as $$
  select case jsonb_typeof(e) when 'object' then e->>'id' when 'array' then null when 'null' then null else e #>> '{}' end
$$;
revoke all on function public.s1_cle(jsonb) from public, anon, authenticated;

create or replace function public.s1_fusionnable(a jsonb)
returns boolean language sql immutable set search_path = public as $$
  select jsonb_typeof(a) = 'array' and not exists (select 1 from jsonb_array_elements(a) x where public.s1_cle(x) is null)
$$;
revoke all on function public.s1_fusionnable(jsonb) from public, anon, authenticated;

/** Fusion des listes d'un patch avec la fiche du serveur (voir l'en-tête). listes = { champ: { modifies: [clés],
    retraits: [clés] } } : seuls les éléments ajoutés ou modifiés par l'appareil remplacent ceux du serveur ; sans
    description (ancienne appli), tous les éléments envoyés comptent comme modifiés (rien n'est retiré). */
create or replace function public.s1_fusion_listes(d jsonb, p jsonb, listes jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare k text; a jsonb; b jsonb; m jsonb; rem text[]; mod text[]; vus text[]; res jsonb; e jsonb; c text;
begin
  if d is null then return p; end if;
  for k in select jsonb_object_keys(p) loop
    a := d->k; b := p->k;
    continue when not public.s1_fusionnable(a) or not public.s1_fusionnable(b);
    m := case when jsonb_typeof(listes->k) = 'object' then listes->k else '{}'::jsonb end;
    rem := array(select jsonb_array_elements_text(case when jsonb_typeof(m->'retraits') = 'array' then m->'retraits' else '[]'::jsonb end));
    mod := case when jsonb_typeof(m->'modifies') = 'array' then array(select jsonb_array_elements_text(m->'modifies'))
                else array(select public.s1_cle(x) from jsonb_array_elements(b) x) end;
    res := '[]'::jsonb; vus := '{}';
    for e in select value from jsonb_array_elements(a) loop        -- ce que le serveur a déjà, dans son ordre
      c := public.s1_cle(e);
      continue when c = any (vus);
      vus := vus || c;
      continue when c = any (rem);
      res := res || jsonb_build_array(case when c = any (mod)
        then coalesce((select x from jsonb_array_elements(b) x where public.s1_cle(x) = c limit 1), e) else e end);
    end loop;
    for e in select value from jsonb_array_elements(b) loop        -- puis les éléments ajoutés par l'appareil
      c := public.s1_cle(e);
      continue when c = any (vus) or c = any (rem) or not (c = any (mod));
      vus := vus || c;
      res := res || jsonb_build_array(e);
    end loop;
    p := jsonb_set(p, array[k], res);
  end loop;
  return p;
end $$;
revoke all on function public.s1_fusion_listes(jsonb, jsonb, jsonb) from public, anon, authenticated;

-- Nouvelle signature (version de l'appli) : l'ancienne est retirée ; les appels « push_fiches(lot) » restent valables.
drop function if exists public.push_fiches(jsonb);

create or replace function public.push_fiches(lot jsonb, version text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean; mod text; u text; gere boolean; soi boolean; lie boolean; listes jsonb;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  -- S1 : version minimale de l'appli (appel par l'API seulement ; rien n'est accepté, la file reste sur le téléphone).
  motif := public.s1_version_refus(version);
  if motif is not null then raise exception '%', motif using errcode = 'P0001'; end if;
  terrain := r in ('technicien', 'prestataire');
  gere := r = 'responsable' or public.est_admin_client();   -- R3 : membres, équipes, sociétés prestataires
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    -- S1 : changements de listes décrits par l'appareil (jamais enregistrés tels quels).
    listes := p->'$listes'; p := p - '$listes';
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- R2 : nature et priorité écrites par le terrain = proposition (le responsable valide).
    if t = 'ots' and terrain then p := public.r2_qualif_terrain(p, ex.data, ex.id is null); end if;
    -- D2 bis : un compteur d'équipement (heures, cycles) relève du préventif, un compteur de ressource de l'énergie.
    mod := public.module_de(cible);
    if cible in ('compteurs', 'releves') then
      u := case
        when t = 'compteurs' then coalesce(p->>'usage', ex.data->>'usage')
        when t = 'releves' then (select c.data->>'usage' from fiches c where c.id = coalesce(p->>'compteurId', ex.data->>'compteurId') and c.entreprise_id = ent)
        else (select case when x.type = 'compteurs' then x.data->>'usage'
                          else (select c.data->>'usage' from fiches c where c.id = x.data->>'compteurId' and c.entreprise_id = ent) end
              from fiches x where x.id = p->>'entiteId' and x.entreprise_id = ent)
      end;
      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
    -- R3 : une société prestataire relève du module de base (pas du magasin).
    if cible = 'fournisseurs' and (t = 'journal' or coalesce(p->>'prestataire', ex.data->>'prestataire', '') = 'true') then mod := 'base'; end if;
    -- R3 : sa propre fiche membre (nom, téléphone) ; fiche reliée à un compte (rôle par l'administrateur).
    soi := cible = 'personnes' and coalesce(case when t = 'journal' then p->>'entiteId' else f->>'id' end, '') = coalesce(public.ma_personne(), '-')
           and (t = 'journal' or (ex.id is not null and not exists (
             select 1 from jsonb_object_keys(p) k where k not in ('nom', 'telephone', 'modifieLe', 'modifiePar'))));
    lie := t = 'personnes' and exists (select 1 from profils x where x.personne_id = f->>'id' and x.entreprise_id = ent);
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs','equipes') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? mod) then
      motif := 'module « ' || mod || ' » non inclus dans l''abonnement';
    elsif cible in ('personnes', 'equipes') and not gere and not soi then
      motif := 'membres et équipes : réservés au responsable et à l''administrateur';
    elsif cible not in ('personnes', 'equipes') and not (cible = 'fournisseurs' and gere) and not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'fournisseurs' and not gere and (p->>'prestataire' = 'true' or ex.data->>'prestataire' = 'true') then
      motif := 'société prestataire : réservée au responsable et à l''administrateur';
    elsif lie and ex.id is not null and ((p ? 'role' and p->'role' is distinct from ex.data->'role')
          or (p ? 'actif' and p->'actif' is distinct from ex.data->'actif' and p->'actif' = 'false'::jsonb)) then
      motif := 'membre avec un accès : rôle et accès se changent par l''administrateur (Membres)';
    elsif t = 'ots' and terrain and ((p ? 'equipeId' and p->'equipeId' is distinct from coalesce(ex.data->'equipeId', 'null'::jsonb) and coalesce(p->>'equipeId', '') <> '')
          or (p ? 'societeId' and p->'societeId' is distinct from coalesce(ex.data->'societeId', 'null'::jsonb) and coalesce(p->>'societeId', '') <> '')) then
      motif := 'intervention confiée à une équipe ou une société : réservé au responsable';
    -- R1 : un prestataire n'écrit que sur les interventions qui lui sont confiées (et ce qui s'y rattache).
    elsif r = 'prestataire' and public.prestataire_refus(t, f->>'id', p, ex.id is null) is not null then
      motif := public.prestataire_refus(t, f->>'id', p, ex.id is null);
    elsif t = 'ots' and terrain and (p->'qualificationValidee' = 'true'::jsonb or p ? 'qualifieePar' or p ? 'qualifieeLe') then
      motif := 'validation de la qualification : réservée au responsable';
    elsif t = 'ots' and terrain and ex.data->'qualificationValidee' = 'true'::jsonb
          and (p ? 'natureProposee' or p ? 'prioriteProposee' or p ? 'qualificationValidee') then
      motif := 'qualification déjà validée par le responsable : demandez-lui de la changer';
    elsif t = 'ots' and p->>'statut' in ('cloturee', 'travail_termine') and coalesce(ex.data->>'statut', '') <> p->>'statut'
          and public.r2_arret_incomplet(coalesce(ex.data, '{}'::jsonb) || p) then
      motif := 'arrêt non planifié : indiquer la remise à disposition ou « heures inconnues »';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    elsif t = 'ots' and r <> 'responsable' and p->>'statut' = 'cloturee' and public.cloture_par_responsable(ent) then
      motif := 'clôture réservée au responsable (réglage de l''entreprise) : terminez l''intervention, le responsable la clôture';
    -- réglages de l'entreprise : une seule fiche, d'identifiant fixe
    elsif t = 'parametres' and f->>'id' <> ('parametres-' || ent::text) then
      motif := 'paramètres : identifiant réservé à l''entreprise';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    -- intégrité : une fiche rattachée à un équipement exige un équipement connu de l'entreprise (lot en cours compris)
    elsif t in ('demandes', 'ots', 'programmes') and ex.id is null and coalesce(p->>'equipementId', '') <> ''
          and not exists (select 1 from fiches x where x.id = p->>'equipementId' and x.type = 'equipements' and x.entreprise_id = ent) then
      motif := 'équipement inconnu de l''entreprise (créé hors connexion ou supprimé ?)';
    -- volet D : compteurs (référentiel du responsable), relevés jamais modifiés, factures à lecture restreinte
    elsif t = 'compteurs' and ex.id is not null
          and ((p ? 'mode' and p->'mode' is distinct from ex.data->'mode') or (p ? 'unite' and p->'unite' is distinct from ex.data->'unite')
               or (p ? 'coefficient' and p->'coefficient' is distinct from ex.data->'coefficient')
               or (p ? 'usage' and p->'usage' is distinct from ex.data->'usage'))
          and exists (select 1 from fiches x where x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = ex.id) then
      motif := 'compteur déjà relevé : usage, mode, unité et coefficient ne changent plus (rupture déclarée ou nouveau compteur)';
    elsif t = 'releves' and ex.id is null and not exists (select 1 from fiches c where c.id = p->>'compteurId' and c.type = 'compteurs' and c.entreprise_id = ent) then
      motif := 'un relevé se rattache à un compteur connu';
    elsif t = 'releves' and ex.id is null and r <> 'responsable' and (p ? 'decision' or p ? 'decidePar' or p ? 'decideLe') then
      motif := 'qualification d''un relevé : réservée au responsable';
    elsif t = 'releves' and ex.id is null and coalesce(p->>'remplaceId', '') <> '' and not exists (
            select 1 from fiches x where x.id = p->>'remplaceId' and x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = p->>'compteurId') then
      motif := 'une correction remplace un relevé du même compteur';
    elsif t = 'releves' and ex.id is not null and (r <> 'responsable' or exists (
            select 1 from jsonb_object_keys(p) k where k not in ('decision', 'motifDecision', 'decideLe', 'decidePar', 'modifieLe', 'modifiePar'))) then
      motif := 'un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)';
    end if;

    if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs', 'equipes') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        case when t = 'releves' then (select site_id from fiches where id = p->>'compteurId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    -- S1 : une liste modifiée en même temps par deux appareils garde les ajouts des deux (fusion élément par élément).
    if ex.id is not null and t not in ('journal', 'mouvements', 'photos') then
      p := public.s1_fusion_listes(ex.data, p, listes);
    end if;
    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    -- R3 : le nom d'un membre avec accès est aussi celui de son compte.
    if t = 'personnes' and lie and coalesce(trim(p->>'nom'), '') <> '' then
      update profils set nom = trim(p->>'nom') where personne_id = f->>'id' and entreprise_id = ent;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;

revoke all on function public.push_fiches(jsonb, text) from public, anon;
grant execute on function public.push_fiches(jsonb, text) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');

-- ===== 20_demo.sql — copie générée de supabase/demo.sql (empreinte 8e724fa0fbc29b27) : ne pas modifier ici =====
-- GMAO terrain — démo commerciale (rejouable). APRÈS achats.sql.
-- Remplace pf_reinitialiser_demo de plateforme.sql (ne pas rejouer plateforme.sql en entier après achats.sql :
-- controle_invitation y est dans sa version d'avant le rôle « achats »).
-- Contenu : volets A et B (équipements, demandes, interventions, préventif, besoins de pièces, retrait urgent)
-- + volet C : prix des entrées de stock (un provisoire), seuil validé du joint (déclenche « À réapprovisionner »),
-- seuil proposé du filtre (à valider), demande d'achat DA-DEMO-0001 commandée (3 filtres, livraison demain).
-- Les écrans Achats et Valeur du stock n'apparaissent que si l'abonnement de la démo inclut le module achats.

create or replace function public.pf_reinitialiser_demo(p_entreprise uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  e entreprises; site uuid; k text; maint text := public.pf_j(0, to_char(now() at time zone 'Africa/Casablanca', 'HH24:MI'));
  l_site text; l_at text; l_li text; l_ut text; presse text; emb text; conv text; comp text;
  resp text; ta text; tb text; mag text; a1 text; a2 text; a3 text; a4 text; b3 text; b4 text; da1 text; d1 text; d3 text; o1 text; o3 text; m1 text;
begin
  perform public.exiger_admin();
  select * into e from entreprises where id = p_entreprise;
  if not found or not e.demo then raise exception 'Seule une entreprise de démonstration peut être réinitialisée'; end if;
  select id into site from sites where entreprise_id = e.id and actif order by cree_le limit 1;
  if site is null then raise exception 'La démo n''a aucun site actif'; end if;

  delete from fiches where entreprise_id = e.id;   -- démo uniquement : rien d'autre n'est jamais supprimé
  k := substr(md5(e.id::text || clock_timestamp()::text), 1, 8);
  l_site := k || '-loc0'; l_at := k || '-loc1'; l_li := k || '-loc2'; l_ut := k || '-loc3';
  presse := k || '-eq1'; emb := k || '-eq2'; conv := k || '-eq3'; comp := k || '-eq4';
  resp := k || '-p1'; ta := k || '-p2'; tb := k || '-p3'; mag := k || '-p4';
  a1 := k || '-a1'; a2 := k || '-a2'; a3 := k || '-a3'; d1 := k || '-d1'; d3 := k || '-d3'; o1 := k || '-o1'; m1 := k || '-m1';
  a4 := k || '-a4'; b3 := k || '-b3'; b4 := k || '-b4'; o3 := k || '-o3'; da1 := k || '-da1';

  insert into fiches (id, type, entreprise_id, site_id, data)
  select v.id, v.type, e.id, case when v.type in ('personnes','articles') then null else site end,
         v.data || jsonb_build_object('id', v.id, 'creeLe', coalesce(v.data->>'creeLe', maint), 'creePar', coalesce(v.data->>'creePar', 'Démo'), 'modifieLe', maint, 'modifiePar', 'Démo')
                || case when v.type in ('personnes','articles') then '{}'::jsonb else jsonb_build_object('siteId', site) end
  from (values
    (l_site, 'localisations', jsonb_build_object('code', 'SITE', 'nom', 'Usine', 'parentId', null)),
    (l_at, 'localisations', jsonb_build_object('code', 'AT-PR', 'nom', 'Atelier presses', 'parentId', l_site)),
    (l_li, 'localisations', jsonb_build_object('code', 'LG-CD', 'nom', 'Ligne conditionnement', 'parentId', l_site)),
    (l_ut, 'localisations', jsonb_build_object('code', 'UT', 'nom', 'Utilités', 'parentId', l_site)),
    (presse, 'equipements', jsonb_build_object('code', 'PRESSE-01', 'designation', 'Presse hydraulique 200 t', 'localisationId', l_at, 'famille', 'presse', 'criticite', '4', 'actif', true)),
    (emb, 'equipements', jsonb_build_object('code', 'EMB-02', 'designation', 'Emballeuse ligne 2', 'localisationId', l_li, 'famille', 'emballage', 'criticite', '3', 'actif', true)),
    (conv, 'equipements', jsonb_build_object('code', 'CONV-03', 'designation', 'Convoyeur sortie ligne 2', 'localisationId', l_li, 'famille', 'convoyage', 'criticite', '2', 'actif', true)),
    (comp, 'equipements', jsonb_build_object('code', 'COMP-01', 'designation', 'Compresseur d’air 55 kW', 'localisationId', l_ut, 'famille', 'utilité', 'criticite', '4', 'actif', true)),
    (resp, 'personnes', jsonb_build_object('nom', 'Responsable maintenance', 'role', 'responsable', 'actif', true)),
    (ta, 'personnes', jsonb_build_object('nom', 'Technicien A (mécanique)', 'role', 'technicien', 'actif', true)),
    (tb, 'personnes', jsonb_build_object('nom', 'Technicien B (automatisme)', 'role', 'technicien', 'actif', true)),
    (mag, 'personnes', jsonb_build_object('nom', 'Magasinier', 'role', 'magasinier', 'actif', true)),
    (a1, 'articles', jsonb_build_object('ref', 'J-VER-80', 'designation', 'Joint de vérin Ø80', 'unite', 'u', 'stockMin', 2, 'actif', true)),
    (a2, 'articles', jsonb_build_object('ref', 'HUI-HV46', 'designation', 'Huile hydraulique HV46', 'unite', 'L', 'stockMin', 20, 'actif', true)),
    (a3, 'articles', jsonb_build_object('ref', 'FIL-AIR', 'designation', 'Filtre à air compresseur', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (a4, 'articles', jsonb_build_object('ref', 'ROUL-TD-50', 'designation', 'Rouleau tendeur convoyeur Ø50', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (k || '-m0d', 'mouvements', jsonb_build_object('articleId', a4, 'type', 'entree', 'qte', 2, 'otId', null, 'le', public.pf_j(0, '09:15'), 'motif', 'Livraison fournisseur')),
    -- volet B : le convoyeur attend un rouleau (demande urgente, en stock) ; 2 L d'huile pris en urgence, à vérifier
    (b3, 'besoins', jsonb_build_object('ref', 'BES-DEMO-0001', 'otId', o3, 'equipementId', conv, 'articleId', a4, 'qte', 1, 'unite', 'u', 'urgent', true, 'statut', 'demande', 'note', 'Arrêt ligne 2', 'demandeur', 'Technicien B (automatisme)', 'demandeLe', public.pf_j(0, '08:30'), 'creeLe', public.pf_j(0, '08:30'))),
    (b4, 'besoins', jsonb_build_object('ref', 'BES-DEMO-0002', 'otId', o3, 'equipementId', conv, 'articleId', a2, 'qte', 2, 'unite', 'L', 'urgent', true, 'statut', 'demande', 'note', 'Retrait urgent', 'demandeur', 'Technicien B (automatisme)', 'demandeLe', public.pf_j(0, '08:10'), 'creeLe', public.pf_j(0, '08:10'))),
    (k || '-m4', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'remise', 'qte', -2, 'urgent', true, 'aVerifier', true, 'besoinId', b4, 'otId', o3, 'le', public.pf_j(0, '08:10'), 'motif', 'Retrait urgent OT-DEMO-0003', 'creePar', 'Technicien B (automatisme)')),
    -- volet C : prix des entrées (valorisation, lecture restreinte), seuils, commande en cours
    (k || '-v0a', 'valorisations', jsonb_build_object('mouvementId', k || '-m0a', 'prixUnitaire', 85, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0b', 'valorisations', jsonb_build_object('mouvementId', k || '-m0b', 'prixUnitaire', 42, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0c', 'valorisations', jsonb_build_object('mouvementId', k || '-m0c', 'prixUnitaire', 310, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0d', 'valorisations', jsonb_build_object('mouvementId', k || '-m0d', 'prixUnitaire', 260, 'devise', 'MAD', 'statut', 'provisoire')),
    (k || '-s1', 'seuils', jsonb_build_object('articleId', a1, 'securite', 1, 'pointCommande', 4, 'cible', 8, 'delaiJours', 21, 'critique', true, 'statut', 'valide',
        'justification', 'Presse critique, délai fournisseur 3 semaines', 'proposePar', 'Magasinier', 'proposeLe', public.pf_j(-10, '10:00'), 'valideLe', public.pf_j(-9, '09:00'), 'validePar', 'Responsable maintenance')),
    (k || '-s2', 'seuils', jsonb_build_object('articleId', a3, 'securite', 1, 'pointCommande', 2, 'cible', 4, 'delaiJours', 10, 'critique', false, 'statut', 'propose',
        'justification', 'Compresseur sans secours : garder un filtre d’avance', 'proposePar', 'Magasinier', 'proposeLe', public.pf_j(-1, '16:00'))),
    (da1, 'achats', jsonb_build_object('ref', 'DA-DEMO-0001', 'statut', 'commandee', 'origine', 'reapprovisionnement', 'redigePar', 'Magasinier', 'redigeLe', public.pf_j(-6, '10:00'),
        'soumiseLe', public.pf_j(-6, '10:05'), 'soumisePar', 'Magasinier', 'valideLe', public.pf_j(-5, '08:30'), 'validePar', 'Responsable maintenance',
        'fournisseur', 'Atlas Compresseurs', 'refCommande', 'BC-DEMO-0042', 'dateCommande', public.pf_j(-4), 'livraisonPrevue', public.pf_j(1), 'devise', 'MAD',
        'commandeLe', public.pf_j(-4, '11:00'), 'commandePar', 'Responsable maintenance',
        'lignes', jsonb_build_array(jsonb_build_object('id', k || '-dl1', 'articleId', a3, 'qte', 3, 'qteCommandee', 3, 'unite', 'u', 'prixUnitaire', 310, 'devise', 'MAD', 'motif', 'Stock sous le seuil')))),
    (k || '-m0a', 'mouvements', jsonb_build_object('articleId', a1, 'type', 'entree', 'qte', 3, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0b', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'entree', 'qte', 60, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0c', 'mouvements', jsonb_build_object('articleId', a3, 'type', 'entree', 'qte', 1, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (m1, 'mouvements', jsonb_build_object('articleId', a1, 'type', 'sortie', 'qte', -1, 'otId', o1, 'le', public.pf_j(-3, '09:00'), 'motif', null)),
    (d1, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0001', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Opérateur presse', 'service', 'Production'), 'equipementId', presse, 'besoin', 'corriger', 'constat', 'Le vérin ne tient plus la position', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(-3, '08:00'), 'precisionHeure', 'exacte', 'statut', 'traitement_organise', 'priseEnChargePar', ta, 'priseEnChargeLe', public.pf_j(-3, '08:05'), 'creeLe', public.pf_j(-3, '08:03'))),
    (k || '-d2', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0002', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Chef de ligne', 'service', 'Conditionnement'), 'equipementId', emb, 'besoin', 'verifier', 'constat', 'Bruit anormal au niveau du convoyeur d’entrée', 'etat', 'degrade', 'impact', 'aucun_constate', 'heureFait', public.pf_j(-1, '14:20'), 'precisionHeure', 'estimee', 'statut', 'a_examiner', 'creeLe', public.pf_j(-1, '14:35'))),
    (d3, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0003', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie, frottement côté moteur', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(0, '07:40'), 'precisionHeure', 'estimee', 'statut', 'traitement_organise', 'priseEnChargePar', tb, 'priseEnChargeLe', public.pf_j(0, '07:50'), 'creeLe', public.pf_j(0, '07:45'))),
    (k || '-d4', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0004', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie', 'etat', 'degrade', 'impact', 'reduit', 'precisionHeure', 'inconnue', 'statut', 'close_sans_travail', 'motifClassement', 'Recentrage par l’opérateur', 'creeLe', public.pf_j(-12, '10:00'))),
    (o1, 'ots', jsonb_build_object('ref', 'OT-DEMO-0001', 'demandeIds', jsonb_build_array(d1), 'equipementId', presse, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'cloturee',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i1', 'personneId', ta, 'role', 'intervenant', 'depuis', public.pf_j(-3, '08:10'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic', 'remplacement'), 'travaux', 'Remplacement du joint de vérin, purge du circuit.', 'resultat', 'resolu', 'cause', 'Joint de vérin usé', 'certitudeCause', 'probable', 'familleDefaut', 'hydraulique',
        'avecArret', 'oui', 'arretDebut', public.pf_j(-3, '08:00'), 'arretFin', public.pf_j(-3, '10:30'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc1', 'articleId', a1, 'qte', 1, 'mouvementId', m1, 'annulee', false)), 'reserves', '[]'::jsonb, 'attentes', '[]'::jsonb,
        'clotureLe', public.pf_j(-3, '11:20'), 'cloturePar', 'Responsable maintenance', 'creeLe', public.pf_j(-3, '08:05'))),
    (o3, 'ots', jsonb_build_object('ref', 'OT-DEMO-0003', 'demandeIds', jsonb_build_array(d3), 'equipementId', conv, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'suspendue',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i3', 'personneId', tb, 'role', 'intervenant', 'depuis', public.pf_j(0, '07:50'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic'), 'travaux', 'Rouleau tendeur grippé.', 'familleDefaut', 'mecanique', 'avecArret', 'oui', 'arretDebut', public.pf_j(0, '07:40'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc3', 'besoinId', b4, 'articleId', a2, 'qte', 2, 'mouvementId', null, 'annulee', false)), 'reserves', '[]'::jsonb,
        'attentes', jsonb_build_array(jsonb_build_object('id', k || '-at3', 'motif', 'piece', 'besoinId', b3, 'detail', 'Rouleau tendeur convoyeur Ø50', 'depuis', public.pf_j(0, '08:30'), 'fin', null, 'responsableId', mag)),
        'creeLe', public.pf_j(0, '07:50'))),
    (k || '-pg1', 'programmes', jsonb_build_object('equipementId', comp, 'libelle', 'Vidange et filtre compresseur', 'modele', 'entretien', 'periodiciteJours', 90, 'prochaineEcheance', public.pf_j(-2), 'regle', 'fixe', 'instruction', 'Consigner selon procédure site, vidanger, remplacer le filtre à air, essai à vide puis en charge.', 'actif', true)),
    (k || '-pg2', 'programmes', jsonb_build_object('equipementId', presse, 'libelle', 'Contrôle niveau et fuites hydrauliques', 'modele', 'inspection', 'periodiciteJours', 30, 'prochaineEcheance', public.pf_j(5), 'regle', 'apres_realisation', 'instruction', 'Niveau bâche, état flexibles, traces de fuite.', 'actif', true))
  ) as v(id, type, data);

  update entreprises set reinit_le = now() where id = e.id;
  return jsonb_build_object('fiches', (select count(*) from fiches where entreprise_id = e.id), 'reinitLe', now());
end $$;
revoke all on function public.pf_reinitialiser_demo(uuid) from public, anon;
grant execute on function public.pf_reinitialiser_demo(uuid) to authenticated;

-- ===== 21_demo_energie.sql — copie générée de supabase/demo_energie.sql (empreinte 7d45dd219704c0d0) : ne pas modifier ici =====
-- GMAO terrain — démo : énergie et eau (volet D, étape D5). APRÈS fichiers.sql (et demo.sql).
-- FICHIER GÉNÉRÉ par scripts/generer_demo_energie.py depuis Calculs.demoEnergie (js/calculs.js) : ne pas modifier à la main.
-- Scénario : arrivée générale + 3 sous-compteurs (résidu ≈ 7 % « à expliquer »), compteur de la ligne remplacé il y a
-- 30 jours, eau avec une lecture erronée (à examiner), heures du compresseur (vidange 2 000 h en alerte), factures ONEE
-- concordante puis en écart (+6 %), facture d'eau. Les écrans n'apparaissent que si l'abonnement inclut le module energie.

create or replace function public.pf_demo_energie(p_ent uuid, p_site uuid, k text, comp text)
returns integer language plpgsql security definer set search_path = public as $$
declare
  maint text := public.pf_j(0, to_char(now() at time zone 'Africa/Casablanca', 'HH24:MI'));
  n integer;
begin
  insert into fiches (id, type, entreprise_id, site_id, data)
  select v.id, v.type, p_ent, p_site,
         v.data || jsonb_build_object('id', v.id, 'siteId', p_site, 'creeLe', coalesce(v.data->>'creeLe', maint), 'creePar', coalesce(v.data->>'creePar', 'Démo'), 'modifieLe', maint, 'modifiePar', 'Démo')
  from (values
    (k || '-ncg', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'ELEC-GEN', 'libelle', 'Électricité — arrivée générale', 'usage', 'ressource', 'ressource', 'electricite', 'unite', 'kWh')),
    (k || '-ncc', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'ELEC-COMP', 'libelle', 'Électricité — compresseur', 'usage', 'ressource', 'ressource', 'electricite', 'unite', 'kWh', 'parentId', k || '-ncg', 'equipementId', comp)),
    (k || '-nca', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'ELEC-AT', 'libelle', 'Électricité — atelier presses', 'usage', 'ressource', 'ressource', 'electricite', 'unite', 'kWh', 'parentId', k || '-ncg')),
    (k || '-ncl', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'ELEC-LG', 'libelle', 'Électricité — ligne conditionnement', 'usage', 'ressource', 'ressource', 'electricite', 'unite', 'kWh', 'parentId', k || '-ncg')),
    (k || '-nce', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'EAU-GEN', 'libelle', 'Eau de ville', 'usage', 'ressource', 'ressource', 'eau', 'unite', 'm³')),
    (k || '-nch', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 1, 'mode', 'cumulatif', 'actif', true, 'code', 'HRS-COMP01', 'libelle', 'Heures de marche compresseur', 'usage', 'equipement', 'unite', 'h', 'equipementId', comp)),
    (k || '-nr1', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-64, '08:00'), 'creeLe', public.pf_j(-64, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 120000, 'unite', 'kWh')),
    (k || '-nr2', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-57, '08:00'), 'creeLe', public.pf_j(-57, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 126100, 'unite', 'kWh')),
    (k || '-nr3', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-50, '08:00'), 'creeLe', public.pf_j(-50, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 132000, 'unite', 'kWh')),
    (k || '-nr4', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-43, '08:00'), 'creeLe', public.pf_j(-43, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 138300, 'unite', 'kWh')),
    (k || '-nr5', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-36, '08:00'), 'creeLe', public.pf_j(-36, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 144350, 'unite', 'kWh')),
    (k || '-nr6', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-29, '08:00'), 'creeLe', public.pf_j(-29, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 150550, 'unite', 'kWh')),
    (k || '-nr7', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-22, '08:00'), 'creeLe', public.pf_j(-22, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 156350, 'unite', 'kWh')),
    (k || '-nr8', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-15, '08:00'), 'creeLe', public.pf_j(-15, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 162750, 'unite', 'kWh')),
    (k || '-nr9', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-8, '08:00'), 'creeLe', public.pf_j(-8, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 168900, 'unite', 'kWh')),
    (k || '-nr10', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-1, '08:00'), 'creeLe', public.pf_j(-1, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 174900, 'unite', 'kWh')),
    (k || '-nr11', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-64, '08:04'), 'creeLe', public.pf_j(-64, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 45000, 'unite', 'kWh')),
    (k || '-nr12', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-57, '08:04'), 'creeLe', public.pf_j(-57, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 47350, 'unite', 'kWh')),
    (k || '-nr13', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-50, '08:04'), 'creeLe', public.pf_j(-50, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 49630, 'unite', 'kWh')),
    (k || '-nr14', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-43, '08:04'), 'creeLe', public.pf_j(-43, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 52050, 'unite', 'kWh')),
    (k || '-nr15', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-36, '08:04'), 'creeLe', public.pf_j(-36, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 54350, 'unite', 'kWh')),
    (k || '-nr16', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-29, '08:04'), 'creeLe', public.pf_j(-29, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 56740, 'unite', 'kWh')),
    (k || '-nr17', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-22, '08:04'), 'creeLe', public.pf_j(-22, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 58990, 'unite', 'kWh')),
    (k || '-nr18', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-15, '08:04'), 'creeLe', public.pf_j(-15, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 61450, 'unite', 'kWh')),
    (k || '-nr19', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-8, '08:04'), 'creeLe', public.pf_j(-8, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 63820, 'unite', 'kWh')),
    (k || '-nr20', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-1, '08:04'), 'creeLe', public.pf_j(-1, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 66130, 'unite', 'kWh')),
    (k || '-nr21', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-64, '08:07'), 'creeLe', public.pf_j(-64, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 80000, 'unite', 'kWh')),
    (k || '-nr22', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-57, '08:07'), 'creeLe', public.pf_j(-57, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 82100, 'unite', 'kWh')),
    (k || '-nr23', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-50, '08:07'), 'creeLe', public.pf_j(-50, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 84150, 'unite', 'kWh')),
    (k || '-nr24', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-43, '08:07'), 'creeLe', public.pf_j(-43, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 86330, 'unite', 'kWh')),
    (k || '-nr25', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-36, '08:07'), 'creeLe', public.pf_j(-36, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 88450, 'unite', 'kWh')),
    (k || '-nr26', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-29, '08:07'), 'creeLe', public.pf_j(-29, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 90600, 'unite', 'kWh')),
    (k || '-nr27', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-22, '08:07'), 'creeLe', public.pf_j(-22, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 92600, 'unite', 'kWh')),
    (k || '-nr28', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-15, '08:07'), 'creeLe', public.pf_j(-15, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 94830, 'unite', 'kWh')),
    (k || '-nr29', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-8, '08:07'), 'creeLe', public.pf_j(-8, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 96970, 'unite', 'kWh')),
    (k || '-nr30', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-1, '08:07'), 'creeLe', public.pf_j(-1, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 99060, 'unite', 'kWh')),
    (k || '-nr31', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-64, '08:10'), 'creeLe', public.pf_j(-64, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 30500, 'unite', 'kWh')),
    (k || '-nr32', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-57, '08:10'), 'creeLe', public.pf_j(-57, '08:10'), 'creePar', 'Technicien A (mécanique)', 'valeur', 31720, 'unite', 'kWh')),
    (k || '-nr33', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-50, '08:10'), 'creeLe', public.pf_j(-50, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 32880, 'unite', 'kWh')),
    (k || '-nr34', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-43, '08:10'), 'creeLe', public.pf_j(-43, '08:10'), 'creePar', 'Technicien A (mécanique)', 'valeur', 34140, 'unite', 'kWh')),
    (k || '-nr35', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-36, '08:10'), 'creeLe', public.pf_j(-36, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 35340, 'unite', 'kWh')),
    (k || '-nr36', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'nature', 'rupture', 'typeRupture', 'remplacement', 'le', public.pf_j(-31, '10:00'), 'creeLe', public.pf_j(-31, '10:00'), 'creePar', 'Responsable maintenance', 'indexFinal', 36240, 'indexInitial', 0, 'motif', 'Compteur défectueux remplacé par l’électricien')),
    (k || '-nr37', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-29, '08:10'), 'creeLe', public.pf_j(-29, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 330, 'unite', 'kWh')),
    (k || '-nr38', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-22, '08:10'), 'creeLe', public.pf_j(-22, '08:10'), 'creePar', 'Technicien A (mécanique)', 'valeur', 1480, 'unite', 'kWh')),
    (k || '-nr39', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-15, '08:10'), 'creeLe', public.pf_j(-15, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 2750, 'unite', 'kWh')),
    (k || '-nr40', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-8, '08:10'), 'creeLe', public.pf_j(-8, '08:10'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3960, 'unite', 'kWh')),
    (k || '-nr41', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-1, '08:10'), 'creeLe', public.pf_j(-1, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 5140, 'unite', 'kWh')),
    (k || '-nr42', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-64, '08:15'), 'creeLe', public.pf_j(-64, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3400, 'unite', 'm³')),
    (k || '-nr43', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-57, '08:15'), 'creeLe', public.pf_j(-57, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 3444, 'unite', 'm³')),
    (k || '-nr44', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-50, '08:15'), 'creeLe', public.pf_j(-50, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3491, 'unite', 'm³')),
    (k || '-nr45', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-43, '08:15'), 'creeLe', public.pf_j(-43, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 3534, 'unite', 'm³')),
    (k || '-nr46', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-36, '08:15'), 'creeLe', public.pf_j(-36, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3580, 'unite', 'm³')),
    (k || '-nr47', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-29, '08:15'), 'creeLe', public.pf_j(-29, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 3625, 'unite', 'm³')),
    (k || '-nr48', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-22, '08:15'), 'creeLe', public.pf_j(-22, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3673, 'unite', 'm³')),
    (k || '-nr49', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-15, '08:15'), 'creeLe', public.pf_j(-15, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 4718, 'unite', 'm³')),
    (k || '-nr50', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-8, '08:15'), 'creeLe', public.pf_j(-8, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3762, 'unite', 'm³')),
    (k || '-nr51', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-1, '08:15'), 'creeLe', public.pf_j(-1, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 3808, 'unite', 'm³')),
    (k || '-nr52', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-64, '08:20'), 'creeLe', public.pf_j(-64, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 11800, 'unite', 'h')),
    (k || '-nr53', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-57, '08:20'), 'creeLe', public.pf_j(-57, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 11912, 'unite', 'h')),
    (k || '-nr54', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-50, '08:20'), 'creeLe', public.pf_j(-50, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 12020, 'unite', 'h')),
    (k || '-nr55', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-43, '08:20'), 'creeLe', public.pf_j(-43, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 12135, 'unite', 'h')),
    (k || '-nr56', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-36, '08:20'), 'creeLe', public.pf_j(-36, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 12245, 'unite', 'h')),
    (k || '-nr57', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-29, '08:20'), 'creeLe', public.pf_j(-29, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 12350, 'unite', 'h')),
    (k || '-nr58', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-22, '08:20'), 'creeLe', public.pf_j(-22, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 12468, 'unite', 'h')),
    (k || '-nr59', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-15, '08:20'), 'creeLe', public.pf_j(-15, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 12579, 'unite', 'h')),
    (k || '-nr60', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-8, '08:20'), 'creeLe', public.pf_j(-8, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 12688, 'unite', 'h')),
    (k || '-nr61', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-1, '08:20'), 'creeLe', public.pf_j(-1, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 12802, 'unite', 'h')),
    (k || '-npg3', 'programmes', jsonb_build_object('equipementId', comp, 'compteurId', k || '-nch', 'libelle', 'Vidange compresseur selon les heures', 'modele', 'entretien', 'intervalleCompteur', 2000, 'margeCompteur', 200, 'dernierIndex', 10850, 'derniereRealisation', public.pf_j(-120, '10:00'), 'regle', 'apres_realisation', 'instruction', 'Vidange, filtre à huile et séparateur, toutes les 2 000 h de marche.', 'actif', true)),
    (k || '-nf1', 'factures_energie', jsonb_build_object('devise', 'MAD', 'creePar', 'Responsable maintenance', 'ressource', 'electricite', 'fournisseur', 'ONEE', 'reference', 'FAC-ONEE-0001', 'du', public.pf_j(-64), 'au', public.pf_j(-36), 'quantite', 24540, 'unite', 'kWh', 'montantHT', 28957.2, 'compteurIds', jsonb_build_array(k || '-ncg'), 'creeLe', public.pf_j(-34, '11:00'))),
    (k || '-nf2', 'factures_energie', jsonb_build_object('devise', 'MAD', 'creePar', 'Responsable maintenance', 'ressource', 'electricite', 'fournisseur', 'ONEE', 'reference', 'FAC-ONEE-0002', 'du', public.pf_j(-36), 'au', public.pf_j(-8), 'quantite', 26100, 'unite', 'kWh', 'montantHT', 30798, 'compteurIds', jsonb_build_array(k || '-ncg'), 'creeLe', public.pf_j(-6, '11:00'))),
    (k || '-nf3', 'factures_energie', jsonb_build_object('devise', 'MAD', 'creePar', 'Responsable maintenance', 'ressource', 'eau', 'fournisseur', 'Régie de distribution', 'reference', 'FAC-EAU-0001', 'du', public.pf_j(-64), 'au', public.pf_j(-8), 'quantite', 362, 'unite', 'm³', 'montantHT', 3439, 'compteurIds', jsonb_build_array(k || '-nce'), 'creeLe', public.pf_j(-6, '11:30')))
  ) as v(id, type, data);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.pf_demo_energie(uuid, uuid, text, text) from public, anon, authenticated;

-- Version de supabase/demo.sql + appel de pf_demo_energie.
create or replace function public.pf_reinitialiser_demo(p_entreprise uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  e entreprises; site uuid; k text; maint text := public.pf_j(0, to_char(now() at time zone 'Africa/Casablanca', 'HH24:MI'));
  l_site text; l_at text; l_li text; l_ut text; presse text; emb text; conv text; comp text;
  resp text; ta text; tb text; mag text; a1 text; a2 text; a3 text; a4 text; b3 text; b4 text; da1 text; d1 text; d3 text; o1 text; o3 text; m1 text;
begin
  perform public.exiger_admin();
  select * into e from entreprises where id = p_entreprise;
  if not found or not e.demo then raise exception 'Seule une entreprise de démonstration peut être réinitialisée'; end if;
  select id into site from sites where entreprise_id = e.id and actif order by cree_le limit 1;
  if site is null then raise exception 'La démo n''a aucun site actif'; end if;

  delete from fiches where entreprise_id = e.id;   -- démo uniquement : rien d'autre n'est jamais supprimé
  k := substr(md5(e.id::text || clock_timestamp()::text), 1, 8);
  l_site := k || '-loc0'; l_at := k || '-loc1'; l_li := k || '-loc2'; l_ut := k || '-loc3';
  presse := k || '-eq1'; emb := k || '-eq2'; conv := k || '-eq3'; comp := k || '-eq4';
  resp := k || '-p1'; ta := k || '-p2'; tb := k || '-p3'; mag := k || '-p4';
  a1 := k || '-a1'; a2 := k || '-a2'; a3 := k || '-a3'; d1 := k || '-d1'; d3 := k || '-d3'; o1 := k || '-o1'; m1 := k || '-m1';
  a4 := k || '-a4'; b3 := k || '-b3'; b4 := k || '-b4'; o3 := k || '-o3'; da1 := k || '-da1';

  insert into fiches (id, type, entreprise_id, site_id, data)
  select v.id, v.type, e.id, case when v.type in ('personnes','articles') then null else site end,
         v.data || jsonb_build_object('id', v.id, 'creeLe', coalesce(v.data->>'creeLe', maint), 'creePar', coalesce(v.data->>'creePar', 'Démo'), 'modifieLe', maint, 'modifiePar', 'Démo')
                || case when v.type in ('personnes','articles') then '{}'::jsonb else jsonb_build_object('siteId', site) end
  from (values
    (l_site, 'localisations', jsonb_build_object('code', 'SITE', 'nom', 'Usine', 'parentId', null)),
    (l_at, 'localisations', jsonb_build_object('code', 'AT-PR', 'nom', 'Atelier presses', 'parentId', l_site)),
    (l_li, 'localisations', jsonb_build_object('code', 'LG-CD', 'nom', 'Ligne conditionnement', 'parentId', l_site)),
    (l_ut, 'localisations', jsonb_build_object('code', 'UT', 'nom', 'Utilités', 'parentId', l_site)),
    (presse, 'equipements', jsonb_build_object('code', 'PRESSE-01', 'designation', 'Presse hydraulique 200 t', 'localisationId', l_at, 'famille', 'presse', 'criticite', '4', 'actif', true)),
    (emb, 'equipements', jsonb_build_object('code', 'EMB-02', 'designation', 'Emballeuse ligne 2', 'localisationId', l_li, 'famille', 'emballage', 'criticite', '3', 'actif', true)),
    (conv, 'equipements', jsonb_build_object('code', 'CONV-03', 'designation', 'Convoyeur sortie ligne 2', 'localisationId', l_li, 'famille', 'convoyage', 'criticite', '2', 'actif', true)),
    (comp, 'equipements', jsonb_build_object('code', 'COMP-01', 'designation', 'Compresseur d’air 55 kW', 'localisationId', l_ut, 'famille', 'utilité', 'criticite', '4', 'actif', true)),
    (resp, 'personnes', jsonb_build_object('nom', 'Responsable maintenance', 'role', 'responsable', 'actif', true)),
    (ta, 'personnes', jsonb_build_object('nom', 'Technicien A (mécanique)', 'role', 'technicien', 'actif', true)),
    (tb, 'personnes', jsonb_build_object('nom', 'Technicien B (automatisme)', 'role', 'technicien', 'actif', true)),
    (mag, 'personnes', jsonb_build_object('nom', 'Magasinier', 'role', 'magasinier', 'actif', true)),
    (a1, 'articles', jsonb_build_object('ref', 'J-VER-80', 'designation', 'Joint de vérin Ø80', 'unite', 'u', 'stockMin', 2, 'actif', true)),
    (a2, 'articles', jsonb_build_object('ref', 'HUI-HV46', 'designation', 'Huile hydraulique HV46', 'unite', 'L', 'stockMin', 20, 'actif', true)),
    (a3, 'articles', jsonb_build_object('ref', 'FIL-AIR', 'designation', 'Filtre à air compresseur', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (a4, 'articles', jsonb_build_object('ref', 'ROUL-TD-50', 'designation', 'Rouleau tendeur convoyeur Ø50', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (k || '-m0d', 'mouvements', jsonb_build_object('articleId', a4, 'type', 'entree', 'qte', 2, 'otId', null, 'le', public.pf_j(0, '09:15'), 'motif', 'Livraison fournisseur')),
    -- volet B : le convoyeur attend un rouleau (demande urgente, en stock) ; 2 L d'huile pris en urgence, à vérifier
    (b3, 'besoins', jsonb_build_object('ref', 'BES-DEMO-0001', 'otId', o3, 'equipementId', conv, 'articleId', a4, 'qte', 1, 'unite', 'u', 'urgent', true, 'statut', 'demande', 'note', 'Arrêt ligne 2', 'demandeur', 'Technicien B (automatisme)', 'demandeLe', public.pf_j(0, '08:30'), 'creeLe', public.pf_j(0, '08:30'))),
    (b4, 'besoins', jsonb_build_object('ref', 'BES-DEMO-0002', 'otId', o3, 'equipementId', conv, 'articleId', a2, 'qte', 2, 'unite', 'L', 'urgent', true, 'statut', 'demande', 'note', 'Retrait urgent', 'demandeur', 'Technicien B (automatisme)', 'demandeLe', public.pf_j(0, '08:10'), 'creeLe', public.pf_j(0, '08:10'))),
    (k || '-m4', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'remise', 'qte', -2, 'urgent', true, 'aVerifier', true, 'besoinId', b4, 'otId', o3, 'le', public.pf_j(0, '08:10'), 'motif', 'Retrait urgent OT-DEMO-0003', 'creePar', 'Technicien B (automatisme)')),
    -- volet C : prix des entrées (valorisation, lecture restreinte), seuils, commande en cours
    (k || '-v0a', 'valorisations', jsonb_build_object('mouvementId', k || '-m0a', 'prixUnitaire', 85, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0b', 'valorisations', jsonb_build_object('mouvementId', k || '-m0b', 'prixUnitaire', 42, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0c', 'valorisations', jsonb_build_object('mouvementId', k || '-m0c', 'prixUnitaire', 310, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0d', 'valorisations', jsonb_build_object('mouvementId', k || '-m0d', 'prixUnitaire', 260, 'devise', 'MAD', 'statut', 'provisoire')),
    (k || '-s1', 'seuils', jsonb_build_object('articleId', a1, 'securite', 1, 'pointCommande', 4, 'cible', 8, 'delaiJours', 21, 'critique', true, 'statut', 'valide',
        'justification', 'Presse critique, délai fournisseur 3 semaines', 'proposePar', 'Magasinier', 'proposeLe', public.pf_j(-10, '10:00'), 'valideLe', public.pf_j(-9, '09:00'), 'validePar', 'Responsable maintenance')),
    (k || '-s2', 'seuils', jsonb_build_object('articleId', a3, 'securite', 1, 'pointCommande', 2, 'cible', 4, 'delaiJours', 10, 'critique', false, 'statut', 'propose',
        'justification', 'Compresseur sans secours : garder un filtre d’avance', 'proposePar', 'Magasinier', 'proposeLe', public.pf_j(-1, '16:00'))),
    (da1, 'achats', jsonb_build_object('ref', 'DA-DEMO-0001', 'statut', 'commandee', 'origine', 'reapprovisionnement', 'redigePar', 'Magasinier', 'redigeLe', public.pf_j(-6, '10:00'),
        'soumiseLe', public.pf_j(-6, '10:05'), 'soumisePar', 'Magasinier', 'valideLe', public.pf_j(-5, '08:30'), 'validePar', 'Responsable maintenance',
        'fournisseur', 'Atlas Compresseurs', 'refCommande', 'BC-DEMO-0042', 'dateCommande', public.pf_j(-4), 'livraisonPrevue', public.pf_j(1), 'devise', 'MAD',
        'commandeLe', public.pf_j(-4, '11:00'), 'commandePar', 'Responsable maintenance',
        'lignes', jsonb_build_array(jsonb_build_object('id', k || '-dl1', 'articleId', a3, 'qte', 3, 'qteCommandee', 3, 'unite', 'u', 'prixUnitaire', 310, 'devise', 'MAD', 'motif', 'Stock sous le seuil')))),
    (k || '-m0a', 'mouvements', jsonb_build_object('articleId', a1, 'type', 'entree', 'qte', 3, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0b', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'entree', 'qte', 60, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0c', 'mouvements', jsonb_build_object('articleId', a3, 'type', 'entree', 'qte', 1, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (m1, 'mouvements', jsonb_build_object('articleId', a1, 'type', 'sortie', 'qte', -1, 'otId', o1, 'le', public.pf_j(-3, '09:00'), 'motif', null)),
    (d1, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0001', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Opérateur presse', 'service', 'Production'), 'equipementId', presse, 'besoin', 'corriger', 'constat', 'Le vérin ne tient plus la position', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(-3, '08:00'), 'precisionHeure', 'exacte', 'statut', 'traitement_organise', 'priseEnChargePar', ta, 'priseEnChargeLe', public.pf_j(-3, '08:05'), 'creeLe', public.pf_j(-3, '08:03'))),
    (k || '-d2', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0002', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Chef de ligne', 'service', 'Conditionnement'), 'equipementId', emb, 'besoin', 'verifier', 'constat', 'Bruit anormal au niveau du convoyeur d’entrée', 'etat', 'degrade', 'impact', 'aucun_constate', 'heureFait', public.pf_j(-1, '14:20'), 'precisionHeure', 'estimee', 'statut', 'a_examiner', 'creeLe', public.pf_j(-1, '14:35'))),
    (d3, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0003', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie, frottement côté moteur', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(0, '07:40'), 'precisionHeure', 'estimee', 'statut', 'traitement_organise', 'priseEnChargePar', tb, 'priseEnChargeLe', public.pf_j(0, '07:50'), 'creeLe', public.pf_j(0, '07:45'))),
    (k || '-d4', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0004', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie', 'etat', 'degrade', 'impact', 'reduit', 'precisionHeure', 'inconnue', 'statut', 'close_sans_travail', 'motifClassement', 'Recentrage par l’opérateur', 'creeLe', public.pf_j(-12, '10:00'))),
    (o1, 'ots', jsonb_build_object('ref', 'OT-DEMO-0001', 'demandeIds', jsonb_build_array(d1), 'equipementId', presse, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'cloturee',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i1', 'personneId', ta, 'role', 'intervenant', 'depuis', public.pf_j(-3, '08:10'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic', 'remplacement'), 'travaux', 'Remplacement du joint de vérin, purge du circuit.', 'resultat', 'resolu', 'cause', 'Joint de vérin usé', 'certitudeCause', 'probable', 'familleDefaut', 'hydraulique',
        'avecArret', 'oui', 'arretDebut', public.pf_j(-3, '08:00'), 'arretFin', public.pf_j(-3, '10:30'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc1', 'articleId', a1, 'qte', 1, 'mouvementId', m1, 'annulee', false)), 'reserves', '[]'::jsonb, 'attentes', '[]'::jsonb,
        'clotureLe', public.pf_j(-3, '11:20'), 'cloturePar', 'Responsable maintenance', 'creeLe', public.pf_j(-3, '08:05'))),
    (o3, 'ots', jsonb_build_object('ref', 'OT-DEMO-0003', 'demandeIds', jsonb_build_array(d3), 'equipementId', conv, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'suspendue',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i3', 'personneId', tb, 'role', 'intervenant', 'depuis', public.pf_j(0, '07:50'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic'), 'travaux', 'Rouleau tendeur grippé.', 'familleDefaut', 'mecanique', 'avecArret', 'oui', 'arretDebut', public.pf_j(0, '07:40'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc3', 'besoinId', b4, 'articleId', a2, 'qte', 2, 'mouvementId', null, 'annulee', false)), 'reserves', '[]'::jsonb,
        'attentes', jsonb_build_array(jsonb_build_object('id', k || '-at3', 'motif', 'piece', 'besoinId', b3, 'detail', 'Rouleau tendeur convoyeur Ø50', 'depuis', public.pf_j(0, '08:30'), 'fin', null, 'responsableId', mag)),
        'creeLe', public.pf_j(0, '07:50'))),
    (k || '-pg1', 'programmes', jsonb_build_object('equipementId', comp, 'libelle', 'Vidange et filtre compresseur', 'modele', 'entretien', 'periodiciteJours', 90, 'prochaineEcheance', public.pf_j(-2), 'regle', 'fixe', 'instruction', 'Consigner selon procédure site, vidanger, remplacer le filtre à air, essai à vide puis en charge.', 'actif', true)),
    (k || '-pg2', 'programmes', jsonb_build_object('equipementId', presse, 'libelle', 'Contrôle niveau et fuites hydrauliques', 'modele', 'inspection', 'periodiciteJours', 30, 'prochaineEcheance', public.pf_j(5), 'regle', 'apres_realisation', 'instruction', 'Niveau bâche, état flexibles, traces de fuite.', 'actif', true))
  ) as v(id, type, data);

  perform public.pf_demo_energie(e.id, site, k, comp);   -- volet D : énergie et eau
  update entreprises set reinit_le = now() where id = e.id;
  return jsonb_build_object('fiches', (select count(*) from fiches where entreprise_id = e.id), 'reinitLe', now());
end $$;
revoke all on function public.pf_reinitialiser_demo(uuid) from public, anon;
grant execute on function public.pf_reinitialiser_demo(uuid) to authenticated;

-- ===== 99_controles.sql =====
-- 99 — contrôles de fin de construction (base neuve). Rejouable.
-- 1) multitenant.sql a créé « Perfora Démo » pour migrer d'anciennes données : sur une base neuve elle est vide,
--    on la retire (les démos commerciales se créent depuis la console, entreprise « démo »).
do $$
declare ent uuid;
begin
  select id into ent from public.entreprises where code = 'DEMO' and not demo;
  if ent is not null and not exists (select 1 from public.fiches where entreprise_id = ent)
     and not exists (select 1 from public.profils where entreprise_id = ent) then
    delete from public.abonnements where entreprise_id = ent;
    delete from public.sites where entreprise_id = ent;
    delete from public.entreprises where id = ent;
  end if;
end $$;

-- 2) Résultat attendu : une seule ligne, tout à 0 / vrai.
select json_build_object(
  'fonctions_ouvertes_sans_compte', (select coalesce(json_agg(p.proname), '[]') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')),
  'tables_sans_rls', (select coalesce(json_agg(c.relname), '[]') from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  'packs', (select count(*) from public.packs),
  'espace_fichiers', (select count(*) from storage.buckets where id = 'fichiers'),
  'entreprises', (select count(*) from public.entreprises),
  'fiches', (select count(*) from public.fiches)
)::text as controle_construction;
