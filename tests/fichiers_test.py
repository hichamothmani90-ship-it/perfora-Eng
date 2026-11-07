"""Règles de l'espace « fichiers » (miroir de supabase/fichiers.sql) contre le serveur factice.
Usage : python tests/serveur_factice.py 8093  puis  python tests/fichiers_test.py 8093"""
import json, sys, urllib.request, urllib.error
B = f"http://localhost:{sys.argv[1] if len(sys.argv) > 1 else 8093}"; CLE = "cle-factice"
def jeton(e):
    r = urllib.request.Request(B + "/auth/v1/token?grant_type=password", data=json.dumps({"email": e, "password": "test-gmao"}).encode(), headers={"apikey": CLE, "Content-Type": "application/json"}, method="POST")
    return json.loads(urllib.request.urlopen(r).read())["access_token"]
def depot(j, chemin, data=b"%PDF-1.4 test", mime="application/pdf"):
    r = urllib.request.Request(B + "/storage/v1/object/fichiers/" + chemin, data=data, headers={"apikey": CLE, "Authorization": "Bearer " + j, "Content-Type": mime}, method="POST")
    try: return str(urllib.request.urlopen(r).status)
    except urllib.error.HTTPError as e: return f"{e.code} {json.loads(e.read()).get('error')}"
def lire(j, chemin):
    r = urllib.request.Request(B + "/storage/v1/object/authenticated/fichiers/" + chemin, headers={"apikey": CLE, "Authorization": "Bearer " + j})
    try: return str(urllib.request.urlopen(r).status)
    except urllib.error.HTTPError as e: return f"{e.code} {json.loads(e.read()).get('error')}"
resp, tech, autre, expl = jeton("test@gmao.test"), jeton("tech3@gmao.test"), jeton("autre@gmao.test"), jeton("expl@gmao.test")
echecs = 0
def ok(nom, v, attendu):
    global echecs
    bon = v.startswith(attendu); echecs += not bon
    print(("OK    " if bon else "ECHEC ") + nom + " : " + v)
ok("responsable depose une facture (couts)", depot(resp, "e-demo/s-tng/couts/facture-0001.pdf"), "200")
ok("technicien lit la facture (couts) -> refus", lire(tech, "e-demo/s-tng/couts/facture-0001.pdf"), "400")
ok("responsable lit la facture", lire(resp, "e-demo/s-tng/couts/facture-0001.pdf"), "200")
ok("technicien depose dans couts -> refus", depot(tech, "e-demo/s-tng/couts/facture-0002.pdf"), "400")
ok("technicien depose sur un site non autorise -> refus", depot(tech, "e-demo/s-cas/documents/doc-000001.pdf"), "400")
ok("responsable depose sur Casablanca", depot(resp, "e-demo/s-cas/documents/doc-000001.pdf"), "200")
ok("technicien Tanger lit un fichier de Casablanca -> refus", lire(tech, "e-demo/s-cas/documents/doc-000001.pdf"), "400")
ok("autre entreprise lit un fichier de DEMO -> refus", lire(autre, "e-demo/s-tng/couts/facture-0001.pdf"), "400")
ok("autre entreprise depose chez DEMO -> refus", depot(autre, "e-demo/commun/documents/intrus-0001.pdf"), "400")
ok("depot en double -> Duplicate (accepte par l'appli)", depot(resp, "e-demo/s-cas/documents/doc-000001.pdf"), "400 Duplicate")
ok("type refuse (executable)", depot(resp, "e-demo/commun/documents/virus-0001.pdf", b"MZ", "application/x-msdownload"), "400")
ok("nom de fichier invalide", depot(resp, "e-demo/commun/documents/..x.pdf"), "400")
ok("exploitation depose une photo", depot(expl, "e-demo/s-cas/photos/photo-0001.jpg", b"\xff\xd8", "image/jpeg"), "200")
print(f"{13 - echecs} / 13 verifications reussies")
