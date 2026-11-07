"""Lot S2 sur le serveur factice : contenu reconnu, liens existants, code appareil unique (miroir de tests_stabilite_s2.sql).
Usage : python tests/serveur_factice.py 8090   puis   python tests/stabilite_s2_serveur_test.py 8090   (serveur neuf)"""
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


def pousser(j, lot):
    return appel("POST", "/rest/v1/rpc/push_fiches", {"lot": lot}, j)[1]


refuse = lambda r, mot: r["acceptes"] == 0 and mot in r["refuses"][0]["motif"]
appel("POST", "/test/abonnement", {"entreprise": "DEMO", "pack": "entreprise"})
resp, tech = session("test@gmao.test"), session("tech3@gmao.test")
S = {"siteId": "s-tng"}
pousser(resp, [{"id": "s2-eq", "type": "equipements", "patch": {"id": "s2-eq", "code": "S2", "designation": "Presse S2", **S}},
               {"id": "s2-art", "type": "articles", "patch": {"id": "s2-art", "ref": "6205", "designation": "Roulement", "unite": "u"}},
               {"id": "s2-ot", "type": "ots", "patch": {"id": "s2-ot", "equipementId": "s2-eq", "nature": "corrective", "statut": "en_cours", **S}}])
O = lambda patch: [{"id": "s2-ot", "type": "ots", "patch": patch}]
verif("statut inconnu → refus", refuse(pousser(resp, O({"statut": "terminee_bis"})), "valeur non reconnue"))
verif("nature inconnue → refus", refuse(pousser(resp, O({"nature": "curative"})), "valeur non reconnue"))
verif("quantité en texte → refus", refuse(pousser(resp, [{"id": "s2-b1", "type": "besoins", "patch": {"id": "s2-b1", "otId": "s2-ot", "articleId": "s2-art", "qte": "deux", **S}}]), "non numérique"))
verif("date mal formée → refus", refuse(pousser(resp, O({"arretDebut": "07/11/2026 08:00"})), "date mal formée"))
verif("pièce vers une intervention inconnue → refus", refuse(pousser(resp, [{"id": "s2-b2", "type": "besoins", "patch": {"id": "s2-b2", "otId": "inconnue", "articleId": "s2-art", "qte": 1, **S}}]), "(otId)"))
verif("mouvement vers un article inconnu → refus", refuse(pousser(resp, [{"id": "s2-m1", "type": "mouvements", "patch": {"id": "s2-m1", "type": "entree", "articleId": "fantome", "qte": 2, **S}}]), "(articleId)"))
verif("équipe inconnue → refus", refuse(pousser(resp, O({"equipeId": "fantome"})), "(equipeId)"))
r = pousser(resp, [{"id": "s2-ot2", "type": "ots", "patch": {"id": "s2-ot2", "equipementId": "s2-eq", "statut": "en_cours", **S}},
                   {"id": "s2-b3", "type": "besoins", "patch": {"id": "s2-b3", "otId": "s2-ot2", "articleId": "s2-art", "qte": 1, "statut": "demande", **S}}])
verif("intervention et sa pièce dans le même envoi", r["acceptes"] == 2, r)

code = lambda c, a: appel("POST", "/rest/v1/rpc/appareil_code", {"p_code": c, "p_appareil": a}, tech)[1]
verif("appareil A garde K3", code("K3", "app-A") == "K3")
cb = code("K3", "app-B")
verif("appareil B qui demande K3 reçoit un autre code", cb != "K3" and 2 <= len(cb) <= 3, cb)
verif("A et B redemandent : mêmes codes", code("ZZ", "app-A") == "K3" and code(None, "app-B") == cb)

print(f"\n{ok} ok, {ko} échec(s)")
sys.exit(1 if ko else 0)
