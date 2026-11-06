# Volet C — Définition des stocks, réapprovisionnement et achats : proposition de conception

Statut : choix 1 à 7 **validés** le 6 nov. 2026. Travail sur la branche git `volet-c` (publication en C5).
**C1 fait** : `calculs.js` (seuilActif, besoinsNonCouverts, receptionLigne, etatAchat, qteEnCommande, qteIsolee,
situationArticle, aReapprovisionner, prixMAD, valorisation, coutConsomme) + `tests/achats.test.js` (10 tests).
Conventions de mouvements retenues : `entree` = utilisable reçu ; `isolement` (qte 0, quantite N) ; `liberation`
(+N, isolementId) ; `disposition` (qte 0, quantite N, decision). Aucun prix sur les mouvements.
Fiche `valorisations` : { mouvementId, prixUnitaire, devise (MAD par défaut), prixUnitaireMAD si autre devise,
statut connu / provisoire }. Une pièce libérée prend le prix de sa réception (valorisation de l'isolement).
Références V3 : §14 (seuils proposés et validés), §15-16 (stock explicable, réception partielle, pièces isolées),
§17 (besoins achats : circuit et états), §18 (CUMP, prix manquant, coûts distincts), §24 (rôle Achats facultatif,
prix masqués aux techniciens), §33 (compatibilités et seuils), §37 (scénarios de vérification).
Périmètre V3 : Perfora **n'envoie aucune commande** et ne devient ni ERP achats ni comptabilité. On suit le besoin,
sa validation, la référence de la commande passée ailleurs, le délai et la réception.

## 1. Ce que l'on ajoute

| Fait | Qui | Effet |
|---|---|---|
| **Seuils** d'un article sur un site : sécurité, point de commande, cible, délai de référence, critique, justification | magasinier propose, responsable valide | alimente le récapitulatif ; aucun effet sur le stock |
| **Récapitulatif « à réapprovisionner »** | calculé | propose, ne commande rien |
| **Demande d'achat** (lignes : article ou description, quantité, date souhaitée, motif, origine) | magasinier ou responsable rédige ; responsable valide | aucun effet sur le stock |
| **Commande externe** (fournisseur, référence, date, délai annoncé, prix) | achats ou responsable | « en commande » (pas du stock) |
| **Réception** (reçu, utilisable, isolé, motif ; reliquat déduit) | magasinier | + stock utilisable ; l'isolé est suivi à part |
| **Décision sur isolé** (libérer, retour fournisseur, rebut) | magasinier, responsable | libérer = + stock utilisable |
| **Valorisation** (prix des entrées, CUMP par article et site) | calculé ; prix saisis par achats / magasin | coût des remises et consommations |

## 2. Règles de calcul (dans `calculs.js`, testées)

- **Seuil actif** = dernière version **validée** pour l'article et le site. Le `stockMin` actuel des articles reste
  affiché comme repère provisoire « non validé ».
- **Couverture** = disponible (physique utilisable − réservé) − besoins non encore réservés + en commande (reliquats
  des commandes confirmées). Un besoin couvert par une commande n'est pas compté deux fois.
- **Alerte** quand couverture < point de commande ; **quantité proposée** = cible − couverture (arrondie au-dessus).
  Tri : rupture (disponible ≤ 0) d'abord, puis article critique, puis écart au seuil. Export CSV pour l'acheteur.
- **Réception** : reçu = utilisable + isolé ; reliquat = commandé − reçu ; une commande peut être livrée sans être
  entièrement acceptée. Exemple V3 : 10 commandées, 6 reçues dont 1 endommagée → 5 utilisables, 1 isolée, 4 attendues.
- **CUMP** mobile par article et site, rejoué dans l'ordre des dates : à chaque entrée valorisée,
  `CUMP = (valeur avant + valeur entrée) / (quantité avant + quantité entrée)`. Les réservations ne changent pas le coût.
  Une sortie prend le CUMP du moment ; un retour réintègre sa valeur de sortie. Exemple V3 : 10 à 100 puis 10 à 120 = 110 MAD.
- **Prix inconnu ≠ 0** : la quantité non valorisée est montrée à part, le CUMP est dit « incomplet ». Un prix
  provisoire est possible, avec son statut. Une nouvelle livraison ne réécrit pas les sorties passées.

## 3. Les prix restent invisibles aux techniciens, y compris par l'API

Aujourd'hui, un technicien lit toutes les fiches de son site (articles, mouvements…). Mettre un prix dans un article
ou un mouvement le rendrait lisible par l'API. Proposition : les montants vivent **uniquement** dans deux nouveaux
types de fiches à **lecture restreinte** par le serveur (RLS selon le rôle) :
- `achats` (demandes d'achat, commandes externes, prix commandés) ;
- `valorisations` (prix d'une entrée de stock : montant, devise, statut connu / provisoire).

Lecture : responsable, magasinier, achats, pilote. Jamais technicien, prestataire ni exploitation. Les mouvements de
réception restent lisibles par tous **sans prix** (le technicien voit le stock, pas sa valeur). Test d'étanchéité dédié.

## 4. Serveur (`supabase/achats.sql`)

- Types `seuils` (par site), `achats` (par site), `valorisations` (par site) ; politique de lecture par rôle ci-dessus.
- Rôle facultatif **`achats`** (V3 §24) : lit les demandes validées, renseigne commande, prix et délai ; ne valide pas.
- Validation d'un seuil ou d'une demande d'achat : **responsable uniquement** ; le magasinier propose.
- Technicien / prestataire : aucun accès à ces types (ils continuent de demander des pièces par les besoins du volet B ;
  le magasinier transforme un besoin hors stock en demande d'achat).
- Mouvement de réception lié à la commande (`achatId`, `ligneId`), toujours immuable.

## 5. Écrans

- **Magasin → Stock** : seuils par article (proposer / valider, historique avec auteur et motif).
- **Magasin → À réapprovisionner** : liste triée, quantité proposée, « Créer la demande d'achat » (cases à cocher), export CSV.
- **Achats** (nouvel écran, menu Plus) : demandes par état — brouillon, soumise, à compléter, validée, refusée,
  commandée en externe, partiellement reçue, reçue, close, annulée ; actions selon le rôle.
- **Réception** depuis une commande : reçu, dont isolé (motif, photo possible) ; reliquat affiché. File « Isolés » avec décision.
- **Valeur du stock** (responsable, magasinier, pilote) : par article et site, part non valorisée visible.

## 6. Étapes

| Étape | Contenu | Vérification |
|---|---|---|
| C1 | Calculs : seuil actif, couverture, récapitulatif, reliquats, isolés, CUMP | Tests des scénarios V3 §37 (10 / 6 / 1 ; CUMP 110 ; prix absent) |
| C2 | Serveur : types, lecture restreinte des prix, rôle achats, règles de validation | Tests SQL + étanchéité des prix (technicien ne lit aucun prix) |
| C3 | Seuils et « À réapprovisionner » (+ export CSV, création de demande d'achat) | Navigateur, rôles magasinier et responsable |
| C4 | Circuit achats, réception partielle, isolés, valeur du stock | Navigateur, 3 rôles + technicien sans prix |
| C5 | Faux serveur, démo, guide, recette, publication v20 | — |

## 7. Choix validés (6 nov. 2026)

1. **Modules** : seuils et « À réapprovisionner » dans le module **magasin** (pack Pro) ; demandes d'achat, réceptions
   liées et valorisation dans le module **achats** (pack Entreprise, ou option du Pro).
2. **Prix en fiches à lecture restreinte** (§3) plutôt que sur les articles et mouvements.
3. **Pas de référentiel fournisseurs** dans ce volet : fournisseur en texte libre sur la commande (fiche fournisseur plus tard).
4. **Seuils** : le magasinier propose, le responsable valide ; `stockMin` actuel conservé comme repère provisoire.
5. **Rôle « achats »** facultatif ajouté (compte dans les quotas d'utilisateurs comme les autres).
6. **Monnaie** : MAD hors taxes, prix et devise d'origine conservés, aucune conversion automatique.
7. Restent hors volet C : emplacements détaillés, transferts entre sites, prestations externes, coûts accessoires.
