"""Lot S2 (risque H) : le SQL, l'appli et le serveur factice décrivent-ils le même modèle que scripts/modele.py ?
Usage : python tests/coherence_modele_test.py   (aucun serveur nécessaire)"""
import os, re, sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RACINE, "scripts"))
import modele  # noqa: E402

ok = ko = 0


def verif(nom, attendu, obtenu):
    global ok, ko
    a, o = sorted(attendu), sorted(obtenu)
    if a == o:
        ok += 1; print("ok :", nom)
    else:
        ko += 1; print("ÉCHEC :", nom, "| manque :", sorted(set(a) - set(o)), "| en trop :", sorted(set(o) - set(a)))


lire = lambda chemin: open(os.path.join(RACINE, chemin), encoding="utf-8").read()
liste_sql = lambda texte: re.findall(r"'([a-z_]+)'", texte)
liste_js = lambda texte: re.findall(r"'([a-z_]+)'", texte)

# ---------- SQL : séquence de construction (dernière définition active) ----------
ordre = re.search(r"ORDRE = \[(.*?)\]", lire("scripts/assembler_sql.py"), re.S).group(1)
fichiers = [f + ".sql" for f in re.findall(r'"([a-z0-9_]+)"', ordre)]
contrainte = module_sql = None
for f in fichiers:
    t = lire("supabase/" + f)
    for m in re.finditer(r"add constraint fiches_type_check check \(type in \((.*?)\)\)", t, re.S):
        contrainte = liste_sql(m.group(1))
    for m in re.finditer(r"create or replace function public\.module_de\(t text\).*?\$\$(.*?)\$\$", t, re.S):
        module_sql = m.group(1)
verif("SQL : contrainte des types (dernière de la séquence)", modele.TYPES, contrainte)
for mod in ("magasin", "achats", "energie", "preventif"):
    m = re.search(r"when t in \(([^)]*)\) then '" + mod + "'", module_sql) or re.search(r"when t = '([a-z_]+)' then '" + mod + "'", module_sql)
    verif(f"SQL : module_de « {mod} »", [t for t, x in modele.MODULE.items() if x == mod], liste_sql(m.group(1)) if m and "," in m.group(1) or (m and "'" in m.group(1)) else ([m.group(1)] if m else []))

push = lire("supabase/push_fiches.sql")
verif("SQL push_fiches : types acceptés", modele.TYPES, liste_sql(re.search(r"if t not in \((.*?)\) then\s+motif := 'type inconnu'", push, re.S).group(1)))
verif("SQL push_fiches : fiches sans site", modele.SANS_SITE, liste_sql(re.search(r"if motif is null and t not in \((.*?)\) then", push, re.S).group(1)))
verif("SQL push_fiches : fiches jamais modifiées", modele.APPEND_ONLY, liste_sql(re.search(r"elsif t in \(([^)]*)\) then\s+insert into fiches", push).group(1)))

# ---------- Appli : stockage du téléphone ----------
store = lire("js/store.js")
types_js = [t for t in liste_js(re.search(r"const TYPES = \[(.*?)\];", store, re.S).group(1)) if t not in ("meta", "sortie")]
verif("Appli : types stockés", modele.TYPES, types_js)
verif("Appli : fiches rattachées à un site", [t for t in modele.TYPES if t not in modele.SANS_SITE], liste_js(re.search(r"const SITE_TYPES = \[(.*?)\];", store, re.S).group(1)))
verif("Appli : fiches jamais modifiées", modele.APPEND_ONLY, liste_js(re.search(r"const APPEND_ONLY = \[(.*?)\];", store, re.S).group(1)))

# ---------- Serveur factice ----------
fac = lire("tests/serveur_factice.py")
dq = lambda texte: re.findall(r'"([a-z_]+)"', texte)
verif("Factice : types", modele.TYPES, dq(re.search(r"^TYPES = \{(.*?)\}", fac, re.M).group(1)))
verif("Factice : fiches sans site", modele.SANS_SITE, dq(re.search(r"^COMMUNS = \{(.*?)\}", fac, re.M).group(1)))
verif("Factice : fiches jamais modifiées", modele.APPEND_ONLY, dq(re.search(r"^APPEND_ONLY = \{(.*?)\}", fac, re.M).group(1)))
mf = re.search(r"def module_de\(t\):\s+return (.*?)\n\n", fac, re.S).group(1)
for mod in ("magasin", "achats", "energie", "preventif"):
    m = re.search(r'"' + mod + r'" if t (?:in \(([^)]*)\)|== "([a-z_]+)")', mf)
    obtenu = dq(m.group(1)) if m and m.group(1) else ([m.group(2)] if m else [])
    verif(f"Factice : module_de « {mod} »", [t for t, x in modele.MODULE.items() if x == mod], obtenu)

print(f"\n{ok} ok, {ko} échec(s)")
sys.exit(1 if ko else 0)
