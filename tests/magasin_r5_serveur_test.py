"""Lot R5 sur le serveur factice : achat urgent, qui commande (miroir de tests_magasin_r5.sql).
Usage : python tests/serveur_factice.py 8090   puis   python tests/magasin_r5_serveur_test.py 8090   (serveur neuf)"""
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


A = lambda fid, patch: [{"id": fid, "type": "achats", "patch": patch}]
refuse = lambda r, mot: r["acceptes"] == 0 and mot in r["refuses"][0]["motif"]

appel("POST", "/test/abonnement", {"entreprise": "DEMO", "pack": "entreprise"})
resp, mag, ach = session("test@gmao.test"), session("mag@gmao.test"), session("achat@gmao.test")
S = {"siteId": "s-cas"}
pousser(resp, [{"id": "r5-eq", "type": "equipements", "patch": {"id": "r5-eq", "code": "R5", "designation": "Presse R5", **S}},
               {"id": "r5-art", "type": "articles", "patch": {"id": "r5-art", "ref": "6205", "designation": "Roulement 6205", "unite": "u"}},
               {"id": "r5-ot", "type": "ots", "patch": {"id": "r5-ot", "equipementId": "r5-eq", "statut": "suspendue", **S}},
               {"id": "r5-b", "type": "besoins", "patch": {"id": "r5-b", "otId": "r5-ot", "articleId": "r5-art", "qte": 2, "statut": "indisponible", "urgent": True, **S}}])
pousser(mag, A("r5-da2", {"id": "r5-da2", "ref": "DA-2", "statut": "soumise", "lignes": [{"id": "l2", "articleId": "r5-art", "qte": 1}], **S}))
pousser(mag, A("r5-da3", {"id": "r5-da3", "ref": "DA-3", "statut": "soumise", "lignes": [{"id": "l3", "articleId": "r5-art", "qte": 1}], **S}))
pousser(resp, A("r5-da3", {"statut": "validee", "valideLe": "2026-11-07"}))

ligne = [{"id": "l1", "articleId": "r5-art", "qte": 2, "besoinId": "r5-b", "otId": "r5-ot"}]
r = pousser(mag, A("r5-da1", {"id": "r5-da1", "ref": "DA-1", "statut": "soumise", "urgent": True, "lignes": ligne, **S}))
verif("demande urgente sans motif → refus", refuse(r, "motif"), r)
r = pousser(mag, A("r5-da1", {"id": "r5-da1", "ref": "DA-1", "statut": "soumise", "urgent": True, "motifUrgence": "presse à l'arrêt", "lignes": ligne, **S}))
verif("demande urgente avec motif, liée à la pièce", r["acceptes"] == 1, r)
r = pousser(ach, A("r5-da1", {"statut": "commandee", "fournisseur": "Roulements SA", "refCommande": "C-1", "dateCommande": "2026-11-07", "livraisonPrevue": "2026-11-09"}))
verif("Achats commande la demande urgente encore soumise", r["acceptes"] == 1, r)
rows = appel("GET", "/rest/v1/fiches?select=id,type,data,seq&seq=gt.0&order=seq.asc&limit=5000", None, session("tech2@gmao.test"))[1]
sv = next(x["data"].get("suiviAchat") for x in rows if x["id"] == "r5-b")
verif("le technicien voit le résumé de la commande sur sa pièce, sans prix", sv and sv["statut"] == "commandee" and sv["fournisseur"] == "Roulements SA" and not any("prix" in k for k in sv), sv)
r = pousser(ach, A("r5-da2", {"statut": "commandee", "fournisseur": "X", "refCommande": "C-2"}))
verif("Achats commande une demande normale soumise → refus", refuse(r, "pas encore validée"), r)
r = pousser(mag, A("r5-da3", {"statut": "commandee", "fournisseur": "X", "refCommande": "C-3"}))
verif("magasinier commande (réglage Achats) → refus", r["acceptes"] == 0, r)
pousser(resp, [{"id": "parametres-e-demo", "type": "parametres", "patch": {"id": "parametres-e-demo", "quiCommande": "magasinier"}}])
r = pousser(mag, A("r5-da3", {"statut": "commandee", "fournisseur": "X", "refCommande": "C-3", "dateCommande": "2026-11-07"}))
verif("magasinier commande (réglage magasinier)", r["acceptes"] == 1, r)
r = pousser(mag, A("r5-da2", {"statut": "commandee", "refCommande": "C-2", "valideLe": "2026-11-07"}))
verif("magasinier glisse une validation dans la commande → refus", r["acceptes"] == 0, r)
r = pousser(resp, A("r5-da1", {"valideLe": "2026-11-07T10:00", "validePar": "Resp", "valideApresCoup": True}))
verif("responsable valide après coup", r["acceptes"] == 1, r)
r = pousser(mag, [{"id": "r5-b", "type": "besoins", "patch": {"achatId": "r5-da1", "ligneId": "l1", "qteReservee": 2, "statut": "reserve"}}])
verif("magasinier lie la pièce et la réserve", r["acceptes"] == 1, r)

print(f"\n{ok} ok, {ko} échec(s)")
sys.exit(1 if ko else 0)
