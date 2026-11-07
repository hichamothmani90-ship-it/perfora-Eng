"""Lot R1 sur le serveur factice : périmètre du prestataire, journal restreint, droit administrateur de l'entreprise.
Usage : python tests/serveur_factice.py 8090   puis   python tests/roles_r1_serveur_test.py 8090   (serveur neuf)"""
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
    appel("POST", "/rest/v1/rpc/mon_profil", {}, j)   # crée la fiche personne p-<nom>
    return j


def pousser(j, lot):
    return appel("POST", "/rest/v1/rpc/push_fiches", {"lot": lot}, j)[1]


def lire(j, type_):
    _, rows = appel("GET", "/rest/v1/fiches?select=id,type,data,seq&seq=gt.0&order=seq.asc&limit=1000", None, j)
    return sorted(r["id"] for r in rows if r["type"] == type_ and r["id"].startswith("r1-"))


resp, tech, presta, dirc = session("test@gmao.test"), session("tech3@gmao.test"), session("presta@gmao.test"), session("dir@gmao.test")
pousser(resp, [
    {"id": "r1-eq", "type": "equipements", "patch": {"id": "r1-eq", "code": "R1-EQ", "designation": "Pompe R1", "siteId": "s-tng"}},
    {"id": "r1-d1", "type": "demandes", "patch": {"id": "r1-d1", "equipementId": "r1-eq", "constat": "fuite", "siteId": "s-tng"}},
    {"id": "r1-ot1", "type": "ots", "patch": {"id": "r1-ot1", "equipementId": "r1-eq", "demandeIds": ["r1-d1"], "statut": "planifiee", "siteId": "s-tng",
                                               "intervenants": [{"id": "i1", "personneId": "p-presta", "role": "prestataire", "fin": None}]}},
    {"id": "r1-ot2", "type": "ots", "patch": {"id": "r1-ot2", "equipementId": "r1-eq", "statut": "en_cours", "siteId": "s-tng",
                                               "intervenants": [{"id": "i2", "personneId": "p-tech3", "role": "intervenant", "fin": None}]}},
    {"id": "r1-j1", "type": "journal", "patch": {"id": "r1-j1", "entite": "ots", "entiteId": "r1-ot2", "champ": "travaux", "siteId": "s-tng"}},
    {"id": "r1-j2", "type": "journal", "patch": {"id": "r1-j2", "entite": "ots", "entiteId": "r1-ot1", "champ": "creneau", "siteId": "s-tng"}},
])

verif("prestataire : lit seulement son intervention", lire(presta, "ots") == ["r1-ot1"], lire(presta, "ots"))
verif("prestataire : lit la demande liée", lire(presta, "demandes") == ["r1-d1"], lire(presta, "demandes"))
verif("prestataire : lit le parc", lire(presta, "equipements") == ["r1-eq"])
r = pousser(presta, [{"id": "r1-ot2", "type": "ots", "patch": {"travaux": "pirate"}}])
verif("prestataire : écrit sur l'intervention d'un autre → refus", r["acceptes"] == 0 and "pas confiée" in r["refuses"][0]["motif"], r)
r = pousser(presta, [{"id": "r1-ot1", "type": "ots", "patch": {"travaux": "fait"}}])
verif("prestataire : écrit sur la sienne → ok", r["acceptes"] == 1, r)
r = pousser(presta, [{"id": "r1-ot3", "type": "ots", "patch": {"id": "r1-ot3", "equipementId": "r1-eq", "siteId": "s-tng"}}])
verif("prestataire : crée une intervention → refus", r["acceptes"] == 0, r)
r = pousser(presta, [{"id": "r1-d2", "type": "demandes", "patch": {"id": "r1-d2", "equipementId": "r1-eq", "constat": "bruit", "siteId": "s-tng"}}])
verif("prestataire : signale → ok, et lit son signalement", r["acceptes"] == 1 and "r1-d2" in lire(presta, "demandes"), r)
verif("journal : le technicien lit seulement celui de son intervention", lire(tech, "journal") == ["r1-j1"], lire(tech, "journal"))
verif("journal : le prestataire lit seulement celui de son intervention", lire(presta, "journal") == ["r1-j2"], lire(presta, "journal"))
verif("journal : la direction lit tout", lire(dirc, "journal") == ["r1-j1", "r1-j2"], lire(dirc, "journal"))
_, p = appel("POST", "/rest/v1/rpc/mon_profil", {}, resp)
verif("mon_profil : adminClient", p.get("adminClient") is True and appel("POST", "/rest/v1/rpc/mon_profil", {}, tech)[1].get("adminClient") is False)
st, _ = appel("POST", "/rest/v1/rpc/definir_profil", {"cible": "u-tech2@gmao.test", "nouveau_role": "technicien", "nouveau_nom": "X", "est_actif": True}, tech)
verif("un technicien ne change pas les rôles", st == 403, st)
st, _ = appel("POST", "/rest/v1/rpc/definir_admin_client", {"cible": "u-dir@gmao.test", "valeur": True}, resp)
verif("l'administrateur donne le droit à la direction", st == 200 and appel("POST", "/rest/v1/rpc/mon_profil", {}, dirc)[1].get("adminClient") is True, st)
appel("POST", "/rest/v1/rpc/definir_admin_client", {"cible": "u-dir@gmao.test", "valeur": False}, resp)
st, e = appel("POST", "/rest/v1/rpc/definir_admin_client", {"cible": "u-test@gmao.test", "valeur": False}, resp)
verif("retirer le dernier administrateur → refus", st == 400, (st, e))
_, eq = appel("GET", "/rest/v1/profils", None, resp)
verif("équipe : droit administrateur renvoyé", any(x["email"] == "test@gmao.test" and x["admin_client"] for x in eq))
print(f"{ok} / {ok + ko} vérifications réussies")
sys.exit(1 if ko else 0)
