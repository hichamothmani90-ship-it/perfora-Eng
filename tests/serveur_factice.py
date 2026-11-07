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
import base64, hashlib, hmac, json, re, secrets, struct, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

PORT = next((int(a) for a in sys.argv[1:] if a.isdigit()), 8099)
CLE = "cle-factice"
CLE_SERVICE = "cle-service-factice"   # clé secrète du projet (sauvegarde des fichiers joints : scripts/sauvegarde/fichiers.py)
APPEND_ONLY = {"journal", "mouvements", "photos"}
TYPES = {"localisations", "equipements", "personnes", "demandes", "ots", "programmes", "articles", "mouvements", "journal", "photos", "besoins", "seuils", "achats", "valorisations", "compteurs", "releves", "factures_energie", "parametres", "fournisseurs", "equipes"}
COMMUNS = {"personnes", "articles", "parametres", "fournisseurs", "equipes"}
LOTS, ETAPES = {}, {}     # reprise des données (supabase/mise_en_service.sql)
FICHES_CLIENT = {}        # centre de contrôle (supabase/centre_controle.sql)
# Simulation du réseau pour les tests hors ligne : POST /test/reseau {"mode": "normal" | "panne" | "lent" | "coupures", "delai": s}
#   panne    : la connexion est coupée sans réponse (le téléphone voit « serveur injoignable »)
#   lent     : réponse après `delai` secondes (au-delà de 20 s l'appli abandonne, mais le serveur a bien traité : réponse perdue)
#   coupures : une requête sur deux est coupée
#   portail  : une page HTML répond à la place de l'API (Wi-Fi d'hôtel non connecté)
RESEAU = {"mode": "normal", "delai": 25, "n": 0, "octets_max": 0, "requetes": 0}
OBJETS, ANNONCES, NUM_TICKET = {}, {}, [0]   # CC2 (supabase/centre_controle_cc2.sql)
FICHIERS = {}   # espace « fichiers » (supabase/fichiers.sql) : chemin -> (octets, type)
for _i, (_n, _c, _t) in enumerate([("Bienvenue", "client", "Bonjour {contact}, bienvenue sur Perfora ! Votre espace {entreprise} est prêt : {lien}."),
                                   ("Rappel d'échéance", "client", "Bonjour {contact}, l'abonnement de {entreprise} arrive à échéance le {fin} ({montant})."),
                                   ("Proposition de démo", "prospect", "Bonjour {contact}, je vous propose une démonstration de Perfora de 20 minutes.")]):
    OBJETS[f"modele-{_i}"] = {"id": f"modele-{_i}", "type": "modele", "entrepriseId": None, "creeLe": "2026-11-01T08:00:00", "data": {"nom": _n, "cible": _c, "texte": _t}}
TARIFS = {"essentiel": {}, "pro": {}, "entreprise": {}}
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
COMPTES = {"tech3@gmao.test": "test-gmao", "expl@gmao.test": "test-gmao", "test@gmao.test": "test-gmao", "tech2@gmao.test": "test-gmao", "autre@gmao.test": "test-gmao", "mag@gmao.test": "test-gmao", "achat@gmao.test": "test-gmao", "presta@gmao.test": "test-gmao", "dir@gmao.test": "test-gmao"}
PROFILS = {
    "test@gmao.test": {"role": "responsable", "nom": "Responsable test", "actif": True, "entreprise": "DEMO", "sites": ["s-tng", "s-cas"], "defaut": "s-tng", "admin": True},
    "tech2@gmao.test": {"role": "technicien", "nom": "Technicien test", "actif": True, "entreprise": "DEMO", "sites": ["s-cas"], "defaut": "s-cas"},
    "autre@gmao.test": {"role": "responsable", "nom": "Responsable Autre", "actif": True, "entreprise": "AUTRE", "sites": ["s-rab"], "defaut": "s-rab", "admin": True},
    "mag@gmao.test": {"role": "magasinier", "nom": "Magasinier test", "actif": True, "entreprise": "DEMO", "sites": ["s-cas"], "defaut": "s-cas"},
    "tech3@gmao.test": {"role": "technicien", "nom": "Technicien Tanger", "actif": True, "entreprise": "DEMO", "sites": ["s-tng"], "defaut": "s-tng"},
    "expl@gmao.test": {"role": "exploitation", "nom": "Opérateur test", "actif": True, "entreprise": "DEMO", "sites": ["s-cas"], "defaut": "s-cas"},
    "achat@gmao.test": {"role": "achats", "nom": "Acheteur test", "actif": True, "entreprise": "DEMO", "sites": ["s-cas", "s-tng"], "defaut": "s-tng"},
    "presta@gmao.test": {"role": "prestataire", "nom": "Prestataire Froid", "actif": True, "entreprise": "DEMO", "sites": ["s-tng"], "defaut": "s-tng"},
    "dir@gmao.test": {"role": "pilote", "nom": "Directrice test", "actif": True, "entreprise": "DEMO", "sites": ["s-tng", "s-cas"], "defaut": "s-tng"},
}

verrou = threading.Lock()
fiches = {}          # id -> {id, type, data, seq, entreprise, site}
seq = [0]
jetons, rafraichis, ENVOIS = {}, {}, []
# Étape 6 : double authentification (TOTP), niveau de session, erreurs remontées, journal (miroir de supabase/securite.sql).
NIVEAU, RAFR_NIVEAU = {}, {}          # jeton / jeton de rafraîchissement -> aal1 | aal2
FACTEURS, DEFIS = {}, {}             # email -> [{id, secret, status, friendly_name}] ; défi -> id du facteur
ADMIN_MFA = {"test@gmao.test": False}   # comme la recette avant activation : la console propose de l'activer
ERREURS, JOURNAL = [], []


def totp(secret, t=None):
    cle = base64.b32decode(secret)
    c = struct.pack(">Q", int((t or time.time()) // 30))
    h = hmac.new(cle, c, hashlib.sha1).digest()
    o = h[-1] & 15
    return "%06d" % ((struct.unpack(">I", h[o:o + 4])[0] & 0x7FFFFFFF) % 1000000)


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


# Lot S2 (miroir de supabase/stabilite_s2.sql) : contenu reconnu, liens existants, code appareil unique.
import re as _re
S2_PERMIS = {
    ("ots", "statut"): ["a_preparer", "a_planifier", "planifiee", "prete", "en_cours", "suspendue", "travail_termine", "cloturee", "annulee"],
    ("ots", "nature"): ["a_qualifier", "corrective", "preventive", "assistance_production", "travaux_techniques"],
    ("ots", "priorite"): ["urgence_securite", "critique_service", "rapide", "planifiable", "a_qualifier"],
    ("ots", "avecArret"): ["oui", "non", "inconnu"], ("ots", "arretType"): ["planifie", "non_planifie"],
    ("demandes", "statut"): ["a_examiner", "prise_en_charge", "traitement_organise", "close_sans_travail", "annulee"],
    ("besoins", "statut"): ["demande", "reserve", "indisponible", "annule", "partiellement_remis", "remis"],
    ("mouvements", "type"): ["entree", "sortie", "remise", "retour", "rebut", "ajustement", "isolement", "liberation", "disposition"],
    ("achats", "statut"): ["brouillon", "soumise", "a_completer", "validee", "refusee", "transmise", "commandee", "partiellement_recue", "recue", "close", "annulee"],
}
S2_PERMIS[("ots", "natureProposee")] = S2_PERMIS[("ots", "nature")]
S2_PERMIS[("ots", "prioriteProposee")] = S2_PERMIS[("ots", "priorite")]
S2_DATES = {"creeLe", "modifieLe", "le", "demandeLe", "depuis", "fin", "arretDebut", "arretFin", "arretPrevuDebut", "arretPrevuFin", "creneau",
            "echeance", "clotureLe", "dateCommande", "livraisonPrevue", "valideLe", "soumiseLe", "redigeLe", "delai", "reserveLe", "contratFin"}
S2_DATE_RE = _re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2}([.][0-9]+)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$")
S2_LIENS = [("besoins", "otId", "ots", True), ("besoins", "articleId", "articles", True), ("mouvements", "articleId", "articles", True),
            ("mouvements", "besoinId", "besoins", True), ("mouvements", "otId", "ots", True), ("ots", "equipeId", "equipes", False), ("ots", "societeId", "fournisseurs", False)]
APPAREILS = {}   # (entreprise, code) -> appareil


def s2_controle(t, pa):
    for k, v in pa.items():
        if v is None:
            continue
        permis = S2_PERMIS.get((t, k))
        if permis is not None and (not isinstance(v, str) or v not in permis):
            return f"valeur non reconnue pour « {k} » : {json.dumps(v, ensure_ascii=False)[:40]} (mettez l'appli à jour)"
        if ((t in ("besoins", "mouvements") and k in ("qte", "qteReservee", "quantite")) or (t == "releves" and k == "valeur")) and (isinstance(v, bool) or not isinstance(v, (int, float))):
            return f"quantité non numérique pour « {k} »"
        if k in S2_DATES and isinstance(v, str) and v and not S2_DATE_RE.match(v):
            return f"date mal formée pour « {k} » : {v[:30]}"
    return None


def s2_lien(t, pa, ent, nouvelle):
    for ty, champ, cible, creation in S2_LIENS:
        if ty != t or (creation and not nouvelle) or not pa.get(champ):
            continue
        x = fiches.get(pa[champ])
        if not (x and x["type"] == cible and x["entreprise"] == ent):
            return f"lien vers une fiche inconnue de l'entreprise ({champ})"
    return None


# Lot R5 (miroir de supabase/magasin_r5.sql) : qui commande, commande d'une demande validée ou urgente.
def r5_qui_commande(ent):
    f = fiches.get("parametres-" + ENTREPRISES[ent]["id"])
    return (f and f["entreprise"] == ent and f["data"].get("quiCommande")) or "achats"


def r5_suivi_besoins(daid, ent):
    d = fiches[daid]["data"]
    for l in d.get("lignes") or []:
        b = fiches.get(l.get("besoinId") or "")
        if not (b and b["type"] == "besoins" and b["entreprise"] == ent):
            continue
        resume = {k: v for k, v in {"achatId": daid, "ligneId": l.get("id"), "ref": d.get("ref"), "statut": d.get("statut"), "urgent": d.get("urgent"),
                                    "fournisseur": d.get("fournisseur"), "dateCommande": d.get("dateCommande"), "livraisonPrevue": d.get("livraisonPrevue"),
                                    "valideLe": d.get("valideLe"), "qte": l.get("qteCommandee", l.get("qte"))}.items() if v is not None}
        if b["data"].get("suiviAchat") != resume:
            seq[0] += 1
            b["data"]["suiviAchat"] = resume
            b["seq"] = seq[0]


CHAMPS_COMMANDE = {"statut", "fournisseur", "fournisseurId", "refCommande", "dateCommande", "livraisonPrevue", "devise", "taux",
                   "lignes", "commandeLe", "commandePar", "modifieLe", "modifiePar"}


def r5_commande_acceptee(r, d, pa, ent):
    return ((r == "achats" or (r == "magasinier" and r5_qui_commande(ent) == "magasinier"))
            and (pa.get("statut") or "commandee") in ("transmise", "commandee")
            and (d.get("statut") in ("validee", "transmise", "commandee", "partiellement_recue", "recue") or (d.get("urgent") is True and d.get("statut") == "soumise"))
            and all(k in CHAMPS_COMMANDE for k in pa))


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


# Lot S1 (miroir de supabase/stabilite_s1.sql) : version minimale de l'appli, fusion des listes élément par élément.
REGLAGES = {"version_minimale": "v0"}   # POST /test/version_minimale {"valeur": "v39"}


def version_num(v):
    d = "".join(c for c in str(v or "") if c.isdigit())
    return int(d) if d else 0


def s1_cle(e):
    if isinstance(e, dict):
        return None if e.get("id") is None else str(e["id"])
    if e is None or isinstance(e, list):
        return None
    return ("true" if e else "false") if isinstance(e, bool) else str(e)


def s1_fusionnable(a):
    return isinstance(a, list) and all(s1_cle(x) is not None for x in a)


def s1_fusion_listes(d, pa, listes):
    """Seuls les éléments ajoutés ou modifiés (listes[champ].modifies) remplacent ceux du serveur ; retraits retirés.
    Sans description (ancienne appli) : tout ce qui est envoyé compte comme modifié, rien n'est retiré."""
    if not d:
        return pa
    out = dict(pa)
    for k, b in pa.items():
        a = d.get(k)
        if not (s1_fusionnable(a) and s1_fusionnable(b)):
            continue
        m = (listes or {}).get(k) if isinstance((listes or {}).get(k), dict) else {}
        rem = {str(x) for x in (m.get("retraits") or [])}
        mod = {str(x) for x in m["modifies"]} if isinstance(m.get("modifies"), list) else {s1_cle(x) for x in b}
        parcle = {}
        for x in b:
            parcle.setdefault(s1_cle(x), x)
        res, vus = [], set()
        for e in a:
            c = s1_cle(e)
            if c in vus:
                continue
            vus.add(c)
            if c in rem:
                continue
            res.append(parcle[c] if c in mod and c in parcle else e)
        for e in b:
            c = s1_cle(e)
            if c in vus or c in rem or c not in mod:
                continue
            vus.add(c)
            res.append(e)
        out[k] = res
    return out


def est_admin_client(email):
    p = PROFILS.get(email)
    return bool(p and p["actif"] and p.get("admin"))


def pid_de(email):
    """Fiche membre du compte (R3 : relier_membre peut la changer)."""
    return PROFILS[email].get("personne") or "p-" + email.split("@")[0]


def ma_societe(email):
    x = fiches.get(pid_de(email))
    return (x and x["type"] == "personnes" and x["entreprise"] == PROFILS[email]["entreprise"] and x["data"].get("societeId")) or None


def ot_a_moi(oid, email):
    o = fiches.get(oid or "")
    soc = ma_societe(email)
    return bool(o and o["type"] == "ots" and o["entreprise"] == PROFILS[email]["entreprise"]
                and (any(i.get("personneId") == pid_de(email) for i in o["data"].get("intervenants") or [])
                     or (soc and o["data"].get("societeId") == soc)))


def prestataire_voit(f, email):
    t, d = f["type"], f["data"]
    if t in ("equipements", "localisations", "personnes", "articles", "compteurs", "releves", "parametres", "journal", "equipes"):
        return True
    if t == "fournisseurs":
        return f["id"] == ma_societe(email)   # R3 : sa société seulement
    if t == "ots":
        return ot_a_moi(f["id"], email)
    if t == "demandes":
        return f.get("auteur") == email or any(ot_a_moi(o["id"], email) and f["id"] in (o["data"].get("demandeIds") or []) for o in fiches.values() if o["type"] == "ots")
    if t in ("besoins", "mouvements"):
        return ot_a_moi(d.get("otId"), email)
    if t == "programmes":
        return any(o["type"] == "ots" and o["data"].get("programmeId") == f["id"] and ot_a_moi(o["id"], email) for o in fiches.values())
    if t == "photos":
        x = fiches.get(d.get("parentId") or "")
        return bool(x and x["type"] != "photos" and prestataire_voit(x, email))
    return False


def journal_visible(f, email):
    if role_de(email) in ("responsable", "pilote") or est_admin_client(email) or f.get("auteur") == email:
        return True
    x = fiches.get(f["data"].get("entiteId") or "")
    if not x:
        return False
    if x.get("auteur") == email:
        return True
    if x["type"] == "ots":
        return ot_a_moi(x["id"], email)
    if x["type"] in ("besoins", "mouvements"):
        return ot_a_moi(x["data"].get("otId"), email)
    if x["type"] == "demandes":
        return any(o["type"] == "ots" and x["id"] in (o["data"].get("demandeIds") or []) and ot_a_moi(o["id"], email) for o in fiches.values())
    return False


def visible(f, email):
    p = PROFILS[email]
    cout = (f["type"] in COUTS or (f["type"] == "journal" and f["data"].get("entite") in COUTS)
            or (f["type"] == "photos" and f["data"].get("parentType") == "factures_energie"))
    return (f["entreprise"] == p["entreprise"] and (f["site"] is None or f["site"] in mes_sites(email)) and (not cout or p["role"] in VOIT_COUTS)
            and (p["role"] != "prestataire" or prestataire_voit(f, email))
            and (f["type"] != "journal" or journal_visible(f, email)))


def r2_qualif_terrain(pa, d, nouvelle):
    """R2 (miroir de supabase/interventions_r2.sql) : nature / priorité écrites par le terrain = proposition."""
    if nouvelle and pa.get("programmeId"):
        return pa
    q = dict(pa)
    for champ, prop in (("nature", "natureProposee"), ("priorite", "prioriteProposee")):
        if champ in pa and pa[champ] != ((d or {}).get(champ) or "a_qualifier"):
            del q[champ]
            q[prop], q["qualificationValidee"] = pa[champ], False
            if nouvelle:
                q[champ] = "a_qualifier"
    return q


def r2_arret_incomplet(d):
    if d.get("avecArret") != "oui" or "arretType" not in d:
        return False
    nat = (d.get("natureProposee") or d.get("nature")) if d.get("qualificationValidee") is False else d.get("nature")
    typ = d.get("arretType") or ("planifie" if nat in ("preventive", "travaux_techniques") else "non_planifie")
    return typ == "non_planifie" and not d.get("arretFin") and d.get("arretHeuresInconnues") is not True


def prestataire_refus(t, fid, pa, email):
    x = fiches.get(fid)
    if t == "ots":
        if not x:
            return "un prestataire ne crée pas d'intervention : signalez, le responsable vous la confie"
        if not ot_a_moi(fid, email):
            return "intervention qui ne vous est pas confiée"
    elif t in ("besoins", "mouvements"):
        if not ot_a_moi(pa.get("otId") or (x and x["data"].get("otId")), email):
            return "pièce hors de vos interventions"
    elif t == "demandes":
        if x and x.get("auteur") != email:
            return "demande qui n'est pas la vôtre"
    elif t == "journal":
        if pa.get("entite") == "ots" and pa.get("entiteId") in fiches and not ot_a_moi(pa.get("entiteId"), email):
            return "intervention qui ne vous est pas confiée"
    return None


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


def fichier_autorise(email, nom, ecrire):
    """Miroir de public.fichier_autorise : <entreprise>/<site|commun>/<photos|documents|couts>/<id>.<ext>."""
    r, p = role_de(email), PROFILS.get(email)
    d = nom.split("/")
    if not r or not p or len(d) != 4 or d[0] != ENTREPRISES[p["entreprise"]]["id"]:
        return False
    if d[2] not in ("photos", "documents", "couts") or (d[2] == "couts" and r not in VOIT_COUTS):
        return False
    if d[1] != "commun" and d[1] not in mes_sites(email):
        return False
    if ecrire and (r == "pilote" or not droits(p["entreprise"])["ecriture"] or not re.match(r"^[A-Za-z0-9_-]{6,80}\.(jpg|jpeg|png|webp|pdf)$", d[3])):
        return False
    return True


def nouvelle_session(email, niveau="aal1"):
    a, r = secrets.token_hex(16), secrets.token_hex(16)
    jetons[a] = (email, time.time() + 3600)
    rafraichis[r] = email
    NIVEAU[a], RAFR_NIVEAU[r] = niveau, niveau
    return {"access_token": a, "refresh_token": r, "expires_in": 3600, "user": {"id": "u-" + email, "email": email}}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "apikey, authorization, content-type, x-upsert, cache-control")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")

    def repondre(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def reseau_coupe(self):
        """True si la requête doit être « perdue » (simulation de panne) ; applique aussi la lenteur."""
        if urlparse(self.path).path.startswith("/test/reseau"):
            return False
        RESEAU["requetes"] += 1
        m = RESEAU["mode"]
        if m == "panne" or (m == "coupures" and (RESEAU.__setitem__("n", RESEAU["n"] + 1) or RESEAU["n"] % 2)):
            self.close_connection = True
            try:
                self.connection.shutdown(2)
            except Exception:
                pass
            return True
        if m == "lent":
            time.sleep(RESEAU["delai"])
        if m == "portail":   # portail Wi-Fi d'hôtel : une page HTML à la place de l'API
            corps = b"<html><body>Connectez-vous au Wi-Fi</body></html>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(corps)))
            self.end_headers()
            self.wfile.write(corps)
            return True
        return False

    def do_DELETE(self):
        if self.reseau_coupe():
            return
        email = self.utilisateur()
        if not email:
            return self.repondre(401, {"message": "JWT expired"})
        m = re.match(r"^/auth/v1/factors/([^/]+)$", urlparse(self.path).path)
        if not m:
            return self.repondre(404, {"message": "Not found"})
        f = next((x for x in FACTEURS.get(email, []) if x["id"] == m.group(1)), None)
        if f and f["status"] == "verified" and self.niveau() != "aal2":
            return self.repondre(403, {"msg": "AAL2 required"})
        FACTEURS[email] = [x for x in FACTEURS.get(email, []) if x["id"] != m.group(1)]
        return self.repondre(200, {"id": m.group(1)})

    def do_OPTIONS(self):
        if self.reseau_coupe():
            return
        self.send_response(204)
        self.cors()
        self.end_headers()

    def corps(self):
        RESEAU["octets_max"] = max(RESEAU["octets_max"], int(self.headers.get("Content-Length") or 0))
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def niveau(self):
        return NIVEAU.get((self.headers.get("Authorization") or "").removeprefix("Bearer "), "aal1")

    def est_admin(self, email):
        return email in ADMINS and (not ADMIN_MFA.get(email, True) or self.niveau() == "aal2")

    def utilisateur(self):
        if self.headers.get("apikey") != CLE:
            return None
        tok = (self.headers.get("Authorization") or "").removeprefix("Bearer ")
        e = jetons.get(tok)
        return e[0] if e and e[1] > time.time() else None

    # ---------- POST ----------
    def service(self):
        """Appel avec la clé secrète du projet (sauvegarde) : tous les droits sur l'espace « fichiers »."""
        return self.headers.get("apikey") == CLE_SERVICE and self.headers.get("Authorization") == "Bearer " + CLE_SERVICE

    def do_POST(self):
        if self.reseau_coupe():
            return
        u = urlparse(self.path)
        if self.service() and u.path == "/storage/v1/object/list/fichiers":
            b = self.corps()
            pre = (b.get("prefix") or "").strip("/")
            enfants = {}
            for nom in sorted(FICHIERS):
                if pre and not nom.startswith(pre + "/"):
                    continue
                reste = nom[len(pre) + 1:] if pre else nom
                tete, _, suite = reste.partition("/")
                enfants[tete] = {"name": tete, "id": None if suite else "f-" + nom}
            lot = list(enfants.values())[int(b.get("offset") or 0):][:int(b.get("limit") or 100)]
            return self.repondre(200, lot)
        if self.service() and u.path.startswith("/storage/v1/object/fichiers/"):
            nom = unquote(u.path.removeprefix("/storage/v1/object/fichiers/"))
            octets = self.rfile.read(int(self.headers.get("Content-Length") or 0))
            if nom in FICHIERS:
                return self.repondre(400, {"statusCode": "409", "error": "Duplicate", "message": "The resource already exists"})
            FICHIERS[nom] = (octets, self.headers.get("Content-Type"))
            return self.repondre(200, {"Key": "fichiers/" + nom})
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
                return self.repondre(200, nouvelle_session(rafraichis.pop(b["refresh_token"]), RAFR_NIVEAU.pop(b["refresh_token"], "aal1")))
            return self.repondre(400, {"error_description": "Invalid refresh token"})
        if u.path == "/auth/v1/recover":
            if self.headers.get("apikey") != CLE:
                return self.repondre(401, {"message": "Invalid API key"})
            ENVOIS.append({"email": self.corps().get("email"), "redirect_to": parse_qs(u.query).get("redirect_to", [""])[0]})
            return self.repondre(200, {})
        if u.path == "/test/version_minimale":
            REGLAGES["version_minimale"] = self.corps().get("valeur") or "v0"
            return self.repondre(200, REGLAGES)
        if u.path == "/test/reseau":
            b = self.corps()
            RESEAU.update({k: b[k] for k in ("mode", "delai") if k in b})
            if b.get("raz"):
                RESEAU.update({"octets_max": 0, "requetes": 0})
            return self.repondre(200, RESEAU)
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
        if u.path.startswith("/storage/v1/object/fichiers/"):
            nom = u.path.removeprefix("/storage/v1/object/fichiers/")
            n = int(self.headers.get("Content-Length") or 0)
            octets = self.rfile.read(n)
            RESEAU["octets_max"] = max(RESEAU["octets_max"], n)
            if not fichier_autorise(email, nom, True):
                return self.repondre(400, {"statusCode": "403", "error": "Unauthorized", "message": "new row violates row-level security policy"})
            if n > 10485760 or self.headers.get("Content-Type") not in ("image/jpeg", "image/png", "image/webp", "application/pdf"):
                return self.repondre(400, {"statusCode": "415", "error": "invalid_mime_type", "message": "Type ou taille refusé"})
            if nom in FICHIERS:
                return self.repondre(400, {"statusCode": "409", "error": "Duplicate", "message": "The resource already exists"})
            FICHIERS[nom] = (octets, self.headers.get("Content-Type"))
            return self.repondre(200, {"Key": "fichiers/" + nom})
        if u.path == "/rest/v1/rpc/push_fiches":
            return self.push(email)
        if u.path == "/rest/v1/rpc/mes_annonces":
            p = PROFILS.get(email)
            ent = p and ENTREPRISES[p["entreprise"]]["id"]
            now = time.strftime("%Y-%m-%dT%H:%M:%S")
            return self.repondre(200, [{"id": a["id"], "titre": a["titre"], "texte": a["texte"], "niveau": a["niveau"]} for a in ANNONCES.values()
                                       if a["actif"] and (a["debut"] or "") <= now and (not a["fin"] or a["fin"] > now) and a["entrepriseId"] in (None, ent)])
        if u.path == "/rest/v1/rpc/support_creer":
            b, p = self.corps(), PROFILS.get(email)
            if not p:
                return self.repondre(403, {"message": "Compte sans entreprise"})
            if b.get("p_nature") not in ("question", "anomalie", "evolution", "facturation") or not (b.get("p_sujet") or "").strip() or not (b.get("p_message") or "").strip():
                return self.repondre(400, {"message": "Sujet et message obligatoires"})
            NUM_TICKET[0] += 1
            ref = f"SUP-{NUM_TICKET[0]:04d}"
            i = "ticket-" + secrets.token_hex(8)
            OBJETS[i] = {"id": i, "type": "ticket", "entrepriseId": ENTREPRISES[p["entreprise"]]["id"], "creeLe": time.strftime("%Y-%m-%dT%H:%M:%S"),
                         "data": {"ref": ref, "nature": b["p_nature"], "sujet": b["p_sujet"].strip(), "description": b["p_message"].strip(), "statut": "ouverte", "priorite": "normale",
                                  "source": "appli", "demandeur": {"nom": p["nom"], "email": email, "role": p["role"]}}}
            return self.repondre(200, {"ref": ref})
        if u.path == "/auth/v1/factors":
            sec = base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")
            f = {"id": "f-" + secrets.token_hex(6), "secret": sec, "status": "unverified", "friendly_name": self.corps().get("friendly_name")}
            FACTEURS.setdefault(email, []).append(f)
            return self.repondre(200, {"id": f["id"], "type": "totp", "friendly_name": f["friendly_name"],
                                       "totp": {"qr_code": "", "secret": sec, "uri": f"otpauth://totp/Perfora:{email}?secret={sec}&issuer=Perfora"}})
        m = re.match(r"^/auth/v1/factors/([^/]+)/(challenge|verify)$", u.path)
        if m:
            f = next((x for x in FACTEURS.get(email, []) if x["id"] == m.group(1)), None)
            if not f:
                return self.repondre(404, {"code": "mfa_factor_not_found", "msg": "Factor not found"})
            if m.group(2) == "challenge":
                d = "c-" + secrets.token_hex(6)
                DEFIS[d] = f["id"]
                return self.repondre(200, {"id": d, "type": "totp", "expires_at": int(time.time()) + 300})
            b = self.corps()
            if DEFIS.pop(b.get("challenge_id"), None) != f["id"]:
                return self.repondre(422, {"code": "mfa_challenge_expired", "msg": "Challenge expired"})
            if str(b.get("code")) not in [totp(f["secret"], time.time() + k * 30) for k in (-1, 0, 1)]:
                return self.repondre(422, {"code": "mfa_verification_failed", "msg": "Invalid TOTP code entered"})
            f["status"] = "verified"
            return self.repondre(200, nouvelle_session(email, "aal2"))
        if u.path == "/rest/v1/rpc/erreurs_signaler":
            for x in (self.corps().get("p_erreurs") or [])[:20]:
                msg = str(x.get("message") or "")[:300]
                ex = next((e for e in ERREURS if e["email"] == email and e["message"] == msg and e["nature"] == x.get("nature")), None)
                if ex:
                    ex["nb"] += int(x.get("nb") or 1); ex["dernierLe"] = time.strftime("%Y-%m-%dT%H:%M:%S")
                else:
                    ERREURS.append({"id": len(ERREURS) + 1, "email": email, "nature": x.get("nature") or "erreur", "message": msg, "detail": str(x.get("detail") or "")[:1500],
                                    "page": x.get("page"), "version": x.get("version"), "appareil": x.get("appareil"), "nb": int(x.get("nb") or 1),
                                    "premierLe": time.strftime("%Y-%m-%dT%H:%M:%S"), "dernierLe": time.strftime("%Y-%m-%dT%H:%M:%S")})
            return self.repondre(200, 1)
        if u.path == "/rest/v1/rpc/mon_profil":
            return self.mon_profil(email)
        if u.path == "/rest/v1/rpc/definir_profil":
            return self.definir_profil(email)
        if u.path.startswith("/rest/v1/rpc/pf_"):
            return self.plateforme(email, u.path.removeprefix("/rest/v1/rpc/"))
        moi = PROFILS[email]
        if u.path == "/rest/v1/rpc/definir_admin_client":
            if not est_admin_client(email):
                return self.repondre(403, {"message": "Réservé à l'administrateur de l'entreprise"})
            b = self.corps()
            cible = b["cible"].removeprefix("u-")
            if cible not in PROFILS or PROFILS[cible]["entreprise"] != PROFILS[email]["entreprise"]:
                return self.repondre(403, {"message": "Compte hors de votre entreprise"})
            if not b.get("valeur") and not any(e != cible and q.get("admin") and q["actif"] and q["entreprise"] == PROFILS[email]["entreprise"] for e, q in PROFILS.items()):
                return self.repondre(400, {"message": "L'entreprise doit garder au moins un administrateur"})
            PROFILS[cible]["admin"] = bool(b.get("valeur"))
            return self.repondre(200, None)
        if u.path == "/rest/v1/rpc/appareil_code":   # S2 (miroir de supabase/stabilite_s2.sql)
            b = self.corps()
            ent, app, code = PROFILS[email]["entreprise"], str(b.get("p_appareil") or ""), b.get("p_code")
            if not app or len(app) > 64:
                return self.repondre(400, {"message": "Appareil inconnu"})
            with verrou:
                deja = next((c for (e, c), a in APPAREILS.items() if e == ent and a == app), None)
                if deja:
                    return self.repondre(200, deja)
                if isinstance(code, str) and _re.match(r"^[A-Z0-9]{2,4}$", code) and (ent, code) not in APPAREILS:
                    APPAREILS[(ent, code)] = app
                    return self.repondre(200, code)
                import random
                for i in range(200):
                    c = "".join(random.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(2 if i < 100 else 3))
                    if (ent, c) not in APPAREILS:
                        APPAREILS[(ent, c)] = app
                        return self.repondre(200, c)
            return self.repondre(400, {"message": "Aucun code appareil libre"})
        if u.path == "/rest/v1/rpc/relier_membre":   # R3 (miroir de supabase/membres_r3.sql)
            if not est_admin_client(email):
                return self.repondre(403, {"message": "Réservé à l'administrateur de l'entreprise"})
            b = self.corps()
            cible, pers = b["cible"].removeprefix("u-"), b.get("personne")
            ent = PROFILS[email]["entreprise"]
            if cible not in PROFILS or PROFILS[cible]["entreprise"] != ent:
                return self.repondre(403, {"message": "Compte hors de votre entreprise"})
            x = fiches.get(pers or "")
            if not (x and x["type"] == "personnes" and x["entreprise"] == ent):
                return self.repondre(400, {"message": "Membre inconnu de l'entreprise"})
            if any(e != cible and pid_de(e) == pers for e in PROFILS):
                return self.repondre(400, {"message": "Ce membre a déjà un autre accès"})
            ancien = pid_de(cible)
            with verrou:
                PROFILS[cible]["personne"] = pers
                PROFILS[cible]["nom"] = (x["data"].get("nom") or "").strip() or PROFILS[cible]["nom"]
                seq[0] += 1
                x["data"].update({"role": PROFILS[cible]["role"], "email": cible, "actif": True})
                x["seq"] = seq[0]
                if ancien != pers and ancien in fiches:
                    seq[0] += 1
                    fiches[ancien]["data"].update({"actif": False, "remplaceePar": pers})
                    fiches[ancien]["seq"] = seq[0]
            return self.repondre(200, None)
        if u.path == "/rest/v1/rpc/affecter_sites" and not est_admin_client(email):
            return self.repondre(403, {"message": "Réservé à l'administrateur de l'entreprise"})
        if u.path == "/rest/v1/rpc/utilisation" and not (est_admin_client(email) or role_de(email) == "responsable"):
            return self.repondre(403, {"message": "Réservé à l'administrateur de l'entreprise"})
        if False:
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
            if not b.get("entrepriseId") and not est_admin_client(email):
                return self.repondre(400, {"erreur": "Réservé à l'administrateur de l'entreprise"})
            if b.get("entrepriseId"):   # invitation par l'administrateur plateforme pour un client
                if not self.est_admin(email):
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
        gere = r == "responsable" or est_admin_client(email)   # R3 : membres, équipes, sociétés prestataires
        corps = self.corps()
        if version_num(corps.get("version")) < version_num(REGLAGES["version_minimale"]):   # S1
            return self.repondre(400, {"message": f"Version de l'appli trop ancienne ({corps.get('version') or 'inconnue'}) : rechargez la page pour passer à la version {REGLAGES['version_minimale']} ou plus récente. Vos saisies restent sur l'appareil.", "code": "P0001"})
        with verrou:
            for f in corps.get("lot", []):
                t, pa = f.get("type"), dict(f.get("patch") or {})
                listes = pa.pop("$listes", None)   # S1 : changements de listes décrits par l'appareil
                cible = pa.get("entite") if t == "journal" else t
                ex = fiches.get(f["id"])
                motif, s = None, None
                exd = ex["data"] if ex else {}
                mod = module_compteur(t, pa, ex, ent, module_de(cible))
                if cible == "fournisseurs" and (t == "journal" or pa.get("prestataire", exd.get("prestataire")) is True):
                    mod = "base"   # R3 : société prestataire = module de base
                soi = cible == "personnes" and ((pa.get("entiteId") if t == "journal" else f["id"]) or "") == pid_de(email) \
                    and (t == "journal" or (ex is not None and all(k in ("nom", "telephone", "modifieLe", "modifiePar") for k in pa)))
                lie = t == "personnes" and any(pid_de(e) == f["id"] and q["entreprise"] == ent for e, q in PROFILS.items())
                if t == "ots" and terrain:
                    pa = r2_qualif_terrain(pa, ex and ex["data"], not ex)
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
                elif mod not in dr["modules"]:
                    motif = f"module « {mod} » non inclus dans l'abonnement"
                elif cible in ("personnes", "equipes") and not gere and not soi:
                    motif = "membres et équipes : réservés au responsable et à l'administrateur"
                elif peut_ecrire(r, cible) and r == "prestataire" and prestataire_refus(t, f["id"], pa, email):
                    motif = prestataire_refus(t, f["id"], pa, email)
                elif cible not in ("personnes", "equipes") and not (cible == "fournisseurs" and gere) and not peut_ecrire(r, cible):
                    motif = f"droits insuffisants ({r})"
                elif t == "fournisseurs" and not gere and (pa.get("prestataire") is True or exd.get("prestataire") is True):
                    motif = "société prestataire : réservée au responsable et à l'administrateur"
                elif lie and ex and (("role" in pa and pa["role"] != exd.get("role")) or ("actif" in pa and pa["actif"] is False and exd.get("actif") is not False)):
                    motif = "membre avec un accès : rôle et accès se changent par l'administrateur (Membres)"
                elif t == "ots" and terrain and any(pa.get(k) and pa.get(k) != exd.get(k) for k in ("equipeId", "societeId")):
                    motif = "intervention confiée à une équipe ou une société : réservé au responsable"
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
                elif t == "achats" and (pa.get("urgent", exd.get("urgent")) is True) and not str(pa.get("motifUrgence") or exd.get("motifUrgence") or "").strip():
                    motif = "achat urgent : indiquer le motif (ex. machine à l'arrêt)"
                elif t == "achats" and ex and r in ("achats", "magasinier") and r5_commande_acceptee(r, exd, pa, ent):
                    motif = None
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
                elif t != "journal" and s2_controle(t, pa):   # S2 (G, K)
                    motif = s2_controle(t, pa)
                elif t != "journal" and s2_lien(t, pa, ent, not ex):
                    motif = s2_lien(t, pa, ent, not ex)
                elif t == "ots" and terrain and (pa.get("qualificationValidee") is True or "qualifieePar" in pa or "qualifieeLe" in pa):
                    motif = "validation de la qualification : réservée au responsable"
                elif t == "ots" and terrain and ex and ex["data"].get("qualificationValidee") is True and any(k in pa for k in ("natureProposee", "prioriteProposee", "qualificationValidee")):
                    motif = "qualification déjà validée par le responsable : demandez-lui de la changer"
                elif t == "ots" and pa.get("statut") in ("cloturee", "travail_termine") and (ex and ex["data"].get("statut")) != pa.get("statut")                         and r2_arret_incomplet({**(ex["data"] if ex else {}), **pa}):
                    motif = "arrêt non planifié : indiquer la remise à disposition ou « heures inconnues »"
                elif t == "ots" and r != "responsable" and ex and ex["data"].get("statut") == "cloturee":
                    motif = "intervention clôturée : modification réservée au responsable"
                elif t == "ots" and r != "responsable" and pa.get("statut") == "cloturee" and cloture_par_responsable(ent):
                    motif = "clôture réservée au responsable (réglage de l'entreprise) : terminez l'intervention, le responsable la clôture"
                elif t == "parametres" and f["id"] != "parametres-" + ENTREPRISES[ent]["id"]:
                    motif = "paramètres : identifiant réservé à l'entreprise"
                # intégrité (miroir de supabase/references.sql)
                elif t in ("demandes", "ots", "programmes") and not ex and pa.get("equipementId") and not (
                        (lambda x: x and x["type"] == "equipements" and x["entreprise"] == ent)(fiches.get(pa["equipementId"]))):
                    motif = "équipement inconnu de l'entreprise (créé hors connexion ou supprimé ?)"
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
                if lie and (pa.get("nom") or "").strip():   # R3 : le nom d'un membre avec accès est aussi celui de son compte
                    for e, q in PROFILS.items():
                        if pid_de(e) == f["id"]:
                            q["nom"] = pa["nom"].strip()
                if ex and t in APPEND_ONLY and t != "mouvements":
                    continue
                seq[0] += 1
                if ex and t not in APPEND_ONLY:
                    pa = s1_fusion_listes(ex["data"], pa, listes)
                data = {**(ex["data"] if ex else {}), **pa, **({"siteId": s} if s else {})}
                fiches[f["id"]] = {"id": f["id"], "type": t, "data": data, "seq": seq[0], "entreprise": ent, "site": s, "auteur": ex.get("auteur", email) if ex else email}
                if t == "achats":   # R5 : résumé sans prix recopié sur les pièces liées
                    r5_suivi_besoins(f["id"], ent)
        return self.repondre(200, {"acceptes": acceptes, "refuses": refus})

    def plateforme(self, email, nom):
        if nom == "pf_mfa_activer":
            if email not in ADMINS or self.niveau() != "aal2":
                return self.repondre(400, {"message": "Confirmez d'abord un code de l'application d'authentification"})
            ADMIN_MFA[email] = True
            return self.repondre(200, {"mfaObligatoire": True})
        if not self.est_admin(email):
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
        if nom == "pf_clients":
            out = []
            for c, e in sorted(ENTREPRISES.items(), key=lambda x: x[1]["nom"]):
                d = droits(c)
                recus = [f for f in fiches.values() if f["entreprise"] == c and not f["data"].get("lotImport")]
                out.append({"id": e["id"], "code": c, "nom": e["nom"], "statut": e["statut"], "demo": e.get("demo", False),
                            "abonnement": {**d, "debut": e.get("debut", "2026-11-01"), "prix": e.get("prix"), "periodicite": e.get("periodicite", "mensuel"),
                                           "remisePct": e.get("remisePct", 0), "conditions": e.get("conditions"), "statutAbonnement": e["statut"], "derogations": e.get("derog", {})},
                            "actifs": actifs_entreprise(c),
                            "sites": [{"id": k, "code": v["code"], "nom": v["nom"], "actif": True} for k, v in SITES.items() if v["entreprise"] == c],
                            "responsables": sorted(m for m, pp in PROFILS.items() if pp["entreprise"] == c and pp["role"] == "responsable" and pp["actif"]),
                            "fiches": sum(1 for f in fiches.values() if f["entreprise"] == c), "activite7j": len(recus),
                            "derniereActivite": e.get("derniereActivite") or (time.strftime("%Y-%m-%dT%H:%M:%S") if recus else None),
                            "miseEnService": ETAPES.get(c), "fiche": FICHES_CLIENT.get(c)})
            return self.repondre(200, out)
        if nom == "pf_tarifs_lire":
            return self.repondre(200, [{"pack": k, "packNom": v["nom"], "modules": v["modules"], "maxSites": v["maxSites"], "maxUtilisateursSite": v["maxUtilisateursSite"],
                                        "maxUtilisateursTotal": v["maxUtilisateursTotal"], "prixMensuel": TARIFS[k].get("m"), "prixAnnuel": TARIFS[k].get("a"), "note": TARIFS[k].get("n")}
                                       for k, v in PACKS.items()])
        if nom == "pf_tarif_maj":
            if b.get("p_pack") not in TARIFS:
                return self.repondre(400, {"message": "Pack inconnu"})
            TARIFS[b["p_pack"]] = {"m": b.get("p_prix_mensuel"), "a": b.get("p_prix_annuel"), "n": b.get("p_note")}
            return self.repondre(200, None)
        if nom == "pf_objets_lire":
            t = b.get("p_type")
            if t not in ("prospect", "ticket", "echange", "modele"):
                return self.repondre(400, {"message": "Type inconnu"})
            l = sorted((o for o in OBJETS.values() if o["type"] == t), key=lambda o: o["creeLe"], reverse=True)
            return self.repondre(200, [{"id": o["id"], "type": o["type"], "entrepriseId": o["entrepriseId"], "creeLe": o["creeLe"], **o["data"]} for o in l])
        if nom == "pf_objet_enregistrer":
            t, d, ent, i = b.get("p_type"), dict(b.get("p_data") or {}), b.get("p_entreprise"), b.get("p_id")
            for k in ("id", "type", "entrepriseId", "creeLe", "majLe"):
                d.pop(k, None)
            ex = OBJETS.get(i) if i else None
            err = None
            if t not in ("prospect", "ticket", "echange", "modele"):
                err = "Type inconnu"
            elif t == "prospect" and not (d.get("nom") or d.get("societe")):
                err = "Prospect : nom ou société obligatoire"
            elif t == "prospect" and d.get("etape") == "perdu" and not d.get("motifPerte"):
                err = "Prospect perdu : motif obligatoire"
            elif t == "ticket" and (not ent or not d.get("sujet")):
                err = "Demande de support : client et sujet obligatoires"
            elif t == "echange" and (d.get("canal") not in ("whatsapp", "email", "telephone", "rencontre", "autre") or not d.get("resume") or not (ent or d.get("prospectId"))):
                err = "Échange incomplet"
            elif t == "echange" and ex:
                err = "Un échange noté ne se modifie pas : ajoutez-en un autre"
            elif t == "modele" and not (d.get("nom") and d.get("texte")):
                err = "Modèle : nom et texte obligatoires"
            if err:
                return self.repondre(400, {"message": err})
            if t == "ticket":
                if ex:
                    d["ref"] = ex["data"]["ref"]
                else:
                    NUM_TICKET[0] += 1
                    d["ref"] = f"SUP-{NUM_TICKET[0]:04d}"
            i = i or f"{t}-{secrets.token_hex(8)}"
            OBJETS[i] = {"id": i, "type": t, "entrepriseId": ent, "creeLe": ex["creeLe"] if ex else time.strftime("%Y-%m-%dT%H:%M:%S"), "data": d}
            return self.repondre(200, {"id": i, "type": t, "entrepriseId": ent, "creeLe": OBJETS[i]["creeLe"], **d})
        if nom == "pf_objet_supprimer":
            o = OBJETS.get(b.get("p_id"))
            if not o or o["type"] not in ("modele", "prospect"):
                return self.repondre(400, {"message": "Seuls un modèle ou un prospect se suppriment"})
            if o["type"] == "prospect":
                for k in [k for k, x in OBJETS.items() if x["type"] == "echange" and x["data"].get("prospectId") == o["id"]]:
                    del OBJETS[k]
            del OBJETS[o["id"]]
            return self.repondre(200, None)
        if nom == "pf_erreurs_lire":
            return self.repondre(200, [{**e, "entreprise": ENTREPRISES[PROFILS[e["email"]]["entreprise"]]["nom"] if e["email"] in PROFILS else None,
                                        "role": PROFILS.get(e["email"], {}).get("role")} for e in reversed(ERREURS)])
        if nom == "pf_journal_admin_lire":
            return self.repondre(200, list(reversed(JOURNAL))[:int(b.get("p_limite") or 200)])
        if nom == "pf_stockage":
            par = {}
            for n_, (o, _) in FICHIERS.items():
                par[n_.split("/")[0]] = par.get(n_.split("/")[0], 0) + len(o)
            return self.repondre(200, {"total": sum(par.values()), "parEntreprise": par, "base": 12 * 1048576})
        if nom == "pf_annonces_lire":
            return self.repondre(200, sorted(ANNONCES.values(), key=lambda a: a["creeLe"], reverse=True))
        if nom == "pf_annonce_enregistrer":
            if not (b.get("p_titre") or "").strip() or not (b.get("p_texte") or "").strip():
                return self.repondre(400, {"message": "Titre et texte obligatoires"})
            i = b.get("p_id") or secrets.token_hex(8)
            ANNONCES[i] = {"id": i, "titre": b["p_titre"].strip(), "texte": b["p_texte"].strip(), "niveau": b.get("p_niveau") or "info", "entrepriseId": b.get("p_entreprise"),
                           "debut": b.get("p_debut") or time.strftime("%Y-%m-%dT%H:%M:%S"), "fin": b.get("p_fin"), "actif": b.get("p_actif") is not False,
                           "creeLe": ANNONCES.get(i, {}).get("creeLe") or time.strftime("%Y-%m-%dT%H:%M:%S")}
            return self.repondre(200, i)
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
        if nom == "pf_client_maj":
            dd = b.get("p_data") or {}
            if dd.get("ice") and not re.match(r"^[0-9]{15}$", dd["ice"]):
                return self.repondre(400, {"message": "ICE : 15 chiffres"})
            FICHES_CLIENT[code] = dd
            return self.repondre(200, dd)
        if nom == "pf_abonnement_conditions":
            if b.get("p_periodicite") not in ("mensuel", "annuel"):
                return self.repondre(400, {"message": "Périodicité : mensuel ou annuel"})
            if b.get("p_prix") is not None and b["p_prix"] < 0:
                return self.repondre(400, {"message": "Prix négatif"})
            e.update({"prix": b.get("p_prix"), "periodicite": b["p_periodicite"], "remisePct": b.get("p_remise") or 0, "conditions": b.get("p_conditions")})
            if b.get("p_debut"):
                e["debut"] = b["p_debut"]
            return self.repondre(200, None)
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
        pid = pid_de(email)
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
                                   "siteDefaut": p["defaut"], "abonnement": droits(p["entreprise"]), "adminPlateforme": self.est_admin(email), "adminClient": est_admin_client(email),
                                   "adminMfa": {"obligatoire": ADMIN_MFA.get(email, True), "niveau": self.niveau()} if email in ADMINS else None})

    def definir_profil(self, email):
        if not est_admin_client(email):
            return self.repondre(403, {"message": "Réservé à l'administrateur de l'entreprise"})
        b = self.corps()
        cible = b["cible"].removeprefix("u-")
        if cible not in PROFILS or PROFILS[cible]["entreprise"] != PROFILS[email]["entreprise"]:
            return self.repondre(403, {"message": "Compte hors de votre entreprise"})
        if b.get("est_actif", True) and not PROFILS[cible]["actif"]:
            q = controle_quota(PROFILS[cible]["entreprise"], PROFILS[cible]["sites"], sauf=cible)
            if q:
                return self.repondre(400, {"message": q})
        PROFILS[cible].update({"role": b.get("nouveau_role") or PROFILS[cible]["role"], "nom": b.get("nouveau_nom") or PROFILS[cible]["nom"], "actif": b.get("est_actif", True)})
        pid = pid_de(cible)
        with verrou:
            if pid in fiches:   # R3 : nom et rôle suivent le compte ; retirer l'accès ne rend pas le membre inactif
                seq[0] += 1
                fiches[pid]["data"].update({k: PROFILS[cible][k] for k in ("role", "nom")})
                fiches[pid]["seq"] = seq[0]
        return self.repondre(200, None)

    # ---------- PUT / GET ----------
    def do_PUT(self):
        if self.reseau_coupe():
            return
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
        if self.reseau_coupe():
            return
        u = urlparse(self.path)
        if self.service() and u.path.startswith("/storage/v1/object/authenticated/fichiers/"):
            nom = unquote(u.path.removeprefix("/storage/v1/object/authenticated/fichiers/"))
            if nom not in FICHIERS:
                return self.repondre(400, {"statusCode": "404", "error": "not_found", "message": "Object not found"})
            octets, mime = FICHIERS[nom]
            self.send_response(200)
            self.send_header("Content-Type", mime or "application/octet-stream")
            self.send_header("Content-Length", str(len(octets)))
            self.end_headers()
            self.wfile.write(octets)
            return
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
            return self.repondre(200, {"id": "u-" + email, "email": email, "factors": [{"id": f["id"], "factor_type": "totp", "status": f["status"], "friendly_name": f["friendly_name"]}
                                                                                  for f in FACTEURS.get(email, [])]})
        if u.path.startswith("/storage/v1/object/authenticated/fichiers/"):
            nom = u.path.removeprefix("/storage/v1/object/authenticated/fichiers/")
            if nom not in FICHIERS or not fichier_autorise(email, nom, False):
                return self.repondre(400, {"statusCode": "404", "error": "not_found", "message": "Object not found"})
            octets, mime = FICHIERS[nom]
            self.send_response(200)
            self.cors()
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(octets)))
            self.end_headers()
            self.wfile.write(octets)
            return
        if u.path == "/rest/v1/profils":
            moi = PROFILS[email]
            vis = [(e, p) for e, p in PROFILS.items() if p["entreprise"] == moi["entreprise"]] if role_de(email) == "responsable" or est_admin_client(email) else [(email, moi)]
            return self.repondre(200, [{"user_id": "u-" + e, "email": e, "nom": p["nom"], "role": p["role"], "actif": p["actif"], "personne_id": pid_de(e), "admin_client": bool(p.get("admin"))} for e, p in sorted(vis)])
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
