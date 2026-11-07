#!/usr/bin/env bash
# Test de bout en bout, en local (Docker, image Supabase Postgres de même version que le projet) :
#   1. base « source » neuve construite par supabase/production/construire_base.sql (contrôles de fin affichés) ;
#   2. données d'essai : 2 comptes, une entreprise de démo réinitialisée (110 fiches, énergie comprise) ;
#   3. sauvegarde chiffrée (sauvegarder.sh) ;
#   4. base « cible » neuve, construite de même, puis restauration (restaurer.sh) et comparaison des comptages ;
#   5. garde-fou : une seconde restauration sur la cible non vide doit être refusée.
# Usage (Linux / WSL, en root ou membre du groupe docker) : bash scripts/sauvegarde/test_local.sh
# Aucune donnée réelle : comptes fictifs, phrase de test.
set -euo pipefail
IMAGE="${IMAGE:-supabase/postgres:17.11.0.018}"
RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
ICI="$RACINE/scripts/sauvegarde"
T="$(mktemp -d /tmp/perfora-test.XXXX)"
nettoyer() { docker rm -f pf-source pf-cible >/dev/null 2>&1 || true; rm -rf "$T"; }
trap nettoyer EXIT
nettoyer; mkdir -p "$T"

# pg_dump / psql 17 de l'image, avec /tmp partagé (fichiers de sortie de sauvegarder.sh).
mkdir -p "$T/bin"
for b in pg_dump psql; do
  printf '#!/usr/bin/env bash\nexec docker run --rm -i --network host -v /tmp:/tmp -e PGPASSWORD %s %s "$@"\n' "$IMAGE" "$b" > "$T/bin/$b"
  chmod +x "$T/bin/$b"
done
export PG_BIN="$T/bin" PGPASSWORD=test-local

demarrer() {  # nom port
  docker run -d --name "$1" -e POSTGRES_PASSWORD=$PGPASSWORD -p "$2":5432 "$IMAGE" >/dev/null
  for _ in $(seq 1 60); do docker exec "$1" pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done
  sleep 3
}
sql() { docker exec -i "$1" psql -U postgres -h localhost -X -q -v ON_ERROR_STOP=1 -t -A "${@:2}"; }
# L'image ne crée que le schéma « storage » vide (les tables viennent du service de fichiers de Supabase) :
# on ajoute les deux tables utilisées par Perfora, avec les mêmes colonnes, pour le test local seulement.
stockage() {
  docker exec -i "$1" psql -U supabase_admin -d postgres -X -q -v ON_ERROR_STOP=1 >/dev/null < "$RACINE/scripts/sauvegarde/complement_image_locale.sql"
}

echo "== 1. Construction de la base source"
demarrer pf-source 54321
stockage pf-source
sql pf-source < "$RACINE/supabase/production/construire_base.sql" > "$T/construction.log" 2>&1 || { grep -a ERROR -A3 "$T/construction.log"; exit 1; }
sql pf-source -c "select json_build_object('fonctions_ouvertes_sans_compte', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')), 'tables_sans_rls', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), 'entreprises', (select count(*) from entreprises), 'packs', (select count(*) from packs), 'espace_fichiers', (select count(*) from storage.buckets where id = 'fichiers'))"

echo "== 2. Données d'essai"
sql pf-source <<'SQL'
insert into auth.users (id, instance_id, aud, role, email, created_at) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@essai.test', now()),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tech@essai.test', now());
insert into admins_plateforme (user_id) values ('00000000-0000-4000-8000-000000000001');
do $$
declare ent uuid; site uuid;
begin
  insert into entreprises (code, nom, statut, demo) values ('ESSAI', 'Essai sauvegarde', 'actif', true) returning id into ent;
  insert into abonnements (entreprise_id, pack, statut) values (ent, 'entreprise', 'actif');
  insert into sites (entreprise_id, code, nom) values (ent, 'S1', 'Site essai') returning id into site;
  update profils set entreprise_id = ent, site_defaut = site, role = 'technicien' where email = 'tech@essai.test';
  insert into profil_sites (user_id, site_id) values ('00000000-0000-4000-8000-000000000002', site);
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);   -- auth.uid() de l'image lit l'ancien nom
  perform pf_reinitialiser_demo(ent);
end $$;
SQL
sql pf-source -c "select 'fiches ' || count(*) from fiches"

echo "== 3. Sauvegarde chiffrée"
export PHRASE="phrase-de-test-locale-$(date +%s)"
DB_URL="postgresql://postgres@localhost:54321/postgres" SORTIE="$T/sauvegardes" bash "$ICI/sauvegarder.sh" > "$T/sauvegarde.log"; head -2 "$T/sauvegarde.log"
ARCH="$(ls "$T"/sauvegardes/*.tar.gz.gpg)"
if tar -tzf "$ARCH" >/dev/null 2>&1; then echo "ERREUR : archive non chiffrée"; exit 1; fi
echo "archive chiffrée : illisible sans la phrase ✓"
if printf 'mauvaise-phrase-de-test-123' | gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 0 -d "$ARCH" >/dev/null 2>&1; then echo "ERREUR : déchiffrée avec une mauvaise phrase"; exit 1; fi
echo "mauvaise phrase refusée ✓"

echo "== 4. Base cible neuve + restauration"
demarrer pf-cible 54322
stockage pf-cible
sql pf-cible < "$RACINE/supabase/production/construire_base.sql" > /dev/null
DB_URL="postgresql://postgres@localhost:54322/postgres" bash "$ICI/restaurer.sh" "$ARCH"
sql pf-cible -c "select json_build_object('admin', (select count(*) from admins_plateforme), 'profil_tech', (select role || '/' || (entreprise_id is not null) from profils where email = 'tech@essai.test'), 'compteurs', (select count(*) from fiches where type = 'compteurs'), 'factures', (select count(*) from fiches where type = 'factures_energie'), 'seq_fiches_ok', (select last_value >= (select max(seq) from fiches) from fiches_seq))"
# Les règles d'accès fonctionnent sur la base restaurée : le technicien voit les fiches de son site, pas les factures.
sql pf-cible -c "begin; set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true); select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true); select 'vues par le technicien : ' || count(*) || ' fiches, dont factures : ' || count(*) filter (where type = 'factures_energie') from fiches; rollback;"

echo "== 5. Garde-fou"
if DB_URL="postgresql://postgres@localhost:54322/postgres" bash "$ICI/restaurer.sh" "$ARCH" 2>"$T/refus.txt"; then echo "ERREUR : restauration sur base non vide acceptée"; exit 1; fi
echo "refusée sur une base non vide ✓ ($(head -1 "$T/refus.txt"))"
echo "== TEST RÉUSSI"
