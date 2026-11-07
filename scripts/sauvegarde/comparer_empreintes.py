"""Compare deux empreintes de schéma (scripts/sauvegarde/empreinte_schema.sql) : projet Supabase / base reconstruite.
Usage : python3 comparer_empreintes.py projet.json locale.json   → liste des différences, code 1 s'il y en a."""
import json
import sys

a, b = (json.load(open(f, encoding="utf-8")) for f in sys.argv[1:3])
ecarts = []
for cle in sorted(set(a) | set(b)):
    x, y = a.get(cle), b.get(cle)
    if isinstance(x, dict) and isinstance(y, dict):
        for k in sorted(set(x) | set(y)):
            if x.get(k) != y.get(k):
                ecarts.append(f"{cle} · {k} : {'absent du projet' if k not in x else 'absent de la base reconstruite' if k not in y else 'différent'}")
    elif x != y:
        ecarts.append(f"{cle} : {x!r} ≠ {y!r}")
print("\n".join(ecarts) if ecarts else "Schémas identiques")
sys.exit(1 if ecarts else 0)
