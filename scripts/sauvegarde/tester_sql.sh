#!/usr/bin/env bash
# Rejoue les tests SQL (supabase/tests_*.sql) sur une base neuve locale construite par construire_base.sql.
# Usage (WSL, moteur Docker lancé) : bash scripts/sauvegarde/tester_sql.sh [tests_securite tests_demo …]
# Un administrateur fictif (MFA obligatoire) est créé : les tests agissent en session « aal2 ».
set -euo pipefail
IMAGE="${IMAGE:-supabase/postgres:17.11.0.018}"
RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
C=pf-tests
docker rm -f $C >/dev/null 2>&1 || true
trap 'docker rm -f $C >/dev/null 2>&1 || true' EXIT
docker run -d --name $C -e POSTGRES_PASSWORD=test-local "$IMAGE" >/dev/null
for _ in $(seq 1 60); do docker exec $C pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done; sleep 3
docker exec -i $C psql -U supabase_admin -d postgres -X -q -v ON_ERROR_STOP=1 >/dev/null < "$RACINE/scripts/sauvegarde/complement_image_locale.sql"
P=(docker exec -i -e PGPASSWORD=test-local $C psql -U postgres -h localhost -X -q -t -A)
"${P[@]}" -v ON_ERROR_STOP=1 < "$RACINE/supabase/production/construire_base.sql" > /tmp/construction.log 2>&1 || { grep -a ERROR -A3 /tmp/construction.log; exit 1; }
"${P[@]}" -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
insert into auth.users (id, instance_id, aud, role, email, created_at) values
  ('00000000-0000-4000-8000-0000000000ad', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@local.test', now());
insert into admins_plateforme (user_id) values ('00000000-0000-4000-8000-0000000000ad');
SQL
LISTE=("$@"); [ ${#LISTE[@]} -eq 0 ] && LISTE=($(cd "$RACINE/supabase" && ls tests_*.sql | sed 's/\.sql$//'))
for t in "${LISTE[@]}"; do
  echo "== $t"
  "${P[@]}" < "$RACINE/supabase/$t.sql" 2>&1 | grep -av '^NOTICE' | tail -3
done
