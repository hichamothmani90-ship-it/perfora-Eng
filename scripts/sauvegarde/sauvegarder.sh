#!/usr/bin/env bash
# Perfora — sauvegarde chiffrée d'une base Supabase (données + comptes + fichiers joints).
# Lancé chaque nuit par .github/workflows/sauvegarde.yml (dépôt GitHub PRIVÉ), ou à la main.
#
# Variables :
#   DB_URL                     connexion Postgres (Supabase : « Session pooler », port 5432) — secret
#   PHRASE                     phrase de chiffrement (au moins 20 caractères) — secret, à garder hors de GitHub aussi
#   SUPABASE_URL, SERVICE_KEY  facultatifs : pour copier les fichiers joints (espace « fichiers ») — secrets
#   SORTIE                     dossier de sortie (défaut : sauvegardes)
#   PG_BIN                     dossier de pg_dump / psql version 17 (défaut : PATH)
# Résultat : $SORTIE/perfora-AAAA-MM-JJ-HHMM.tar.gz.gpg (AES-256) + .sha256
# Le schéma n'est pas restauré depuis la sauvegarde : il se reconstruit avec supabase/production/construire_base.sql
# (même version de l'appli), puis restaurer.sh recharge les données.
set -euo pipefail
: "${DB_URL:?DB_URL manquant}" "${PHRASE:?PHRASE manquante}"
[ "${#PHRASE}" -ge 20 ] || { echo "PHRASE trop courte (20 caractères minimum)" >&2; exit 1; }
SORTIE="${SORTIE:-sauvegardes}"; P="${PG_BIN:+$PG_BIN/}"
ICI="$(cd "$(dirname "$0")" && pwd)"
NOM="perfora-$(date -u +%Y-%m-%d-%H%M)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/$NOM" "$SORTIE"
D="$T/$NOM"

"${P}pg_dump" --version | grep -q " 1[7-9]\." || { echo "pg_dump 17 ou plus requis" >&2; exit 1; }
# 1) Données de l'appli (schéma public), comptes (auth), sans propriétaires ni droits.
"${P}pg_dump" "$DB_URL" --data-only --no-owner --no-privileges --schema=public -f "$D/public.sql"
AUTH=$("${P}psql" "$DB_URL" -X -t -A -c "select string_agg('--table=auth.' || t, ' ') from unnest(array['users','identities']) t where to_regclass('auth.' || t) is not null")
# shellcheck disable=SC2086
"${P}pg_dump" "$DB_URL" --data-only --no-owner --no-privileges $AUTH -f "$D/auth.sql"
# 2) Schéma public pour information (comparer avec construire_base.sql si besoin).
"${P}pg_dump" "$DB_URL" --schema-only --no-owner --no-privileges --schema=public -f "$D/schema_public.sql"
# 3) Comptages de contrôle (relus après restauration).
"${P}psql" "$DB_URL" -X -q -t -A -v ON_ERROR_STOP=1 -c "
  select json_build_object('tables', (select json_object_agg(t, n) from (
      select 'public.' || c.relname as t, (xpath('/row/n/text()', query_to_xml('select count(*) as n from public.' || quote_ident(c.relname), false, true, '')))[1]::text::bigint as n
      from pg_class c join pg_namespace s on s.oid = c.relnamespace where s.nspname = 'public' and c.relkind = 'r'
      union all select 'auth.users', (select count(*) from auth.users)
      union all select 'auth.identities', (xpath('/row/n/text()', query_to_xml('select count(*) as n from auth.identities', false, true, '')))[1]::text::bigint
        where to_regclass('auth.identities') is not null) x),
    'fichiers_stockage', (select count(*) from storage.objects where bucket_id = 'fichiers'),
    'version', version(), 'le', now())" > "$D/comptages.json"
# 4) Fichiers joints (photos, PDF) : copie de l'espace « fichiers ».
if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SERVICE_KEY:-}" ]; then
  python3 "$ICI/fichiers.py" telecharger "$D/fichiers"
else
  echo "Fichiers joints non copiés (SUPABASE_URL / SERVICE_KEY absents)" | tee "$D/SANS_FICHIERS.txt"
fi
# 5) Archive chiffrée (AES-256, phrase lue sur l'entrée standard : jamais dans la ligne de commande).
tar -C "$T" -czf "$T/$NOM.tar.gz" "$NOM"
printf '%s' "$PHRASE" | gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 0 \
  --symmetric --cipher-algo AES256 -o "$SORTIE/$NOM.tar.gz.gpg" "$T/$NOM.tar.gz"
( cd "$SORTIE" && sha256sum "$NOM.tar.gz.gpg" > "$NOM.tar.gz.gpg.sha256" )
echo "Sauvegarde : $SORTIE/$NOM.tar.gz.gpg ($(du -h "$SORTIE/$NOM.tar.gz.gpg" | cut -f1))"
cat "$D/comptages.json"
