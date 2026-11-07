"""Copie des fichiers joints (espace de stockage Supabase « fichiers ») pour la sauvegarde et la restauration.

  python3 fichiers.py telecharger DOSSIER   : tous les fichiers de l'espace → DOSSIER/<chemin>
  python3 fichiers.py deposer DOSSIER       : DOSSIER/<chemin> → espace « fichiers » du projet (déjà présent = ignoré)
Variables : SUPABASE_URL (https://<projet>.supabase.co), SERVICE_KEY (clé secrète du projet, jamais dans l'appli).
"""
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

ESPACE = "fichiers"
URL = os.environ["SUPABASE_URL"].rstrip("/")
CLE = os.environ["SERVICE_KEY"]
ENTETES = {"Authorization": f"Bearer {CLE}", "apikey": CLE}


def appel(methode, chemin, corps=None, type_contenu="application/json"):
    data = json.dumps(corps).encode() if isinstance(corps, (dict, list)) else corps
    req = urllib.request.Request(URL + chemin, data=data, method=methode, headers={**ENTETES, **({"Content-Type": type_contenu} if data is not None else {})})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def lister(prefixe=""):
    """Tous les chemins de l'espace (les dossiers n'ont pas d'id)."""
    out, depart = [], 0
    while True:
        lot = json.loads(appel("POST", f"/storage/v1/object/list/{ESPACE}", {"prefix": prefixe, "limit": 1000, "offset": depart, "sortBy": {"column": "name", "order": "asc"}}))
        for x in lot:
            chemin = f"{prefixe}/{x['name']}" if prefixe else x["name"]
            out.extend([chemin] if x.get("id") else lister(chemin))
        if len(lot) < 1000:
            return out
        depart += 1000


def telecharger(dossier):
    chemins = lister()
    for c in chemins:
        cible = os.path.join(dossier, *c.split("/"))
        os.makedirs(os.path.dirname(cible), exist_ok=True)
        open(cible, "wb").write(appel("GET", f"/storage/v1/object/authenticated/{ESPACE}/{urllib.parse.quote(c)}"))
    print(f"Fichiers joints copiés : {len(chemins)}")


def deposer(dossier):
    n = deja = 0
    for racine, _, noms in os.walk(dossier):
        for nom in noms:
            local = os.path.join(racine, nom)
            c = os.path.relpath(local, dossier).replace(os.sep, "/")
            try:
                appel("POST", f"/storage/v1/object/{ESPACE}/{urllib.parse.quote(c)}", open(local, "rb").read(),
                      mimetypes.guess_type(nom)[0] or "application/octet-stream")
                n += 1
            except urllib.error.HTTPError as e:
                if e.code in (400, 409) and b"exists" in e.read().lower():
                    deja += 1
                else:
                    raise
    print(f"Fichiers joints déposés : {n} (déjà présents : {deja})")


if __name__ == "__main__":
    {"telecharger": telecharger, "deposer": deposer}[sys.argv[1]](sys.argv[2])
