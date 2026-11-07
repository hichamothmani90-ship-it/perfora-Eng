#!/bin/sh
# Prépare le dossier publié par Cloudflare Pages (dist/), sans rien d'autre que le nécessaire.
#   sh scripts/build_pages.sh app   → app.perfora.ma  (l'application : index, css, js, sw, manifeste, icône)
# Le site de présentation (perfora.ma) est dans un dépôt séparé : perfora-site (Cloudflare refuse deux projets
# Pages sur un même dépôt).
# Réglages Cloudflare Pages : commande de build = la ligne ci-dessus, dossier de sortie = dist.
# Jamais publiés : docs/, supabase/, tests/, .claude/, scripts/ (ils restent dans le dépôt).
set -e
cible="${1:-app}"
rm -rf dist && mkdir -p dist
if [ "$cible" = "app" ]; then
  cp index.html sw.js manifest.webmanifest icon.svg dist/
  cp -r css js dist/
  cp deploy/app/_headers dist/_headers
  mkdir -p dist/kit && cp kit/Kit_demarrage_Perfora.xlsx dist/kit/   # kit vide, téléchargeable depuis la console
  cp -r console dist/                                                  # centre de contrôle (administrateur) : app.perfora.ma/console/
  # Adresses versionnées : le cache navigateur de Cloudflare (4 h sur le domaine) ne sert jamais une ancienne console.
  version=$(grep -o "gmao-terrain-v[0-9]*" sw.js | head -1)
  sed -i "s/?v=dev/?v=$version/g" dist/console/index.html
  # Scripts communs de l'appli chargés par la console (../js/…) : versionnés aussi, sinon une ancienne copie en cache
  # (sync.js d'avant la double authentification, par ex.) casserait la console nouvelle.
  sed -i -E "s#(\.\./js/[a-z_]+\.js)\"#\1?v=$version\"#g" dist/console/index.html
else
  echo "Cible inconnue : $cible (seule « app » existe ; le site est dans le dépôt perfora-site)" >&2; exit 1
fi
echo "dist/ prêt pour « $cible » :"; find dist -type f | sort
