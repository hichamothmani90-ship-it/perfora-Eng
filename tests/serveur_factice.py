"""Faux serveur Supabase pour tester la synchronisation en local, sans compte.
Reproduit les 3 appels utilisés par js/sync.js et la fusion de supabase/schema.sql :
  POST /auth/v1/token?grant_type=password|refresh_token
  POST /rest/v1/rpc/push_fiches
  GET  /rest/v1/fiches?select=...&seq=gt.N&order=seq.asc&limit=L
Comptes de test : test@gmao.test (responsable), tech2@gmao.test (technicien) / test-gmao
Clé publique : cle-factice. Mêmes règles de droits que supabase/roles.sql.
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
PROFILS = {          # email -> profil (miroir de la table profils)
    "test@gmao.test": {"role": "responsable", "nom": "Responsable test", "actif": True},
    "tech2@gmao.test": {"role": "technicien", "nom": "Technicien test", "actif": True},
}


def peut_ecrire(r, t):
    if not r or r == "pilote":
        return False
    if r == "responsable":
        return True
    if t in ("demandes", "journal", "photos"):
        return True
    if t == "ots":
        return r in ("technicien", "prestataire")
    if t == "articles":
        return r == "magasinier"
    if t == "mouvements":
        return r in ("magasinier", "technicien", "prestataire")
    return False


def role_de(email):
    p = PROFILS.get(email)
    return p["role"] if p and p["actif"] else None


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
            email = self.utilisateur()
            if not email:
                return self.repondre(401, {"message": "JWT expired"})
            r = role_de(email)
            if not r:
                return self.repondre(403, {"message": "Compte sans droits (profil absent ou désactivé)"})
            lot = self.corps().get("lot", [])
            acceptes, refus, refuses = 0, [], set()
            with verrou:
                for f in lot:
                    t = f.get("type")
                    cible = f["patch"].get("entite") if t == "journal" else t
                    motif = None
                    if t not in TYPES:
                        motif = "type inconnu"
                    elif t == "journal" and f["patch"].get("entiteId") in refuses:
                        motif = "modification liée refusée"
                    elif not peut_ecrire(r, cible):
                        motif = f"droits insuffisants ({r})"
                    elif t == "mouvements" and r in ("technicien", "prestataire") and not f["patch"].get("otId"):
                        motif = "mouvement de stock hors intervention : réservé au magasin"
                    elif t == "ots" and r != "responsable" and fiches.get(f["id"], {}).get("data", {}).get("statut") == "cloturee":
                        motif = "intervention clôturée : modification réservée au responsable"
                    if motif:
                        refus.append({"id": f["id"], "type": t, "motif": motif})
                        refuses.add(f["id"])
                        continue
                    ex = fiches.get(f["id"])
                    acceptes += 1
                    if ex and t in APPEND_ONLY:
                        continue
                    seq[0] += 1
                    data = {**ex["data"], **f["patch"]} if ex else f["patch"]
                    fiches[f["id"]] = {"id": f["id"], "type": t, "data": data, "seq": seq[0]}
            return self.repondre(200, {"acceptes": acceptes, "refuses": refus})
        if u.path == "/rest/v1/rpc/mon_profil":
            email = self.utilisateur()
            if not email:
                return self.repondre(401, {"message": "JWT expired"})
            p = PROFILS.get(email)
            if not p:
                return self.repondre(403, {"message": "Compte sans profil"})
            pid = "p-" + email.split("@")[0]
            with verrou:
                if pid not in fiches:
                    seq[0] += 1
                    fiches[pid] = {"id": pid, "type": "personnes", "seq": seq[0], "data": {"id": pid, "nom": p["nom"], "role": p["role"], "actif": p["actif"], "email": email, "creeLe": "2026-11-06T08:00", "modifieLe": "2026-11-06T08:00"}}
            return self.repondre(200, {"userId": "u-" + email, "email": email, "nom": p["nom"], "role": p["role"], "personneId": pid, "actif": p["actif"]})
        if u.path == "/rest/v1/rpc/definir_profil":
            email = self.utilisateur()
            if role_de(email) != "responsable":
                return self.repondre(403, {"message": "Réservé au responsable"})
            b = self.corps()
            cible = b["cible"].removeprefix("u-")
            if cible not in PROFILS:
                return self.repondre(404, {"message": "inconnu"})
            PROFILS[cible].update({"role": b.get("nouveau_role") or PROFILS[cible]["role"], "nom": b.get("nouveau_nom") or PROFILS[cible]["nom"], "actif": b.get("est_actif", True)})
            pid = "p-" + cible.split("@")[0]
            with verrou:
                if pid in fiches:
                    seq[0] += 1
                    fiches[pid]["data"].update({k: PROFILS[cible][k] for k in ("role", "nom", "actif")})
                    fiches[pid]["seq"] = seq[0]
            return self.repondre(200, None)
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
        if u.path == "/rest/v1/profils":
            email = self.utilisateur()
            if not email:
                return self.repondre(401, {"message": "JWT expired"})
            vis = PROFILS.items() if role_de(email) == "responsable" else [(email, PROFILS[email])]
            return self.repondre(200, [{"user_id": "u-" + e, "email": e, "nom": p["nom"], "role": p["role"], "actif": p["actif"], "personne_id": "p-" + e.split("@")[0]} for e, p in sorted(vis)])
        if u.path == "/rest/v1/fiches":
            email = self.utilisateur()
            if not email or not role_de(email):
                return self.repondre(401, {"message": "JWT expired"})
            q = parse_qs(u.query)
            if "id" in q:   # id=in.("a","b")
                ids = [x.strip('"') for x in q["id"][0].removeprefix("in.(").removesuffix(")").split(",")]
                with verrou:
                    return self.repondre(200, [fiches[i] for i in ids if i in fiches])
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
