#!/usr/bin/env bash
# Perfora — restauration d'une sauvegarde chiffrée (faite par sauvegarder.sh) dans une base NEUVE.
#
# Avant : la base cible a été construite avec supabase/production/construire_base.sql (même version de l'appli).
# Variables :
#   DB_URL                     base cible — secret
#   PHRASE                     phrase de chiffrement de la sauvegarde — secret
#   SUPABASE_URL, SERVICE_KEY  facultatifs : projet cible, pour redéposer les fichiers joints
#   FORCER=1                   accepter une cible qui contient déjà des comptes ou des fiches (ils sont REMPLACÉS)
#   PG_BIN                     dossier de psql version 17 (défaut : PATH)
# Usage : restaurer.sh sauvegardes/perfora-AAAA-MM-JJ-HHMM.tar.gz.gpg
set -euo pipefail
: "${DB_URL:?DB_URL manquant}" "${PHRASE:?PHRASE manquante}"
ARCH="${1:?fichier .tar.gz.gpg attendu}"; P="${PG_BIN:+$PG_BIN/}"
ICI="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PSQL=("${P}psql" "$DB_URL" -X -q -v ON_ERROR_STOP=1)

if [ -f "$ARCH.sha256" ]; then ( cd "$(dirname "$ARCH")" && sha256sum -c --quiet "$(basename "$ARCH").sha256" ) || { echo "Empreinte SHA-256 différente : archive abîmée" >&2; exit 1; }; fi
printf '%s' "$PHRASE" | gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 0 -d -o "$T/a.tar.gz" "$ARCH"
tar -C "$T" -xzf "$T/a.tar.gz"
D="$(find "$T" -mindepth 1 -maxdepth 1 -type d -name 'perfora-*' | head -1)"

# Garde-fou : jamais d'écrasement silencieux d'une base en service.
deja=$("${PSQL[@]}" -t -A -c "select (select count(*) from auth.users) + (select count(*) from public.fiches) + (select count(*) from public.profils)")
if [ "$deja" != "0" ] && [ "${FORCER:-}" != "1" ]; then
  echo "La base cible contient déjà $deja compte(s) / fiche(s). Restauration refusée (FORCER=1 pour remplacer)." >&2; exit 1
fi

# Tables du schéma public présentes dans la sauvegarde : vidées puis rechargées (les tables de référence créées par
# construire_base.sql, comme packs, sont remplacées par celles de la sauvegarde).
TABLES=$(grep -oE '^COPY public\.[a-z_0-9]+' "$D/public.sql" | sed 's/^COPY //' | sort -u | paste -sd, -)
{
  echo "begin;"
  echo "set session_replication_role = replica;"     # pas de déclencheurs (quotas, création de profil) pendant le chargement
  [ -n "$TABLES" ] && echo "truncate $TABLES cascade;"
  echo "do \$\$ begin if to_regclass('auth.identities') is not null then delete from auth.identities; end if; end \$\$;"
  echo "delete from auth.users;"
  cat "$D/auth.sql" "$D/public.sql"
  echo "set session_replication_role = origin;"
  echo "commit;"
} > "$T/charger.sql"
"${PSQL[@]}" -f "$T/charger.sql" > /dev/null

# Contrôle : mêmes comptages qu'à la sauvegarde.
python3 - "$D/comptages.json" "$DB_URL" "${P}psql" <<'PY'
import json, subprocess, sys
attendu = json.load(open(sys.argv[1]))["tables"]
ecarts = []
for t, n in attendu.items():
    r = subprocess.run([sys.argv[3], sys.argv[2], "-X", "-t", "-A", "-c", f"select count(*) from {t}"], capture_output=True, text=True, check=True)
    if int(r.stdout.strip()) != int(n):
        ecarts.append(f"{t} : {r.stdout.strip()} au lieu de {n}")
print("Comptages identiques (%d tables)" % len(attendu) if not ecarts else "ÉCARTS : " + " ; ".join(ecarts))
sys.exit(1 if ecarts else 0)
PY

if [ -d "$D/fichiers" ] && [ -n "${SUPABASE_URL:-}" ] && [ -n "${SERVICE_KEY:-}" ]; then
  python3 "$ICI/fichiers.py" deposer "$D/fichiers"
elif [ -d "$D/fichiers" ]; then
  echo "Fichiers joints présents dans la sauvegarde mais non redéposés (SUPABASE_URL / SERVICE_KEY absents)."
fi
echo "Restauration terminée."
