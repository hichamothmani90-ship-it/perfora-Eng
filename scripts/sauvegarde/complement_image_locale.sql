-- Compléments pour l'image Docker supabase/postgres (tests locaux seulement, jamais sur Supabase) :
-- l'image ne crée que le schéma « storage » vide (les tables viennent du service de fichiers) et une version ancienne
-- de auth.uid(). On reproduit ce que Supabase fournit réellement. À exécuter avec le compte supabase_admin.
create table if not exists storage.buckets (id text primary key, name text not null unique, owner uuid, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text, owner uuid, metadata jsonb, created_at timestamptz default now(), updated_at timestamptz default now(), last_accessed_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated, anon;
grant select, insert on storage.objects to authenticated;
alter table storage.buckets owner to postgres;
alter table storage.objects owner to postgres;
-- auth.uid() / auth.jwt() comme sur Supabase aujourd'hui (lisent request.jwt.claims).
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''), nullif(current_setting('request.jwt.claims', true), ''))::jsonb
$$;
