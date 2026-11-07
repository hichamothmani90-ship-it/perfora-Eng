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
