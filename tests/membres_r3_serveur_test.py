"""Lot R3 sur le serveur factice : membres, équipes, sociétés prestataires, relier un compte (miroir de tests_membres_r3.sql).
Usage : python tests/serveur_factice.py 8090   puis   python tests/membres_r3_serveur_test.py 8090   (serveur neuf)"""
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
    j = appel("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": "test-gmao"})[1]["access_token"]
    appel("POST", "/rest/v1/rpc/mon_profil", {}, j)   # crée la fiche membre du compte
    return j


def pousser(j, lot):
    return appel("POST", "/rest/v1/rpc/push_fiches", {"lot": lot}, j)[1]


def fiches(j):
    return {r["id"]: r["data"] for r in appel("GET", "/rest/v1/fiches?select=id,type,data,seq&seq=gt.0&order=seq.asc&limit=5000", None, j)[1]}


def refus(r, mot):
    return r["acceptes"] == 0 and mot in r["refuses"][0]["motif"]


resp, tech, presta, mag, dire = (session(e) for e in ("test@gmao.test", "tech3@gmao.test", "presta@gmao.test", "mag@gmao.test", "dir@gmao.test"))

r = pousser(tech, [{"id": "r3-m0", "type": "personnes", "patch": {"id": "r3-m0", "nom": "X", "role": "technicien"}}])
verif("technicien crée un membre → refus", refus(r, "réservés au responsable"), r)
r = pousser(tech, [{"id": "p-tech3", "type": "personnes", "patch": {"telephone": "0600000000"}}])
verif("technicien change son téléphone", r["acceptes"] == 1, r)
r = pousser(tech, [{"id": "p-tech3", "type": "personnes", "patch": {"role": "responsable"}}])
verif("technicien change son rôle → refus", refus(r, "réservés au responsable"), r)
r = pousser(tech, [{"id": "r3-eqp2", "type": "equipes", "patch": {"id": "r3-eqp2", "nom": "Nuit"}}])
verif("technicien crée une équipe → refus", refus(r, "réservés au responsable"), r)
r = pousser(dire, [{"id": "r3-eqp3", "type": "equipes", "patch": {"id": "r3-eqp3", "nom": "Direction"}}])
verif("direction sans droit admin crée une équipe → refus", refus(r, "réservés au responsable"), r)

r = pousser(resp, [{"id": "r3-soc", "type": "fournisseurs", "patch": {"id": "r3-soc", "nom": "Froid Service", "prestataire": True}},
                   {"id": "r3-four", "type": "fournisseurs", "patch": {"id": "r3-four", "nom": "Roulements SA"}},
                   {"id": "r3-m1", "type": "personnes", "patch": {"id": "r3-m1", "nom": "Youssef", "role": "technicien", "societeId": "r3-soc", "actif": True}},
                   {"id": "r3-eqp", "type": "equipes", "patch": {"id": "r3-eqp", "nom": "Mécanique", "chefId": "p-tech3", "membreIds": ["p-tech3", "r3-m1"]}},
                   {"id": "p-presta", "type": "personnes", "patch": {"societeId": "r3-soc"}}])
verif("responsable : société, fournisseur, membre, équipe, société du prestataire", r["acceptes"] == 5, r)
r = pousser(resp, [{"id": "p-tech3", "type": "personnes", "patch": {"role": "magasinier"}}])
verif("rôle d'un membre avec accès par la fiche → refus", refus(r, "par l'administrateur"), r)
r = pousser(resp, [{"id": "p-tech3", "type": "personnes", "patch": {"nom": "Tech Renommé"}}])
equipe = appel("GET", "/rest/v1/profils?select=user_id,email,nom,role,actif,personne_id,admin_client", None, resp)[1]
verif("renommer un membre avec accès : le compte suit", r["acceptes"] == 1 and any(p["email"] == "tech3@gmao.test" and p["nom"] == "Tech Renommé" for p in equipe), equipe)

r = pousser(mag, [{"id": "r3-soc4", "type": "fournisseurs", "patch": {"id": "r3-soc4", "nom": "Autre", "prestataire": True}}])
verif("magasinier crée une société prestataire → refus", refus(r, "société prestataire"), r)
r = pousser(mag, [{"id": "r3-four2", "type": "fournisseurs", "patch": {"id": "r3-four2", "nom": "Visserie"}}])
verif("magasinier crée un fournisseur", r["acceptes"] == 1, r)

pousser(resp, [{"id": "r3-eq", "type": "equipements", "patch": {"id": "r3-eq", "code": "R3-EQ", "designation": "Groupe froid", "siteId": "s-tng"}},
               {"id": "r3-ot1", "type": "ots", "patch": {"id": "r3-ot1", "equipementId": "r3-eq", "siteId": "s-tng", "statut": "planifiee", "societeId": "r3-soc"}},
               {"id": "r3-ot2", "type": "ots", "patch": {"id": "r3-ot2", "equipementId": "r3-eq", "siteId": "s-tng", "statut": "planifiee"}}])
vu = fiches(presta)
verif("prestataire voit l'intervention confiée à sa société, pas l'autre", "r3-ot1" in vu and "r3-ot2" not in vu, sorted(k for k in vu if k.startswith("r3")))
verif("prestataire lit sa société, pas un autre fournisseur", "r3-soc" in vu and "r3-four" not in vu)
r = pousser(presta, [{"id": "r3-ot1", "type": "ots", "patch": {"statut": "en_cours", "intervenants": [{"id": "i1", "personneId": "p-presta", "role": "intervenant"}]}}])
verif("prestataire s'ajoute comme intervenant", r["acceptes"] == 1, r)
r = pousser(tech, [{"id": "r3-ot2", "type": "ots", "patch": {"equipeId": "r3-eqp"}}])
verif("technicien confie une intervention à une équipe → refus", refus(r, "réservé au responsable"), r)

st, rep = appel("POST", "/functions/v1/inviter", {"email": "youssef@gmao.test", "role": "technicien", "sites": ["s-tng"]}, resp)
st2, _ = appel("POST", "/rest/v1/rpc/relier_membre", {"cible": rep["userId"], "personne": "r3-m1"}, dire)
verif("relier_membre sans droit admin → refus", st2 == 403)
st2, _ = appel("POST", "/rest/v1/rpc/relier_membre", {"cible": rep["userId"], "personne": "r3-m1"}, resp)
equipe = appel("GET", "/rest/v1/profils?select=user_id,email,nom,role,actif,personne_id,admin_client", None, resp)[1]
y = next(p for p in equipe if p["email"] == "youssef@gmao.test")
verif("relier_membre : compte relié à la fiche, nom repris", st2 == 200 and y["personne_id"] == "r3-m1" and y["nom"] == "Youssef", y)
yj = session("youssef@gmao.test")
pid = appel("POST", "/rest/v1/rpc/mon_profil", {}, yj)[1]["personneId"]
verif("le nouveau compte arrive sur sa fiche (pas de doublon)", pid == "r3-m1" and "p-youssef" not in fiches(resp), pid)
st3, _ = appel("POST", "/rest/v1/rpc/relier_membre", {"cible": "u-tech3@gmao.test", "personne": "r3-m1"}, resp)
verif("relier un membre déjà relié à un autre compte → refus", st3 == 400)
appel("POST", "/rest/v1/rpc/definir_profil", {"cible": rep["userId"], "nouveau_role": "technicien", "nouveau_nom": "Youssef", "est_actif": False}, resp)
verif("retirer l'accès : le membre reste actif", fiches(resp)["r3-m1"].get("actif") is True)

print(f"\n{ok} ok, {ko} échec(s)")
sys.exit(1 if ko else 0)
