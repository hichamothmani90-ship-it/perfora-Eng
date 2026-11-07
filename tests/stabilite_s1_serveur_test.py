"""Lot S1 sur le serveur factice : fusion des listes élément par élément, version minimale (miroir de tests_stabilite_s1.sql).
Usage : python tests/serveur_factice.py 8090   puis   python tests/stabilite_s1_serveur_test.py 8090   (serveur neuf)"""
import json, sys, urllib.error, urllib.request

BASE = f"http://localhost:{sys.argv[1] if len(sys.argv) > 1 else 8090}"
ok = ko = 0


def appel(methode, chemin, corps=None, jeton=None):
    req = urllib.request.Request(BASE + chemin, method=methode, data=None if corps is None else json.dumps(corps).encode(),
                                 headers={"apikey": "cle-factice", "Content-Type": "application/json", **({"Authorization": "Bearer " + jeton} if jeton else {})})
    try:
        with urllib.request.urlopen(req) as r:
            t = r.read()
            return r.status, json.loads(t) if t else None
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


def verif(nom, cond, detail=""):
    global ok, ko
    if cond:
        ok += 1; print("ok :", nom)
    else:
        ko += 1; print("ÉCHEC :", nom, detail)


def session(email):
    return appel("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": "test-gmao"})[1]["access_token"]


def pousser(j, lot, version=None):
    return appel("POST", "/rest/v1/rpc/push_fiches", {"lot": lot, **({"version": version} if version else {})}, j)


def ot(j):
    _, rows = appel("GET", "/rest/v1/fiches?select=id,type,data,seq&seq=gt.0&order=seq.asc&limit=5000", None, j)
    return next(r["data"] for r in rows if r["id"] == "s1-ot")


P = lambda patch: [{"id": "s1-ot", "type": "ots", "patch": patch}]
ids = lambda d: [x["id"] for x in d["intervenants"]]
resp, tech = session("test@gmao.test"), session("tech3@gmao.test")
pousser(resp, [{"id": "s1-eq", "type": "equipements", "patch": {"id": "s1-eq", "code": "S1", "designation": "Presse S1", "siteId": "s-tng"}},
               {"id": "s1-ot", "type": "ots", "patch": {"id": "s1-ot", "equipementId": "s1-eq", "siteId": "s-tng", "nature": "corrective", "priorite": "rapide",
                                                       "statut": "en_cours", "intervenants": [], "activites": ["diagnostic"], "mesures": [{"v": 1}]}}])

pousser(tech, P({"intervenants": [{"id": "i1", "personneId": "p-tech3"}], "activites": ["diagnostic", "reglage"],
                 "$listes": {"intervenants": {"modifies": ["i1"]}, "activites": {"modifies": ["reglage"]}}}))
pousser(resp, P({"intervenants": [{"id": "i2", "personneId": "p-test"}], "activites": ["diagnostic", "essai"],
                 "$listes": {"intervenants": {"modifies": ["i2"]}, "activites": {"modifies": ["essai"]}}}))
d = ot(resp)
verif("deux ajouts simultanés : les deux restent", ids(d) == ["i1", "i2"] and d["activites"] == ["diagnostic", "reglage", "essai"], d)
pousser(tech, P({"intervenants": [{"id": "i1", "personneId": "p-tech3", "fin": "2026-11-07T10:00"}], "$listes": {"intervenants": {"modifies": ["i1"]}}}))
d = ot(resp)
verif("même élément modifié : le dernier gagne, l'autre reste", ids(d) == ["i1", "i2"] and d["intervenants"][0].get("fin") and not d["intervenants"][1].get("fin"), d)
pousser(tech, P({"intervenants": [{"id": "i2", "personneId": "p-test"}], "$listes": {"intervenants": {"modifies": [], "retraits": ["i1"]}}}))
pousser(resp, P({"intervenants": [{"id": "i1", "personneId": "p-tech3"}, {"id": "i2", "personneId": "p-test"}, {"id": "i3", "personneId": "p-test"}],
                 "$listes": {"intervenants": {"modifies": ["i3"]}}}))
verif("retrait par un appareil, ajout par l'autre (pas de résurrection)", ids(ot(resp)) == ["i2", "i3"], ids(ot(resp)))
pousser(resp, P({"activites": ["reglage", "essai", "nettoyage"], "$listes": {"activites": {"modifies": ["nettoyage"], "retraits": ["diagnostic"]}}}))
verif("liste de valeurs : ajouts gardés, retrait appliqué", ot(resp)["activites"] == ["reglage", "essai", "nettoyage"], ot(resp)["activites"])
pousser(resp, P({"mesures": [{"v": 2}]}))
verif("liste sans identifiant : remplacée", ot(resp)["mesures"] == [{"v": 2}])
verif("« $listes » jamais enregistré", "$listes" not in ot(resp))
pousser(resp, P({"intervenants": [{"id": "i9", "personneId": "p-test"}]}))
verif("ancienne appli (liste complète) : ajout sans rien perdre", ids(ot(resp)) == ["i2", "i3", "i9"], ids(ot(resp)))

appel("POST", "/test/version_minimale", {"valeur": "v39"})
st, r = pousser(resp, P({"travaux": "a"}), "v38")
verif("version trop ancienne → refus de tout le lot", st == 400 and "trop ancienne" in r["message"], r)
st, r = pousser(resp, P({"travaux": "b"}))
verif("sans version → refus", st == 400 and "inconnue" in r["message"], r)
st, r = pousser(resp, P({"travaux": "c"}), "v39")
verif("version à jour → accepté", st == 200 and r["acceptes"] == 1, r)
appel("POST", "/test/version_minimale", {"valeur": "v0"})

print(f"\n{ok} ok, {ko} échec(s)")
sys.exit(1 if ko else 0)
