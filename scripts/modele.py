"""Référence unique du modèle de données (lot S2, risque H) : types de fiches, fiches communes à l'entreprise (sans
site), fiches jamais modifiées, module de chaque type. tests/coherence_modele_test.py vérifie que le SQL, l'appli et le
serveur factice disent la même chose. Nouveau type de fiche : l'ajouter ICI d'abord, puis suivre les écarts signalés
par le test (et relever le périmètre de lecture, docs/AUDIT_STABILITE_MODELE.md §6)."""

TYPES = ["localisations", "equipements", "personnes", "demandes", "ots", "programmes", "articles", "mouvements", "journal",
         "photos", "besoins", "seuils", "achats", "valorisations", "compteurs", "releves", "factures_energie", "parametres",
         "fournisseurs", "equipes"]

# Fiches communes à l'entreprise : pas de site.
SANS_SITE = ["personnes", "articles", "parametres", "fournisseurs", "equipes"]

# Fiches jamais modifiées après création (on corrige par une nouvelle fiche).
APPEND_ONLY = ["journal", "mouvements", "photos"]

# Module d'abonnement requis pour écrire (« base » par défaut). Exceptions décidées ailleurs, non listées ici :
# compteur d'équipement → preventif (D2 bis) ; société prestataire → base (R3).
MODULE = {"articles": "magasin", "mouvements": "magasin", "besoins": "magasin", "seuils": "magasin", "fournisseurs": "magasin",
          "achats": "achats", "valorisations": "achats",
          "compteurs": "energie", "releves": "energie", "factures_energie": "energie",
          "programmes": "preventif"}


def module(t):
    return MODULE.get(t, "base")
