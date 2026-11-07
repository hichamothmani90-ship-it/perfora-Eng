"""Étape 6 (sécurité) sur le serveur factice : double authentification de l'administrateur, erreurs remontées.
Usage : python tests/serveur_factice.py 8090   puis   python tests/securite_serveur_test.py 8090   (serveur neuf)"""
import base64, hashlib, hmac, json, struct, sys, time, urllib.error, urllib.request

BASE = f"http://localhost:{sys.argv[1] if len(sys.argv) > 1 else 8090}"
CLE = "cle-factice"
ok = ko = 0


def appel(methode, chemin, corps=None, jeton=None):
    req = urllib.request.Request(BASE + chemin, method=methode, data=None if corps is None else json.dumps(corps).encode(),
                                 headers={"apikey": CLE, "Content-Type": "application/json", **({"Authorization": "Bearer " + jeton} if jeton else {})})
    try:
        with urllib.request.urlopen(req) as r:
            t = r.read()
            return r.status, json.loads(t) if t else None
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


def totp(secret, decalage=0):
    cle = base64.b32decode(secret + "=" * (-len(secret) % 8))
    h = hmac.new(cle, struct.pack(">Q", int(time.time() // 30) + decalage), hashlib.sha1).digest()
    o = h[-1] & 15
    return "%06d" % ((struct.unpack(">I", h[o:o + 4])[0] & 0x7FFFFFFF) % 1000000)


def verif(nom, cond, detail=""):
    global ok, ko
    if cond:
        ok += 1; print("ok :", nom)
    else:
        ko += 1; print("ÉCHEC :", nom, detail)


def connexion(email):
    return appel("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": "test-gmao"})[1]


s = connexion("test@gmao.test")
_, p = appel("POST", "/rest/v1/rpc/mon_profil", {}, s["access_token"])
verif("recette : admin sans MFA activée → droits, bandeau d'activation", p["adminPlateforme"] and p["adminMfa"] == {"obligatoire": False, "niveau": "aal1"}, p.get("adminMfa"))
_, f = appel("POST", "/auth/v1/factors", {"factor_type": "totp", "friendly_name": "Perfora test"}, s["access_token"])
verif("inscription : clé et lien otpauth", f["totp"]["secret"] and f["totp"]["uri"].startswith("otpauth://totp/"))
_, d = appel("POST", f"/auth/v1/factors/{f['id']}/challenge", {}, s["access_token"])
st, _ = appel("POST", f"/auth/v1/factors/{f['id']}/verify", {"challenge_id": d["id"], "code": "000000" if totp(f["totp"]["secret"]) != "000000" else "111111"}, s["access_token"])
verif("mauvais code refusé", st == 422, st)
_, d = appel("POST", f"/auth/v1/factors/{f['id']}/challenge", {}, s["access_token"])
st, s2 = appel("POST", f"/auth/v1/factors/{f['id']}/verify", {"challenge_id": d["id"], "code": totp(f["totp"]["secret"])}, s["access_token"])
verif("bon code : nouvelle session", st == 200 and s2.get("access_token"), st)
st, r = appel("POST", "/rest/v1/rpc/pf_mfa_activer", {}, s["access_token"])
verif("activation depuis la session sans code : refusée", st == 400, st)
st, r = appel("POST", "/rest/v1/rpc/pf_mfa_activer", {}, s2["access_token"])
verif("activation depuis la session avec code", st == 200 and r == {"mfaObligatoire": True}, (st, r))
_, s3 = appel("POST", "/auth/v1/token?grant_type=refresh_token", {"refresh_token": s2["refresh_token"]})
_, p = appel("POST", "/rest/v1/rpc/mon_profil", {}, s3["access_token"])
verif("rafraîchissement : la session garde le code (aal2)", p["adminPlateforme"] and p["adminMfa"]["niveau"] == "aal2", p.get("adminMfa"))
s4 = connexion("test@gmao.test")
_, p = appel("POST", "/rest/v1/rpc/mon_profil", {}, s4["access_token"])
verif("nouvelle connexion, mot de passe seul : plus de droits d'admin", not p["adminPlateforme"] and p["adminMfa"] == {"obligatoire": True, "niveau": "aal1"}, p.get("adminMfa"))
st, _ = appel("POST", "/rest/v1/rpc/pf_clients", {}, s4["access_token"])
verif("… pf_clients refusé", st == 400, st)
st, _ = appel("DELETE", f"/auth/v1/factors/{f['id']}", None, s4["access_token"])
verif("… impossible de retirer le facteur confirmé sans code", st == 403, st)
_, u = appel("GET", "/auth/v1/user", None, s4["access_token"])
fv = [x for x in u["factors"] if x["status"] == "verified"]
_, d = appel("POST", f"/auth/v1/factors/{fv[0]['id']}/challenge", {}, s4["access_token"])
_, s5 = appel("POST", f"/auth/v1/factors/{fv[0]['id']}/verify", {"challenge_id": d["id"], "code": totp(f["totp"]["secret"])}, s4["access_token"])
st, l = appel("POST", "/rest/v1/rpc/pf_clients", {}, s5["access_token"])
verif("code saisi : pf_clients lisible", st == 200 and isinstance(l, list), st)
t = connexion("tech3@gmao.test")
_, p = appel("POST", "/rest/v1/rpc/mon_profil", {}, t["access_token"])
verif("technicien : ni admin ni MFA", not p["adminPlateforme"] and p["adminMfa"] is None)
for _ in range(2):
    appel("POST", "/rest/v1/rpc/erreurs_signaler", {"p_erreurs": [{"nature": "erreur", "message": "TypeError: x is undefined", "page": "#/ot/1", "version": "v35", "nb": 1}]}, t["access_token"])
st, e = appel("POST", "/rest/v1/rpc/pf_erreurs_lire", {"p_jours": 7}, s5["access_token"])
verif("erreurs regroupées, lues par l'admin", st == 200 and len(e) == 1 and e[0]["nb"] == 2 and e[0]["email"] == "tech3@gmao.test", e)
st, _ = appel("POST", "/rest/v1/rpc/pf_erreurs_lire", {"p_jours": 7}, t["access_token"])
verif("technicien ne lit pas les erreurs", st == 400, st)
print(f"{ok} / {ok + ko} vérifications réussies")
sys.exit(1 if ko else 0)
