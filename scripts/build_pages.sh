#!/bin/sh
# Prépare le dossier publié par Cloudflare Pages (dist/), sans rien d'autre que le nécessaire.
#   sh scripts/build_pages.sh app   → app.perfora.ma  (l'application : index, css, js, sw, manifeste, icône)
#   sh scripts/build_pages.sh site  → perfora.ma      (le site de présentation : dossier site/)
# Réglages Cloudflare Pages : commande de build = la ligne ci-dessus, dossier de sortie = dist.
# Jamais publiés : docs/, supabase/, tests/, .claude/, scripts/ (ils restent dans le dépôt).
set -e
cible="${1:-app}"
rm -rf dist && mkdir -p dist
if [ "$cible" = "app" ]; then
  cp index.html sw.js manifest.webmanifest icon.svg dist/
  cp -r css js dist/
  cp deploy/app/_headers dist/_headers
elif [ "$cible" = "site" ]; then
  cp -r site/. dist/
else
  echo "Cible inconnue : $cible (app ou site)" >&2; exit 1
fi
echo "dist/ prêt pour « $cible » :"; find dist -type f | sort
