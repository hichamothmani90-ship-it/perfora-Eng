#!/usr/bin/env bash
# Construit une base neuve (Docker, image Supabase Postgres) avec supabase/production/construire_base.sql et affiche
# l'empreinte de son schéma (scripts/sauvegarde/empreinte_schema.sql), à comparer avec celle du projet Supabase :
#   bash scripts/sauvegarde/comparer_schema.sh > locale.json
#   python3 scripts/sauvegarde/comparer_empreintes.py projet.json locale.json
set -euo pipefail
IMAGE="${IMAGE:-supabase/postgres:17.11.0.018}"
RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
docker rm -f pf-schema >/dev/null 2>&1 || true
trap 'docker rm -f pf-schema >/dev/null 2>&1 || true' EXIT
docker run -d --name pf-schema -e POSTGRES_PASSWORD=test-local "$IMAGE" >/dev/null
for _ in $(seq 1 60); do docker exec pf-schema pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done; sleep 3
docker exec -i pf-schema psql -U supabase_admin -d postgres -X -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
create table if not exists storage.buckets (id text primary key, name text not null unique, owner uuid, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text, owner uuid, metadata jsonb, created_at timestamptz default now(), updated_at timestamptz default now(), last_accessed_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated, anon;
alter table storage.buckets owner to postgres; alter table storage.objects owner to postgres;
SQL
docker exec -i -e PGPASSWORD=test-local pf-schema psql -U postgres -h localhost -X -q -v ON_ERROR_STOP=1 >/dev/null 2>&1 < "$RACINE/supabase/production/construire_base.sql"
docker exec -i -e PGPASSWORD=test-local pf-schema psql -U postgres -h localhost -X -q -t -A < "$RACINE/scripts/sauvegarde/empreinte_schema.sql" | sed 's/^##//'
