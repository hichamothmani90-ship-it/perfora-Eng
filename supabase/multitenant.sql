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
