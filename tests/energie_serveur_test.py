"""Volet D2 — règles du serveur (miroir de supabase/energie.sql) contre le serveur factice.
Usage : python tests/serveur_factice.py 8093  puis  python tests/energie_serveur_test.py 8093"""
import json
import sys
import urllib.request

BASE = f"http://localhost:{sys.argv[1] if len(sys.argv) > 1 else 8093}"
CLE = "cle-factice"


def req(chemin, corps=None, jeton=None, methode=None):
    h = {"apikey": CLE, "Content-Type": "application/json"}
    if jeton:
        h["Authorization"] = "Bearer " + jeton
    r = urllib.request.Request(BASE + chemin, data=json.dumps(corps).encode() if corps is not None else None, headers=h, method=methode)
    with urllib.request.urlopen(r) as rep:
        return json.loads(rep.read() or b"null")


def jeton(email):
    return req("/auth/v1/token?grant_type=password", {"email": email, "password": "test-gmao"})["access_token"]


def push(j, *fiches):
    return req("/rest/v1/rpc/push_fiches", {"lot": [{"id": i, "type": t, "patch": p} for i, t, p in fiches]}, j)


def lire(j, ids):
    return {f["id"]: f for f in req(f"/rest/v1/fiches?select=id,type,data,seq&id=in.({','.join(ids)})", jeton=j)}


ok = 0


def verifie(nom, cond, detail=""):
    global ok
    if not cond:
        print("ÉCHEC :", nom, detail)
        sys.exit(1)
    ok += 1
    print("ok :", nom)


req("/test/abonnement", {"entreprise": "DEMO", "pack": "pro"})
resp, tech, expl, mag, ach, autre = (jeton(e) for e in ("test@gmao.test", "tech2@gmao.test", "expl@gmao.test", "mag@gmao.test", "achat@gmao.test", "autre@gmao.test"))
r = push(resp, ("d2-c1", "compteurs", {"id": "d2-c1", "code": "EL-01", "unite": "kWh", "mode": "cumulatif", "coefficient": 1, "siteId": "s-cas"}))
verifie("pack Pro : module énergie absent", r["refuses"] and "energie" in r["refuses"][0]["motif"], r)
push(resp, ("d2-eq", "equipements", {"id": "d2-eq", "code": "CMP-D2", "designation": "Compresseur", "siteId": "s-cas"}))
r = push(resp, ("d2-h1", "compteurs", {"id": "d2-h1", "code": "HRS-D2", "usage": "equipement", "equipementId": "d2-eq", "unite": "h", "mode": "cumulatif", "siteId": "s-cas"}),
         ("d2-hj", "journal", {"id": "d2-hj", "entite": "compteurs", "entiteId": "d2-h1", "action": "creation"}))
verifie("D2 bis : compteur d'équipement accepté en pack Pro (préventif), journal compris", r["acceptes"] == 2 and not r["refuses"], r)
r = push(tech, ("d2-hr", "releves", {"id": "d2-hr", "compteurId": "d2-h1", "le": "2026-11-06T08:00", "valeur": 12300}))
verifie("D2 bis : relevé d'heures accepté en pack Pro", r["acceptes"] == 1, r)
r = push(resp, ("d2-h1", "compteurs", {"usage": "ressource"}))
verifie("D2 bis : en pack Pro, passer un compteur en ressource est refusé (module)", r["refuses"] and "energie" in r["refuses"][0]["motif"], r)
req("/test/abonnement", {"entreprise": "DEMO", "pack": "entreprise"})
r = push(resp, ("d2-h1", "compteurs", {"usage": "ressource"}))
verifie("D2 bis : usage figé après le premier relevé", r["refuses"] and "usage" in r["refuses"][0]["motif"], r)

r = push(tech, ("d2-c0", "compteurs", {"id": "d2-c0", "unite": "kWh", "mode": "cumulatif"}))
verifie("technicien ne crée pas de compteur", r["refuses"] and "droits" in r["refuses"][0]["motif"], r)
r = push(resp, ("d2-c1", "compteurs", {"id": "d2-c1", "code": "EL-01", "unite": "kWh", "mode": "cumulatif", "coefficient": 1, "siteId": "s-cas"}))
verifie("responsable crée un compteur", r["acceptes"] == 1, r)
r = push(resp, ("d2-c1", "compteurs", {"coefficient": 40}))
verifie("compteur jamais relevé : coefficient modifiable", r["acceptes"] == 1, r)

r = push(tech, ("d2-r1", "releves", {"id": "d2-r1", "compteurId": "d2-c1", "le": "2026-11-01T08:00", "valeur": 1000}))
verifie("technicien saisit un relevé", r["acceptes"] == 1, r)
r = push(expl, ("d2-r2", "releves", {"id": "d2-r2", "compteurId": "d2-c1", "le": "2026-11-08T08:00", "valeur": 9999}))
verifie("exploitation saisit un relevé", r["acceptes"] == 1, r)
verifie("le relevé prend le site du compteur", lire(resp, ["d2-r2"])["d2-r2"]["data"]["siteId"] == "s-cas")
r = push(mag, ("d2-r9", "releves", {"id": "d2-r9", "compteurId": "d2-c1", "le": "2026-11-08T09:00", "valeur": 1}))
verifie("magasinier ne saisit pas de relevé", bool(r["refuses"]), r)
r = push(tech, ("d2-r3", "releves", {"id": "d2-r3", "compteurId": "inconnu", "le": "2026-11-08T08:00", "valeur": 1}))
verifie("relevé sans compteur connu refusé", r["refuses"] and "compteur connu" in r["refuses"][0]["motif"], r)
r = push(expl, ("d2-r2", "releves", {"valeur": 1025}))
verifie("un relevé ne se modifie pas", r["refuses"] and "ne se modifie pas" in r["refuses"][0]["motif"], r)
r = push(expl, ("d2-r2", "releves", {"id": "d2-r2", "compteurId": "d2-c1", "le": "2026-11-08T08:00", "valeur": 9999}))
verifie("renvoi identique accepté sans rien changer", r["acceptes"] == 1 and not r["refuses"], r)
r = push(tech, ("d2-r4", "releves", {"id": "d2-r4", "compteurId": "d2-c1", "le": "2026-11-08T08:05", "valeur": 1025, "remplaceId": "d2-r2"}))
verifie("correction = nouveau relevé lié", r["acceptes"] == 1, r)
r = push(tech, ("d2-r5", "releves", {"id": "d2-r5", "compteurId": "d2-c1", "le": "2026-11-09T08:00", "valeur": 1030, "decision": "confirme"}))
verifie("technicien ne qualifie pas un relevé", r["refuses"] and "qualification" in r["refuses"][0]["motif"], r)
r = push(tech, ("d2-r1", "releves", {"decision": "invalide"}))
verifie("technicien n'invalide pas un relevé existant", bool(r["refuses"]), r)
r = push(resp, ("d2-r1", "releves", {"decision": "confirme", "motifDecision": "Vérifié sur place", "decidePar": "Resp"}))
verifie("responsable qualifie un relevé", r["acceptes"] == 1, r)
r = push(resp, ("d2-r1", "releves", {"valeur": 1}))
verifie("même le responsable ne change pas la valeur", bool(r["refuses"]), r)
r = push(resp, ("d2-c1", "compteurs", {"coefficient": 2}))
verifie("compteur relevé : coefficient figé (rupture)", r["refuses"] and "rupture" in r["refuses"][0]["motif"], r)
r = push(resp, ("d2-c1", "compteurs", {"libelle": "Arrivée générale"}))
verifie("compteur relevé : libellé modifiable", r["acceptes"] == 1, r)
r = push(tech, ("d2-rup", "releves", {"id": "d2-rup", "compteurId": "d2-c1", "nature": "rupture", "le": "2026-11-10T08:00", "indexFinal": 1040, "indexInitial": 0, "coefficient": 2, "motif": "Remplacement"}))
verifie("technicien déclare une rupture", r["acceptes"] == 1, r)
r = push(autre, ("d2-rx", "releves", {"id": "d2-rx", "compteurId": "d2-c1", "le": "2026-11-10T08:00", "valeur": 5}))
verifie("autre entreprise : compteur inconnu", bool(r["refuses"]), r)

r = push(tech, ("d2-f1", "factures_energie", {"id": "d2-f1", "du": "2026-10-15", "au": "2026-11-15", "quantite": 1010, "unite": "kWh", "montantHT": 1500, "siteId": "s-cas"}))
verifie("technicien ne saisit pas de facture", bool(r["refuses"]), r)
r = push(ach, ("d2-f1", "factures_energie", {"id": "d2-f1", "du": "2026-10-15", "au": "2026-11-15", "quantite": 1010, "unite": "kWh", "montantHT": 1500, "compteurIds": ["d2-c1"], "siteId": "s-cas"}),
         ("d2-pj", "photos", {"id": "d2-pj", "parentType": "factures_energie", "parentId": "d2-f1", "dataUrl": "data:application/pdf;base64,AA=="}),
         ("d2-j1", "journal", {"id": "d2-j1", "entite": "factures_energie", "entiteId": "d2-f1", "action": "creation", "apres": "1500"}))
verifie("achats saisit une facture + pièce jointe", r["acceptes"] == 3, r)
vt, vr, vm = lire(tech, ["d2-f1", "d2-pj", "d2-j1"]), lire(resp, ["d2-f1", "d2-pj", "d2-j1"]), lire(mag, ["d2-f1"])
verifie("technicien ne voit ni la facture, ni sa pièce jointe, ni son journal", vt == {}, vt)
verifie("responsable voit facture, pièce jointe et journal", len(vr) == 3, vr)
verifie("magasinier voit les montants (comme les prix)", "d2-f1" in vm)

r = push(tech, ("parametres-e-demo", "parametres", {"clotureParResponsable": True}))
verifie("technicien ne change pas les réglages", bool(r["refuses"]), r)
r = push(resp, ("parametres-e-autre", "parametres", {"clotureParResponsable": True}))
verifie("réglages : identifiant de l'entreprise imposé", r["refuses"] and "identifiant" in r["refuses"][0]["motif"], r)
r = push(tech, ("d2-ot", "ots", {"id": "d2-ot", "statut": "en_cours", "siteId": "s-cas"}), ("d2-ot", "ots", {"statut": "cloturee"}))
verifie("sans réglage : le technicien clôture", r["acceptes"] == 2, r)
r = push(resp, ("parametres-e-demo", "parametres", {"id": "parametres-e-demo", "clotureParResponsable": True}))
verifie("responsable active « clôture par le responsable »", r["acceptes"] == 1, r)
r = push(tech, ("d2-ot2", "ots", {"id": "d2-ot2", "statut": "en_cours", "siteId": "s-cas"}), ("d2-ot2", "ots", {"statut": "travail_termine"}), ("d2-ot2", "ots", {"statut": "cloturee"}))
verifie("avec réglage : le technicien termine mais ne clôture pas", r["acceptes"] == 2 and "réservée au responsable" in r["refuses"][0]["motif"], r)
r = push(resp, ("d2-ot2", "ots", {"statut": "cloturee"}))
verifie("le responsable clôture", r["acceptes"] == 1, r)
verifie("tous les rôles lisent les réglages", "parametres-e-demo" in lire(tech, ["parametres-e-demo"]))
push(resp, ("parametres-e-demo", "parametres", {"clotureParResponsable": False}))
req("/test/abonnement", {"entreprise": "DEMO", "pack": "pro"})
print(f"{ok} vérifications réussies")
