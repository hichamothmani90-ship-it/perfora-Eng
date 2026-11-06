"""Faux serveur Supabase pour tester la synchronisation en local, sans compte.
Reproduit les 3 appels utilisés par js/sync.js et la fusion de supabase/schema.sql :
  POST /auth/v1/token?grant_type=password|refresh_token
  POST /rest/v1/rpc/push_fiches
  GET  /rest/v1/fiches?select=...&seq=gt.N&order=seq.asc&limit=L
Compte de test : test@gmao.test / test-gmao  — clé publique : cle-factice
Lancer : python tests/serveur_factice.py [port]   (8099 par défaut)
Données en mémoire : perdues à l'arrêt."""
import json, secrets, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = next((int(a) for a in sys.argv[1:] if a.isdigit()), 8099)
CLE = "cle-factice"
COMPTES = {"test@gmao.test": "test-gmao", "tech2@gmao.test": "test-gmao"}
APPEND_ONLY = {"journal", "mouvements", "photos"}
TYPES = {"localisations", "equipements", "personnes", "demandes", "ots", "programmes", "articles", "mouvements", "journal", "photos"}

verrou = threading.Lock()
fiches = {}          # id -> {id, type, data, seq}
seq = [0]
jetons = {}          # access -> (email, expire)
rafraichis = {}      # refresh -> email
ENVOIS = []          # e-mails « envoyés » (lien de mot de passe)


def nouvelle_session(email):
    a, r = secrets.token_hex(16), secrets.token_hex(16)
    jetons[a] = (email, time.time() + 3600)
    rafraichis[r] = email
    return {"access_token": a, "refresh_token": r, "expires_in": 3600, "user": {"id": "u-" + email, "email": email}}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "apikey, authorization, content-type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")

    def repondre(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.end_headers()

    def corps(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def utilisateur(self):
        if self.headers.get("apikey") != CLE:
            return None
        tok = (self.headers.get("Authorization") or "").removeprefix("Bearer ")
        e = jetons.get(tok)
        return e[0] if e and e[1] > time.time() else None

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/auth/v1/token":
            if self.headers.get("apikey") != CLE:
                return self.repondre(401, {"message": "Invalid API key"})
            grant = parse_qs(u.query).get("grant_type", [""])[0]
            b = self.corps()
            if grant == "password":
                if COMPTES.get(b.get("email")) != b.get("password"):
                    return self.repondre(400, {"error_description": "Invalid login credentials"})
                return self.repondre(200, nouvelle_session(b["email"]))
            if grant == "refresh_token" and b.get("refresh_token") in rafraichis:
                return self.repondre(200, nouvelle_session(rafraichis.pop(b["refresh_token"])))
            return self.repondre(400, {"error_description": "Invalid refresh token"})
        if u.path == "/auth/v1/recover":
            if self.headers.get("apikey") != CLE:
                return self.repondre(401, {"message": "Invalid API key"})
            ENVOIS.append({"email": self.corps().get("email"), "redirect_to": parse_qs(u.query).get("redirect_to", [""])[0]})
            return self.repondre(200, {})
        if u.path == "/auth/v1/user":   # PUT simulé en POST impossible : voir do_PUT
            return self.repondre(405, {"message": "PUT attendu"})
        if u.path == "/rest/v1/rpc/push_fiches":
            if not self.utilisateur():
                return self.repondre(401, {"message": "JWT expired"})
            lot = self.corps().get("lot", [])
            with verrou:
                for f in lot:
                    if f.get("type") not in TYPES:
                        return self.repondre(400, {"message": "type invalide"})
                    ex = fiches.get(f["id"])
                    if ex and f["type"] in APPEND_ONLY:
                        continue
                    seq[0] += 1
                    data = {**ex["data"], **f["patch"]} if ex else f["patch"]
                    fiches[f["id"]] = {"id": f["id"], "type": f["type"], "data": data, "seq": seq[0]}
            return self.repondre(200, len(lot))
        self.repondre(404, {"message": "inconnu"})

    def do_PUT(self):
        if urlparse(self.path).path == "/auth/v1/user":
            email = self.utilisateur()
            if not email:
                return self.repondre(401, {"message": "JWT expired"})
            mdp = self.corps().get("password", "")
            if len(mdp) < 6:
                return self.repondre(422, {"msg": "Password should be at least 6 characters"})
            COMPTES[email] = mdp
            return self.repondre(200, {"id": "u-" + email, "email": email})
        self.repondre(404, {"message": "inconnu"})

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/auth/v1/user":
            email = self.utilisateur()
            return self.repondre(200, {"id": "u-" + email, "email": email}) if email else self.repondre(401, {"message": "JWT expired"})
        if u.path == "/rest/v1/fiches":
            if not self.utilisateur():
                return self.repondre(401, {"message": "JWT expired"})
            q = parse_qs(u.query)
            apres = int(q.get("seq", ["gt.0"])[0].removeprefix("gt."))
            lim = int(q.get("limit", ["1000"])[0])
            with verrou:
                rows = sorted((f for f in fiches.values() if f["seq"] > apres), key=lambda f: f["seq"])[:lim]
            return self.repondre(200, rows)
        if u.path == "/etat":   # aide aux tests
            with verrou:
                return self.repondre(200, {"envois": ENVOIS[-3:], "fiches": len(fiches), "seq": seq[0], "types": {t: sum(1 for f in fiches.values() if f["type"] == t) for t in TYPES}})
        self.repondre(404, {"message": "inconnu"})


if __name__ == "__main__":
    print(f"Faux serveur Supabase : http://localhost:{PORT}  (clé {CLE})")
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
