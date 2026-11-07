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
