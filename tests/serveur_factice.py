"""Faux serveur Supabase pour tester l'appli en local, sans compte ni réseau.
Reproduit les appels de js/sync.js et les règles de supabase/schema.sql, roles.sql et
multitenant.sql (entreprises, sites, modules du pack, abonnement, rôles) :
  POST /auth/v1/token?grant_type=password|refresh_token   · POST /auth/v1/recover · GET/PUT /auth/v1/user
  POST /rest/v1/rpc/push_fiches | mon_profil | definir_profil
  GET  /rest/v1/fiches?...seq=gt.N | id=in.(...)            · GET /rest/v1/profils
Comptes (mot de passe test-gmao), clé publique cle-factice :
  test@gmao.test   responsable, entreprise DEMO (pack Pro), sites Tanger + Casablanca
  tech2@gmao.test  technicien,  entreprise DEMO, site Casablanca seulement
  autre@gmao.test  responsable, entreprise AUTRE (pack Essentiel), site Rabat
Aide aux tests : GET /etat ; POST /test/abonnement {"entreprise":"AUTRE","statut":"suspendu"} ou {"entreprise":"DEMO","pack":"entreprise"}
Quotas (comme supabase/quotas.sql) : rpc/utilisation, rpc/affecter_sites, functions/v1/inviter.
Console plateforme (comme supabase/plateforme.sql) : rpc/pf_* ; test@gmao.test est administrateur plateforme.
Lancer : python tests/serveur_factice.py [port]   (8099 par défaut). Données en mémoire."""
import json, re, secrets, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = next((int(a) for a in sys.argv[1:] if a.isdigit()), 8099)
CLE = "cle-factice"
APPEND_ONLY = {"journal", "mouvements", "photos"}
TYPES = {"localisations", "equipements", "personnes", "demandes", "ots", "programmes", "articles", "mouvements", "journal", "photos", "besoins", "seuils", "achats", "valorisations", "compteurs", "releves", "factures_energie", "parametres", "fournisseurs"}
COMMUNS = {"personnes", "articles", "parametres", "fournisseurs"}
LOTS, ETAPES = {}, {}     # reprise des données (supabase/mise_en_service.sql)
COUTS = {"achats", "valorisations", "factures_energie"}          # lecture restreinte (supabase/achats.sql, energie.sql)
VOIT_COUTS = {"responsable", "magasinier", "achats", "pilote"}

PACKS = {
    "essentiel": {"nom": "Essentiel", "modules": ["base", "preventif"], "maxSites": 1, "maxUtilisateursSite": 2, "maxUtilisateursTotal": 2},  # limites basses pour les tests
    "pro": {"nom": "Pro", "modules": ["base", "preventif", "magasin", "rapports"], "maxSites": 3, "maxUtilisateursSite": 15, "maxUtilisateursTotal": 45},
    "entreprise": {"nom": "Entreprise", "modules": ["base", "preventif", "magasin", "rapports", "achats", "energie", "imports"], "maxSites": None, "maxUtilisateursSite": None, "maxUtilisateursTotal": None},
}
ENTREPRISES = {
    "DEMO": {"id": "e-demo", "code": "DEMO", "nom": "Perfora Démo", "pack": "pro", "statut": "actif"},
    "AUTRE": {"id": "e-autre", "code": "AUTRE", "nom": "Autre Industrie", "pack": "essentiel", "statut": "actif"},
}
SITES = {  # id -> site
    "s-tng": {"id": "s-tng", "entreprise": "DEMO", "code": "TNG", "nom": "Site Tanger"},
    "s-cas": {"id": "s-cas", "entreprise": "DEMO", "code": "CAS", "nom": "Site Casablanca"},
    "s-rab": {"id": "s-rab", "entreprise": "AUTRE", "code": "RAB", "nom": "Site Rabat"},
}
COMPTES = {"expl@gmao.test": "test-gmao", "test@gmao.test": "test-gmao", "tech2@gmao.test": "test-gmao", "autre@gmao.test": "test-gmao", "mag@gmao.test": "test-gmao", "achat@gmao.test": "test-gmao"}
PROFILS = {
    "test@gmao.test": {"role": "responsable", "nom": "Responsable test", "actif": True, "entreprise": "DEMO", "sites": ["s-tng", "s-cas"], "defaut": "s-tng"},
    "tech2@gmao.test": {"role": "technicien", "nom": "Technicien test", "actif": True, "entreprise": "DEMO", "sites": ["s-cas"], "defaut": "s-cas"},
    "autre@gmao.test": {"role": "responsable", "nom": "Responsable Autre", "actif": True, "entreprise": "AUTRE", "sites": ["s-rab"], "defaut": "s-rab"},
    "mag@gmao.test": {"role": "magasinier", "nom": "Magasinier test", "actif": True, "entreprise": "DEMO", "sites": ["s-cas"], "defaut": "s-cas"},
    "expl@gmao.test": {"role": "exploitation", "nom": "Opérateur test", "actif": True, "entreprise": "DEMO", "sites": ["s-cas"], "defaut": "s-cas"},
    "achat@gmao.test": {"role": "achats", "nom": "Acheteur test", "actif": True, "entreprise": "DEMO", "sites": ["s-cas", "s-tng"], "defaut": "s-tng"},
}

verrou = threading.Lock()
fiches = {}          # id -> {id, type, data, seq, entreprise, site}
seq = [0]
jetons, rafraichis, ENVOIS = {}, {}, []


def peut_ecrire(r, t):
    if not r or r == "pilote":
        return False
    if r == "responsable":
        return True
    if t in ("demandes", "journal", "photos"):
        return True
    if t == "ots":
        return r in ("technicien", "prestataire")
    if t in ("articles", "seuils"):
        return r == "magasinier"
    if t in ("achats", "valorisations"):
        return r in ("magasinier", "achats")
    if t in ("mouvements", "besoins"):
        return r in ("magasinier", "technicien", "prestataire")
    if t == "releves":
        return r in ("technicien", "prestataire", "exploitation")
    if t == "fournisseurs":
        return r in ("magasinier", "achats")
    if t == "factures_energie":
        return r == "achats"
    return False


def module_de(t):
    return ("magasin" if t in ("articles", "mouvements", "besoins", "seuils", "fournisseurs") else "achats" if t in ("achats", "valorisations")
            else "energie" if t in ("compteurs", "releves", "factures_energie") else "preventif" if t == "programmes" else "base")


def cloture_par_responsable(ent):
    f = fiches.get("parametres-" + ENTREPRISES[ent]["id"])
    return bool(f and f["entreprise"] == ent and f["data"].get("clotureParResponsable"))


def module_compteur(t, pa, ex, ent, mod):
    """D2 bis : un compteur d'équipement (et ses relevés, son journal) relève du préventif."""
    exd = (ex or {}).get("data", {})
    if t == "compteurs":
        u = pa.get("usage") or exd.get("usage")
    elif t == "releves":
        c = fiches.get(pa.get("compteurId") or exd.get("compteurId") or "")
        u = c and c["entreprise"] == ent and c["data"].get("usage")
    elif t == "journal" and pa.get("entite") in ("compteurs", "releves"):
        x = fiches.get(pa.get("entiteId") or "")
        if x and x["type"] == "releves":
            x = fiches.get(x["data"].get("compteurId") or "")
        u = x and x["entreprise"] == ent and x["data"].get("usage")
    else:
        return mod
    return "preventif" if u == "equipement" else mod


def role_de(email):
    p = PROFILS.get(email)
    return p["role"] if p and p["actif"] else None


def mes_sites(email):
    p = PROFILS[email]
    if p["role"] == "responsable":
        return [s for s, v in SITES.items() if v["entreprise"] == p["entreprise"]]
    return list(p["sites"])


ADMINS = {"test@gmao.test"}


def droits(code):
    e = ENTREPRISES[code]
    pk, d = PACKS[e["pack"]], e.get("derog", {})
    lim = lambda k: d.get(k) if d.get(k) is not None else pk[k]
    return {"pack": e["pack"], "packNom": pk["nom"], "statut": e["statut"], "fin": e.get("fin"), "ecriture": e["statut"] in ("essai", "actif"),
            "modules": pk["modules"], "maxSites": lim("maxSites"), "maxUtilisateursSite": lim("maxUtilisateursSite"), "maxUtilisateursTotal": lim("maxUtilisateursTotal")}


def code_de(ent_id):
    return next((c for c, e in ENTREPRISES.items() if e["id"] == ent_id), None)


def actifs_entreprise(code, sauf=None):
    return sum(1 for e, p in PROFILS.items() if p["entreprise"] == code and p["actif"] and e != sauf)


def actifs_site(site, sauf=None):
    return sum(1 for e, p in PROFILS.items() if site in p["sites"] and p["actif"] and e != sauf)


def controle_quota(code, sites, sauf=None):
    d = droits(code)
    if d["maxUtilisateursTotal"] is not None and actifs_entreprise(code, sauf) + 1 > d["maxUtilisateursTotal"]:
        return f"Quota atteint : {d['maxUtilisateursTotal']} utilisateur(s) actif(s) maximum (pack {d['packNom']}). Désactivez un compte ou changez de pack."
    for s in sites:
        if d["maxUtilisateursSite"] is not None and actifs_site(s, sauf) + 1 > d["maxUtilisateursSite"]:
            return f"Quota atteint : {d['maxUtilisateursSite']} utilisateur(s) maximum sur « {SITES[s]['nom']} »"
    return None


def visible(f, email):
    p = PROFILS[email]
    cout = (f["type"] in COUTS or (f["type"] == "journal" and f["data"].get("entite") in COUTS)
            or (f["type"] == "photos" and f["data"].get("parentType") == "factures_energie"))
    return f["entreprise"] == p["entreprise"] and (f["site"] is None or f["site"] in mes_sites(email)) and (not cout or p["role"] in VOIT_COUTS)


ADMIS = ("localisations", "equipements", "compteurs", "releves", "fournisseurs", "articles", "mouvements", "valorisations", "programmes", "personnes")
COMMUNS_IMPORT = ("articles", "fournisseurs", "personnes")
REFS = (("localisationId", "localisations"), ("parentId", None), ("equipementId", "equipements"), ("compteurId", "compteurs"),
        ("articleId", "articles"), ("mouvementId", "mouvements"), ("fournisseurId", "fournisseurs"))


def importer(code, b):
    """Miroir de pf_importer : tout ou rien ; p_essai = vérification à blanc."""
    lot, lst, essai = b.get("p_lot") or "", b.get("p_fiches") or [], bool(b.get("p_essai"))
    if not re.match(r"^[A-Za-z0-9-]{6,64}$", lot):
        return 400, {"message": "Identifiant de lot invalide"}
    if lot in LOTS:
        return 400, {"message": "Ce lot a déjà été importé"}
    if not lst:
        return 400, {"message": "Aucune fiche à importer"}
    with verrou:
        nouveau, refus, resume = {}, [], {}
        tout = lambda: list(fiches.values()) + list(nouveau.values())
        for f in lst:
            t, d = f.get("type"), {**(f.get("data") or {}), "id": f.get("id"), "lotImport": lot}
            s, motif = None, None
            if t not in ADMIS:
                motif = "type non importable"
            elif not f.get("id"):
                motif = "identifiant manquant"
            elif f["id"] in fiches or f["id"] in nouveau:
                motif = "identifiant déjà utilisé"
            elif t not in COMMUNS_IMPORT:
                s = d.get("siteId")
                if s not in SITES or SITES[s]["entreprise"] != code:
                    motif = "site absent ou d'une autre entreprise"
            if not motif:
                meme = [x for x in tout() if x["entreprise"] == code and x["type"] == t]
                up = lambda v: (v or "").upper()
                if t in ("equipements", "compteurs") and any(up(x["data"].get("code")) == up(d.get("code")) for x in meme):
                    motif = "code équipement déjà utilisé" if t == "equipements" else "code compteur déjà utilisé"
                elif t == "localisations" and any(x["site"] == s and up(x["data"].get("code")) == up(d.get("code")) for x in meme):
                    motif = "code de lieu déjà utilisé sur ce site"
                elif t == "articles" and any(up(x["data"].get("ref")) == up(d.get("ref")) for x in meme):
                    motif = "référence d'article déjà utilisée"
                elif t == "fournisseurs" and any((x["data"].get("nom") or "").lower() == (d.get("nom") or "").lower() for x in meme):
                    motif = "fournisseur déjà présent"
            if motif:
                refus.append({"id": f.get("id"), "type": t, "motif": motif})
                continue
            nouveau[f["id"]] = {"id": f["id"], "type": t, "data": d, "entreprise": code, "site": s}
            resume[t] = resume.get(t, 0) + 1
        par_id = {x["id"]: x for x in tout()}
        for x in nouveau.values():
            for k, cible in REFS:
                v = x["data"].get(k)
                y = par_id.get(v) if v else None
                if v and not (y and y["entreprise"] == code and y["type"] == (cible or x["type"])):
                    refus.append({"id": x["id"], "type": x["type"], "motif": f"référence introuvable ({k})"})
        importe = not essai and not refus
        if importe:
            for x in nouveau.values():
                seq[0] += 1
                fiches[x["id"]] = {**x, "seq": seq[0]}
            LOTS[lot] = {"id": lot, "entreprise": code, "creeLe": time.strftime("%Y-%m-%dT%H:%M:%S"), "fichier": b.get("p_fichier"), "resume": resume, "annuleLe": None, "seq": seq[0]}
    return 200, {"essai": essai, "acceptes": len(nouveau), "refus": refus, "resume": resume, "importe": importe}


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

    # ---------- POST ----------
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
        if u.path == "/test/abonnement":
            b = self.corps()
            if "statut" in b:
                ENTREPRISES[b["entreprise"]]["statut"] = b["statut"]
            if "pack" in b:  # ex. {"entreprise":"DEMO","pack":"entreprise"} pour le module achats
                ENTREPRISES[b["entreprise"]]["pack"] = b["pack"]
            return self.repondre(200, droits(b["entreprise"]))
        email = self.utilisateur()
        if not email:
            return self.repondre(401, {"message": "JWT expired"})
        if u.path == "/rest/v1/rpc/push_fiches":
            return self.push(email)
        if u.path == "/rest/v1/rpc/mon_profil":
            return self.mon_profil(email)
        if u.path == "/rest/v1/rpc/definir_profil":
            return self.definir_profil(email)
        if u.path.startswith("/rest/v1/rpc/pf_"):
            return self.plateforme(email, u.path.removeprefix("/rest/v1/rpc/"))
        moi = PROFILS[email]
        if u.path in ("/rest/v1/rpc/utilisation", "/rest/v1/rpc/affecter_sites", "/functions/v1/inviter") and role_de(email) != "responsable":
            return self.repondre(403, {"message": "Réservé au responsable"})
        ent = moi["entreprise"]
        sites_ent = [k for k, v in SITES.items() if v["entreprise"] == ent]
        if u.path == "/rest/v1/rpc/utilisation":
            d = droits(ent)
            return self.repondre(200, {"actifs": actifs_entreprise(ent), "maxTotal": d["maxUtilisateursTotal"], "maxSite": d["maxUtilisateursSite"], "maxSites": d["maxSites"],
                                       "sites": [{"id": k, "nom": SITES[k]["nom"], "actifs": actifs_site(k)} for k in sorted(sites_ent, key=lambda k: SITES[k]["nom"])],
                                       "affectations": [{"userId": "u-" + e, "siteId": st} for e, p in PROFILS.items() if p["entreprise"] == ent for st in p["sites"]]})
        if u.path == "/rest/v1/rpc/affecter_sites":
            b = self.corps()
            cible, liste = b["cible"].removeprefix("u-"), b.get("liste") or []
            if cible not in PROFILS or PROFILS[cible]["entreprise"] != ent:
                return self.repondre(403, {"message": "Compte hors de votre entreprise"})
            if not liste:
                return self.repondre(400, {"message": "Choisissez au moins un site"})
            if any(x not in sites_ent for x in liste):
                return self.repondre(400, {"message": "Site inconnu ou inactif"})
            d = droits(ent)
            for x in liste:
                if x not in PROFILS[cible]["sites"] and PROFILS[cible]["actif"] and d["maxUtilisateursSite"] is not None and actifs_site(x, cible) + 1 > d["maxUtilisateursSite"]:
                    return self.repondre(400, {"message": f"Quota atteint : {d['maxUtilisateursSite']} utilisateur(s) maximum sur « {SITES[x]['nom']} »"})
            PROFILS[cible]["sites"] = list(liste)
            if PROFILS[cible]["defaut"] not in liste:
                PROFILS[cible]["defaut"] = liste[0]
            return self.repondre(200, None)
        if u.path == "/functions/v1/inviter":
            b = self.corps()
            em, role, liste = (b.get("email") or "").strip().lower(), b.get("role"), b.get("sites") or []
            if b.get("entrepriseId"):   # invitation par l'administrateur plateforme pour un client
                if email not in ADMINS:
                    return self.repondre(400, {"erreur": "Réservé à l'administrateur plateforme"})
                ent = code_de(b["entrepriseId"])
                sites_ent = [k for k, v in SITES.items() if v["entreprise"] == ent]
            if "@" not in em or "." not in em.split("@")[-1]:
                return self.repondre(400, {"erreur": "Adresse e-mail invalide"})
            if not liste or any(x not in sites_ent for x in liste):
                return self.repondre(400, {"erreur": "Choisissez au moins un site de votre entreprise"})
            if em in PROFILS:
                return self.repondre(400, {"erreur": "Ce compte fait déjà partie de l'équipe" if PROFILS[em]["entreprise"] == ent else "Ce compte est rattaché à une autre entreprise"})
            if not droits(ent)["ecriture"]:
                return self.repondre(400, {"erreur": "Abonnement suspendu ou expiré"})
            q = controle_quota(ent, liste)
            if q:
                return self.repondre(400, {"erreur": q})
            PROFILS[em] = {"role": role, "nom": b.get("nom") or em.split("@")[0], "actif": True, "entreprise": ent, "sites": list(liste), "defaut": liste[0]}
            COMPTES[em] = "test-gmao"
            ENVOIS.append({"email": em, "redirect_to": b.get("redirectTo"), "type": "invite"})
            return self.repondre(200, {"ok": True, "userId": "u-" + em, "emailEnvoye": True})
        self.repondre(404, {"message": "inconnu"})

    def push(self, email):
        r = role_de(email)
        if not r:
            return self.repondre(403, {"message": "Compte sans droits (profil absent, désactivé ou sans entreprise)"})
        p = PROFILS[email]
        ent, dr, mes = p["entreprise"], droits(p["entreprise"]), mes_sites(email)
        defaut = p["defaut"] if p["defaut"] in mes else (mes[0] if len(mes) == 1 else None)
        acceptes, refus, refuses = 0, [], set()
        terrain = r in ("technicien", "prestataire")
        with verrou:
            for f in self.corps().get("lot", []):
                t, pa = f.get("type"), f.get("patch") or {}
                cible = pa.get("entite") if t == "journal" else t
                ex = fiches.get(f["id"])
                motif, s = None, None
                if t in ("mouvements", "releves") and ex and ex["entreprise"] == ent and all(ex["data"].get(k) == v for k, v in pa.items()):
                    acceptes += 1  # renvoi identique (réponse perdue, envoi complet) : rien à changer
                    continue
                if t not in TYPES:
                    motif = "type inconnu"
                elif not dr["ecriture"]:
                    motif = "abonnement suspendu ou expiré : lecture seule"
                elif ex and ex["entreprise"] != ent:
                    motif = "fiche d'une autre entreprise"
                elif t == "journal" and pa.get("entiteId") in refuses:
                    motif = "modification liée refusée"
                elif module_compteur(t, pa, ex, ent, module_de(cible)) not in dr["modules"]:
                    motif = f"module « {module_compteur(t, pa, ex, ent, module_de(cible))} » non inclus dans l'abonnement"
                elif not peut_ecrire(r, cible):
                    motif = f"droits insuffisants ({r})"
                # volet B (miroir de supabase/magasin.sql)
                elif t == "besoins" and terrain and ("qteReservee" in pa or "delai" in pa or (pa.get("statut") or "demande") not in ("demande", "annule")):
                    motif = "réservation et disponibilité : réservées au magasin"
                elif t == "besoins" and terrain and not ex and not pa.get("otId"):
                    motif = "un besoin de pièce se rattache à une intervention"
                elif t == "mouvements" and not ex and terrain and not ((pa.get("type") == "remise" and pa.get("urgent")) or pa.get("type") in ("retour", "sortie")):
                    motif = "mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)"
                elif t == "mouvements" and not ex and terrain and not pa.get("otId") and not pa.get("besoinId"):
                    motif = "mouvement de stock hors intervention : réservé au magasin"
                elif t == "mouvements" and ex and (terrain or any(k not in ("verifieLe", "verifiePar", "aVerifier", "modifieLe", "modifiePar") for k in pa)):
                    motif = "un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)"
                # volet C (miroir de supabase/achats.sql)
                elif t == "seuils" and r != "responsable" and ((pa.get("statut") or "propose") != "propose" or "valideLe" in pa or "validePar" in pa):
                    motif = "validation des seuils : réservée au responsable"
                elif t == "seuils" and r != "responsable" and ex and ex["data"].get("statut") == "valide":
                    motif = "un seuil validé ne se modifie pas : proposez une nouvelle version"
                elif t == "seuils" and not ex and not pa.get("articleId"):
                    motif = "un seuil se rattache à un article"
                elif t == "achats" and r == "achats" and not ex:
                    motif = "une demande d'achat est rédigée par le magasin ou le responsable"
                elif t == "achats" and r == "achats" and ex["data"].get("statut") not in ("validee", "transmise", "commandee", "partiellement_recue", "recue"):
                    motif = "demande d'achat pas encore validée par le responsable"
                elif t == "achats" and r == "achats" and "statut" in pa and pa["statut"] not in ("transmise", "commandee"):
                    motif = "les achats renseignent la commande, pas la validation"
                elif t == "achats" and r == "magasinier" and ((ex and ex["data"].get("statut")) or "brouillon") in ("brouillon", "soumise", "a_completer") and "statut" in pa and pa["statut"] not in ("brouillon", "soumise", "annulee"):
                    motif = "validation d'une demande d'achat : réservée au responsable"
                elif t == "achats" and r == "magasinier" and ((ex and ex["data"].get("statut")) or "brouillon") not in ("brouillon", "soumise", "a_completer") and not (
                        pa.get("statut") == "close" and ex["data"].get("statut") in ("commandee", "partiellement_recue", "recue")
                        and all(k in ("statut", "closLe", "closPar", "motifCloture", "modifieLe", "modifiePar") for k in pa)):
                    motif = "demande d'achat validée : modification réservée au responsable et aux achats"
                elif t == "valorisations" and not ex and not pa.get("mouvementId"):
                    motif = "un prix se rattache à une entrée de stock"
                elif t == "valorisations" and ex and r != "responsable":
                    motif = "correction d'un prix : réservée au responsable"
                elif t == "ots" and r != "responsable" and ex and ex["data"].get("statut") == "cloturee":
                    motif = "intervention clôturée : modification réservée au responsable"
                elif t == "ots" and r != "responsable" and pa.get("statut") == "cloturee" and cloture_par_responsable(ent):
                    motif = "clôture réservée au responsable (réglage de l'entreprise) : terminez l'intervention, le responsable la clôture"
                elif t == "parametres" and f["id"] != "parametres-" + ENTREPRISES[ent]["id"]:
                    motif = "paramètres : identifiant réservé à l'entreprise"
                # volet D (miroir de supabase/energie.sql)
                elif t == "compteurs" and ex and any(k in pa and pa[k] != ex["data"].get(k) for k in ("mode", "unite", "coefficient", "usage")) \
                        and any(x["type"] == "releves" and x["entreprise"] == ent and x["data"].get("compteurId") == f["id"] for x in fiches.values()):
                    motif = "compteur déjà relevé : usage, mode, unité et coefficient ne changent plus (rupture déclarée ou nouveau compteur)"
                elif t == "releves" and not ex and not (fiches.get(pa.get("compteurId") or "") or {}).get("type") == "compteurs":
                    motif = "un relevé se rattache à un compteur connu"
                elif t == "releves" and not ex and fiches[pa["compteurId"]]["entreprise"] != ent:
                    motif = "un relevé se rattache à un compteur connu"
                elif t == "releves" and not ex and r != "responsable" and any(k in pa for k in ("decision", "decidePar", "decideLe")):
                    motif = "qualification d'un relevé : réservée au responsable"
                elif t == "releves" and not ex and pa.get("remplaceId") and not (
                        (lambda x: x and x["type"] == "releves" and x["entreprise"] == ent and x["data"].get("compteurId") == pa.get("compteurId"))(fiches.get(pa["remplaceId"]))):
                    motif = "une correction remplace un relevé du même compteur"
                elif t == "releves" and ex and (r != "responsable" or any(k not in ("decision", "motifDecision", "decideLe", "decidePar", "modifieLe", "modifiePar") for k in pa)):
                    motif = "un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)"
                if not motif and t not in COMMUNS:
                    parent = pa.get("entiteId") if t == "journal" else pa.get("parentId") if t == "photos" else (pa.get("besoinId") or pa.get("otId")) if t in ("besoins", "mouvements") else pa.get("mouvementId") if t == "valorisations" else pa.get("compteurId") if t == "releves" else None
                    hp = fiches.get(parent) if parent else None
                    s = (pa.get("siteId") if pa.get("siteId") in SITES else None) or (ex and ex["site"]) or (hp and hp["entreprise"] == ent and hp["site"]) or defaut
                    if not s:
                        motif = "site non déterminé (choisissez un site)"
                    elif s not in mes:
                        motif = "site non autorisé"
                    elif ex and ex["site"] and s != ex["site"] and r != "responsable":
                        motif = "changement de site réservé au responsable"
                if motif:
                    refus.append({"id": f["id"], "type": t, "motif": motif})
                    refuses.add(f["id"])
                    continue
                acceptes += 1
                if ex and t in APPEND_ONLY and t != "mouvements":
                    continue
                seq[0] += 1
                data = {**(ex["data"] if ex else {}), **pa, **({"siteId": s} if s else {})}
                fiches[f["id"]] = {"id": f["id"], "type": t, "data": data, "seq": seq[0], "entreprise": ent, "site": s}
        return self.repondre(200, {"acceptes": acceptes, "refuses": refus})

    def plateforme(self, email, nom):
        if email not in ADMINS:
            return self.repondre(400, {"message": "Réservé à l'administrateur plateforme"})
        b = self.corps()
        if nom == "pf_entreprises":
            out = []
            for c, e in sorted(ENTREPRISES.items(), key=lambda x: x[1]["nom"]):
                d = droits(c)
                out.append({"id": e["id"], "code": c, "nom": e["nom"], "statut": e["statut"], "demo": e.get("demo", False), "reinitLe": e.get("reinitLe"),
                            "abonnement": d, "derogations": e.get("derog", {}), "actifs": actifs_entreprise(c),
                            "sites": [{"id": k, "code": v["code"], "nom": v["nom"], "actif": True, "actifs": actifs_site(k)} for k, v in SITES.items() if v["entreprise"] == c],
                            "responsables": sorted(m for m, pp in PROFILS.items() if pp["entreprise"] == c and pp["role"] == "responsable" and pp["actif"]),
                            "fiches": sum(1 for f in fiches.values() if f["entreprise"] == c), "photos": sum(1 for f in fiches.values() if f["entreprise"] == c and f["type"] == "photos"),
                            "derniereActivite": None})
            return self.repondre(200, out)
        if nom == "pf_creer_entreprise":
            code = (b.get("p_code") or "").strip().upper()
            if not code or code in ENTREPRISES:
                return self.repondre(400, {"message": "Ce code entreprise existe déjà" if code else "Code obligatoire"})
            eid, sid = "e-" + code.lower(), "s-" + code.lower() + "-1"
            ENTREPRISES[code] = {"id": eid, "code": code, "nom": b["p_nom"], "pack": b["p_pack"], "statut": b.get("p_statut") or "essai", "demo": bool(b.get("p_demo")), "derog": {}}
            SITES[sid] = {"id": sid, "entreprise": code, "code": (b.get("p_site_code") or "S1").upper(), "nom": b["p_site_nom"]}
            return self.repondre(200, {"entrepriseId": eid, "siteId": sid})
        code = code_de(b.get("p_entreprise"))
        if not code:
            return self.repondre(400, {"message": "Entreprise inconnue"})
        e = ENTREPRISES[code]
        if nom == "pf_modifier_abonnement":
            e.update({"pack": b["p_pack"], "statut": b["p_statut"], "fin": b.get("p_fin"),
                      "derog": {"maxSites": b.get("p_max_sites"), "maxUtilisateursSite": b.get("p_max_utilisateurs_site"), "maxUtilisateursTotal": b.get("p_max_utilisateurs_total")}})
            return self.repondre(200, None)
        if nom == "pf_ajouter_site":
            d = droits(code)
            n = sum(1 for v in SITES.values() if v["entreprise"] == code)
            if d["maxSites"] is not None and n + 1 > d["maxSites"]:
                return self.repondre(400, {"message": f"Quota atteint : {d['maxSites']} site(s) maximum (pack {d['packNom']})"})
            sid = f"s-{code.lower()}-{n + 1}"
            SITES[sid] = {"id": sid, "entreprise": code, "code": b["p_code"].upper(), "nom": b["p_nom"]}
            return self.repondre(200, sid)
        if nom == "pf_reinitialiser_demo":
            if not e.get("demo"):
                return self.repondre(400, {"message": "Seule une entreprise de démonstration peut être réinitialisée"})
            site = next(k for k, v in SITES.items() if v["entreprise"] == code)
            k = secrets.token_hex(4)
            with verrou:
                for i in [i for i, f in fiches.items() if f["entreprise"] == code]:
                    del fiches[i]
                seed = [("localisations", {"code": "AT", "nom": "Atelier démo", "parentId": None}),
                        ("equipements", {"code": "PRESSE-01", "designation": "Presse hydraulique 200 t", "localisationId": k + "-0", "criticite": "4", "actif": True}),
                        ("demandes", {"ref": "DEM-DEMO-0001", "equipementId": k + "-1", "besoin": "verifier", "constat": "Bruit anormal", "etat": "degrade", "impact": "aucun_constate", "statut": "a_examiner", "creeLe": "2026-11-06T08:00"})]
                for n_, (t, d) in enumerate(seed):
                    seq[0] += 1
                    fid = f"{k}-{n_}"
                    fiches[fid] = {"id": fid, "type": t, "seq": seq[0], "entreprise": code, "site": site,
                                   "data": {**d, "id": fid, "siteId": site, "creeLe": d.get("creeLe", "2026-11-06T08:00"), "modifieLe": "2026-11-06T08:00"}}
            e["reinitLe"] = time.strftime("%Y-%m-%dT%H:%M:%S")
            return self.repondre(200, {"fiches": len(seed), "reinitLe": e["reinitLe"]})
        if nom == "pf_referentiel":
            mine = lambda t: [f for f in fiches.values() if f["entreprise"] == code and f["type"] == t]
            return self.repondre(200, {
                "sites": [{"id": k, "code": v["code"], "nom": v["nom"]} for k, v in SITES.items() if v["entreprise"] == code],
                "localisations": [{"id": f["id"], "code": f["data"].get("code"), "siteId": f["site"]} for f in mine("localisations")],
                "equipements": [{"id": f["id"], "code": f["data"].get("code"), "siteId": f["site"]} for f in mine("equipements")],
                "compteurs": [{"id": f["id"], "code": f["data"].get("code"), "siteId": f["site"], "unite": f["data"].get("unite")} for f in mine("compteurs")],
                "articles": [{"id": f["id"], "ref": f["data"].get("ref")} for f in mine("articles")],
                "fournisseurs": [{"id": f["id"], "nom": f["data"].get("nom")} for f in mine("fournisseurs")],
                "personnes": [{"id": f["id"], "nom": f["data"].get("nom")} for f in mine("personnes")]})
        if nom == "pf_importer":
            return self.repondre(*importer(code, b))
        if nom == "pf_annuler_lot":
            l = LOTS.get(b.get("p_lot"))
            if not l or l["entreprise"] != code:
                return self.repondre(400, {"message": "Lot inconnu pour cette entreprise"})
            if l["annuleLe"]:
                return self.repondre(400, {"message": "Lot déjà annulé"})
            with verrou:
                if any(f["entreprise"] == code and f["seq"] > l["seq"] and f["type"] != "parametres" for f in fiches.values()):
                    return self.repondre(400, {"message": "Le client (ou un lot plus récent) a enregistré des données depuis cet import : annulation impossible, corrigez fiche par fiche"})
                ids = [i for i, f in fiches.items() if f["entreprise"] == code and f["data"].get("lotImport") == l["id"]]
                for i in ids:
                    del fiches[i]
            l["annuleLe"] = time.strftime("%Y-%m-%dT%H:%M:%S")
            return self.repondre(200, {"supprimees": len(ids)})
        if nom == "pf_mes_lire":
            return self.repondre(200, {"etapes": ETAPES.get(code, {}), "lots": sorted(({k: v for k, v in l.items() if k not in ("entreprise", "seq")} for l in LOTS.values() if l["entreprise"] == code), key=lambda l: l["creeLe"], reverse=True)})
        if nom == "pf_mes_etape":
            if b.get("p_cle") not in ("kit_envoye", "kit_recu", "import", "responsable_invite", "qr_imprimes", "equipe_invitee", "mise_en_service"):
                return self.repondre(400, {"message": "Étape inconnue"})
            et = ETAPES.setdefault(code, {})
            if b.get("p_fait"):
                et[b["p_cle"]] = time.strftime("%Y-%m-%dT%H:%M:%S")
            else:
                et.pop(b["p_cle"], None)
            return self.repondre(200, et)
        return self.repondre(404, {"message": "inconnu"})

    def mon_profil(self, email):
        p = PROFILS.get(email)
        if not p:
            return self.repondre(403, {"message": "Compte sans profil"})
        pid = "p-" + email.split("@")[0]
        with verrou:
            if pid not in fiches:
                seq[0] += 1
                fiches[pid] = {"id": pid, "type": "personnes", "seq": seq[0], "entreprise": p["entreprise"], "site": None,
                               "data": {"id": pid, "nom": p["nom"], "role": p["role"], "actif": p["actif"], "email": email, "creeLe": "2026-11-06T08:00", "modifieLe": "2026-11-06T08:00"}}
        e = ENTREPRISES[p["entreprise"]]
        sites = sorted((SITES[s] for s in mes_sites(email)), key=lambda x: x["nom"])
        return self.repondre(200, {"userId": "u-" + email, "email": email, "nom": p["nom"], "role": p["role"], "personneId": pid, "actif": p["actif"],
                                   "entreprise": {"id": e["id"], "code": e["code"], "nom": e["nom"], "statut": e["statut"], "demo": e.get("demo", False), "reinitLe": e.get("reinitLe")},
                                   "sites": [{"id": s["id"], "code": s["code"], "nom": s["nom"]} for s in sites],
                                   "siteDefaut": p["defaut"], "abonnement": droits(p["entreprise"]), "adminPlateforme": email in ADMINS})

    def definir_profil(self, email):
        if role_de(email) != "responsable":
            return self.repondre(403, {"message": "Réservé au responsable"})
        b = self.corps()
        cible = b["cible"].removeprefix("u-")
        if cible not in PROFILS or PROFILS[cible]["entreprise"] != PROFILS[email]["entreprise"]:
            return self.repondre(403, {"message": "Compte hors de votre entreprise"})
        if b.get("est_actif", True) and not PROFILS[cible]["actif"]:
            q = controle_quota(PROFILS[cible]["entreprise"], PROFILS[cible]["sites"], sauf=cible)
            if q:
                return self.repondre(400, {"message": q})
        PROFILS[cible].update({"role": b.get("nouveau_role") or PROFILS[cible]["role"], "nom": b.get("nouveau_nom") or PROFILS[cible]["nom"], "actif": b.get("est_actif", True)})
        pid = "p-" + cible.split("@")[0]
        with verrou:
            if pid in fiches:
                seq[0] += 1
                fiches[pid]["data"].update({k: PROFILS[cible][k] for k in ("role", "nom", "actif")})
                fiches[pid]["seq"] = seq[0]
        return self.repondre(200, None)

    # ---------- PUT / GET ----------
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
        if u.path == "/etat":
            with verrou:
                par = {}
                for f in fiches.values():
                    k = f"{f['entreprise']}/{f['site'] or 'commun'}"
                    par[k] = par.get(k, 0) + 1
                return self.repondre(200, {"envois": ENVOIS[-3:], "fiches": len(fiches), "seq": seq[0], "par_entreprise_site": par})
        email = self.utilisateur()
        if not email:
            return self.repondre(401, {"message": "JWT expired"})
        if u.path == "/auth/v1/user":
            return self.repondre(200, {"id": "u-" + email, "email": email})
        if u.path == "/rest/v1/profils":
            moi = PROFILS[email]
            vis = [(e, p) for e, p in PROFILS.items() if p["entreprise"] == moi["entreprise"]] if role_de(email) == "responsable" else [(email, moi)]
            return self.repondre(200, [{"user_id": "u-" + e, "email": e, "nom": p["nom"], "role": p["role"], "actif": p["actif"], "personne_id": "p-" + e.split("@")[0]} for e, p in sorted(vis)])
        if u.path == "/rest/v1/fiches":
            if not role_de(email):
                return self.repondre(200, [])
            q = parse_qs(u.query)
            with verrou:
                if "id" in q:   # id=in.("a","b")
                    ids = [x.strip('"') for x in q["id"][0].removeprefix("in.(").removesuffix(")").split(",")]
                    return self.repondre(200, [self.public(fiches[i]) for i in ids if i in fiches and visible(fiches[i], email)])
                apres = int(q.get("seq", ["gt.0"])[0].removeprefix("gt."))
                lim = int(q.get("limit", ["1000"])[0])
                rows = sorted((f for f in fiches.values() if f["seq"] > apres and visible(f, email)), key=lambda f: f["seq"])[:lim]
            return self.repondre(200, [self.public(f) for f in rows])
        self.repondre(404, {"message": "inconnu"})

    @staticmethod
    def public(f):
        return {"id": f["id"], "type": f["type"], "data": f["data"], "seq": f["seq"]}


if __name__ == "__main__":
    print(f"Faux serveur Supabase multi-entreprise : http://localhost:{PORT}  (clé {CLE})")
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
