#!/usr/bin/env bash
# Lot S2 (risque E) : un téléphone peut-il manquer des fiches écrites par une longue transaction (import) ?
# A : import de 300 fiches, transaction ouverte 6 s ; B : un envoi ordinaire validé pendant ce temps ;
# C : un téléphone lit pendant l'import (curseur = plus grand seq vu), puis relit après (recouvrement de 200).
# Variante « avec correctif » : l'import renumérote ses fiches juste avant de valider (comme pf_importer depuis S2).
# Usage (WSL, moteur Docker lancé) : bash scripts/sauvegarde/tester_curseur.sh
set -euo pipefail
IMAGE="${IMAGE:-supabase/postgres:17.11.0.018}"
C=pf-curseur
docker rm -f $C >/dev/null 2>&1 || true
trap 'docker rm -f $C >/dev/null 2>&1 || true' EXIT
docker run -d --name $C -e POSTGRES_PASSWORD=test-local "$IMAGE" >/dev/null
for _ in $(seq 1 60); do docker exec $C pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done; sleep 3
P() { docker exec -i -e PGPASSWORD=test-local $C psql -U postgres -h localhost -X -q -t -A "$@"; }

essai() {   # $1 = sans | avec
  P <<'SQL'
drop table if exists f; drop sequence if exists s;
create sequence s; create table f (id text primary key, seq bigint not null default nextval('s'), origine text);
insert into f (id, origine) select 'ancien' || g, 'avant' from generate_series(1, 1000) g;
SQL
  local renum=""; [ "$1" = avec ] && renum="update f set seq = nextval('s') where origine = 'import';"
  P -c "begin; insert into f (id, origine) select 'imp' || g, 'import' from generate_series(1, 300) g; select pg_sleep(6); $renum commit;" >/dev/null &
  sleep 2
  P -c "insert into f (id, origine) values ('envoi1', 'envoi');" >/dev/null            # B, validé pendant l'import
  local curseur; curseur=$(P -c "select max(seq) from f;")                              # C lit pendant l'import
  wait
  local recus manques
  recus=$(P -c "select count(*) from f where origine = 'import' and seq > $curseur - 200;")
  manques=$(P -c "select count(*) from f where origine = 'import' and seq <= $curseur - 200;")
  echo "$1 correctif : curseur du téléphone $curseur ; fiches de l'import relues $recus / 300 ; jamais reçues $manques"
}
essai sans
essai avec
