"""Lot R2 sur le serveur factice : qualification proposée / validée, arrêt non planifié (miroir de tests_interventions_r2.sql).
Usage : python tests/serveur_factice.py 8090   puis   python tests/interventions_r2_serveur_test.py 8090   (serveur neuf)"""
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


def fiche(j, fid):
    _, rows = appel("GET", "/rest/v1/fiches?select=id,type,data,seq&seq=gt.0&order=seq.asc&limit=5000", None, j)
    return next((r["data"] for r in rows if r["id"] == fid), None)


def ot(fid, **x):
    return {"id": fid, "type": "ots", "patch": {"id": fid, "equipementId": "r2-eq", "siteId": "s-tng", **x}}


resp, tech = session("test@gmao.test"), session("tech3@gmao.test")
pousser(resp, [{"id": "r2-eq", "type": "equipements", "patch": {"id": "r2-eq", "code": "R2-EQ", "designation": "Presse R2", "siteId": "s-tng"}},
               {"id": "r2-prog", "type": "programmes", "patch": {"id": "r2-prog", "equipementId": "r2-eq", "libelle": "Graissage", "siteId": "s-tng"}}])

pousser(tech, [ot("r2-ot1", nature="corrective", priorite="critique_service", statut="en_cours")])
d = fiche(resp, "r2-ot1")
verif("technicien crée : qualification proposée", d["nature"] == "a_qualifier" and d["natureProposee"] == "corrective"
      and d["prioriteProposee"] == "critique_service" and d["qualificationValidee"] is False, d)
pousser(tech, [{"id": "r2-ot1", "type": "ots", "patch": {"nature": "assistance_production"}}])
verif("technicien change la nature non validée : proposée", fiche(resp, "r2-ot1")["natureProposee"] == "assistance_production")
r = pousser(tech, [{"id": "r2-ot1", "type": "ots", "patch": {"qualificationValidee": True, "qualifieePar": "Tech"}}])
verif("technicien valide lui-même → refus", r["acceptes"] == 0 and "réservée au responsable" in r["refuses"][0]["motif"], r)
r = pousser(resp, [{"id": "r2-ot1", "type": "ots", "patch": {"nature": "corrective", "priorite": "critique_service", "qualificationValidee": True, "qualifieePar": "Resp", "qualifieeLe": "2026-11-07T10:00"}}])
verif("responsable valide", r["acceptes"] == 1 and fiche(resp, "r2-ot1")["nature"] == "corrective", r)
r = pousser(tech, [{"id": "r2-ot1", "type": "ots", "patch": {"nature": "preventive"}}])
verif("technicien change une qualification validée → refus", r["acceptes"] == 0 and "déjà validée" in r["refuses"][0]["motif"], r)
pousser(tech, [ot("r2-ot2", programmeId="r2-prog", nature="preventive", priorite="planifiable", statut="a_planifier")])
verif("préventif d'un programme : nature gardée", fiche(resp, "r2-ot2")["nature"] == "preventive")

arret = dict(nature="corrective", statut="en_cours", avecArret="oui", arretType="non_planifie", arretDebut="2026-11-07T08:00", resultat="resolu")
pousser(tech, [ot("r2-ot3", **arret), ot("r2-ot4", **arret), ot("r2-ot5", **{**arret, "arretType": "planifie"})])
r = pousser(tech, [{"id": "r2-ot3", "type": "ots", "patch": {"statut": "cloturee"}}])
verif("terminer un arrêt non planifié sans fin → refus", r["acceptes"] == 0 and "arrêt non planifié" in r["refuses"][0]["motif"], r)
r = pousser(tech, [{"id": "r2-ot3", "type": "ots", "patch": {"statut": "travail_termine", "arretHeuresInconnues": True}}])
verif("avec « heures inconnues » → ok", r["acceptes"] == 1, r)
r = pousser(tech, [{"id": "r2-ot4", "type": "ots", "patch": {"statut": "cloturee", "arretFin": "2026-11-07T09:30"}}])
verif("avec fin d'arrêt → ok", r["acceptes"] == 1, r)
r = pousser(tech, [{"id": "r2-ot5", "type": "ots", "patch": {"statut": "cloturee"}}])
verif("arrêt planifié sans fin → ok", r["acceptes"] == 1, r)
pousser(resp, [ot("r2-old", nature="corrective", statut="en_cours", avecArret="oui", resultat="resolu")])
r = pousser(tech, [{"id": "r2-old", "type": "ots", "patch": {"statut": "cloturee"}}])
verif("ancienne intervention sans arretType → acceptée (contrôle appli)", r["acceptes"] == 1, r)
print(f"{ok} / {ok + ko} vérifications réussies")
sys.exit(1 if ko else 0)
