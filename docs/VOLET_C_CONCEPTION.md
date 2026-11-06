# Volet C — Définition des stocks, réapprovisionnement et achats : proposition de conception

Statut : choix 1 à 7 **validés** le 6 nov. 2026. Travail sur la branche git `volet-c` (publication en C5).
**C1 fait** : `calculs.js` (seuilActif, besoinsNonCouverts, receptionLigne, etatAchat, qteEnCommande, qteIsolee,
situationArticle, aReapprovisionner, prixMAD, valorisation, coutConsomme) + `tests/achats.test.js` (10 tests).
Conventions de mouvements retenues : `entree` = utilisable reçu ; `isolement` (qte 0, quantite N) ; `liberation`
(+N, isolementId) ; `disposition` (qte 0, quantite N, decision). Aucun prix sur les mouvements.
Fiche `valorisations` : { mouvementId, prixUnitaire, devise (MAD par défaut), prixUnitaireMAD si autre devise,
statut connu / provisoire }. Une pièce libérée prend le prix de sa réception (valorisation de l'isolement).
**C2 fait** : `supabase/achats.sql` exécuté sur Supabase (types seuils / achats / valorisations, rôle « achats »,
fonction `voit_couts()`, lecture restreinte des fiches achats / valorisations **et des lignes de journal qui les
concernent**, règles de validation) + `supabase/tests_achats.sql` (21 tests conformes, dont « technicien : 0 prix
lisible »). Non-régression : tests_magasin 16/16, tests_etancheite 12/12.
Règles ajoutées : un seuil validé ne se modifie pas (nouvelle version proposée) ; le magasinier rédige et soumet
une demande d'achat, ne la valide pas, et après validation ne peut que la clore une fois commandée ; le rôle achats
ne crée pas de demande et ne renseigne que la commande (statuts transmise / commandee) d'une demande validée ;
un prix se rattache à une entrée de stock (site hérité) et sa correction est réservée au responsable.
**C3 fait** (v20 locale) : `js/vues/reappro.js` — bloc « Seuils » de la fiche article (repère provisoire, proposition,
valider / refuser, historique, consommation hebdomadaire et seuil indicatif V3), onglet **À réapprovisionner** (par
site ; en « tous les sites », un récapitulatif par site), export CSV (nombres réels, texte protégé), création d'une
demande d'achat en brouillon depuis les lignes cochées (une par site, aucun prix), consultation / modification des
quantités / soumission / annulation de la demande. Stockage local v5. Faux serveur aligné sur `achats.sql` (compte
`achat@` rôle achats ; `POST /test/abonnement {"entreprise":"DEMO","pack":"entreprise"}`).

**C5 fait** : démo enrichie (`supabase/demo.sql`), guide, publication v20 — **volet C terminé**.
**C4 fait** : `js/vues/achats.js` — écran **Achats** (menu Plus : à valider, à commander, à réceptionner,
brouillons, terminées ; pièces isolées en attente), détail d'une demande (valider / à compléter / refuser ; commande
externe saisie par le rôle achats ou le responsable : fournisseur, référence, dates, devise et taux explicites, quantité
commandée et prix par ligne ; réception partielle avec isolé et bon de livraison ; clôture, motif obligatoire s'il reste
un reliquat), décisions sur pièces isolées (libérer, retour fournisseur, rebut, réparation), **Valeur du stock** (CUMP
par article et site, quantités sans prix montrées « non valorisé »), accueil du rôle achats, prix facultatif à la
réception manuelle. Calculs ajoutés : `montantCommande`, `isolementsEnAttente` (50 tests).

## 5 quater. Décisions prises en C3

- Le récapitulatif reste visible des techniciens (aucun prix) ; les demandes d'achat ne leur parviennent jamais.
- Un seuil se définit sur un site précis ; le responsable peut « Valider maintenant » sa propre saisie ; contrôle
  sécurité ≤ point de commande ≤ cible ; justification obligatoire (motif de révision V3 §14).
- Seuil indicatif = consommation hebdomadaire (90 j, retours déduits) × délai + sécurité, simple aide (V3 §14).
- Correction en passant : charger la démo sur un appareil connecté ne change plus la signature (elle reste celle du compte).

## 5 quinquies. Décisions prises en C4

- La réception crée l'entrée (utilisable) et l'isolement ; le prix de la ligne de commande est copié dans une fiche
  `valorisations` pour chacun (une pièce libérée prend ainsi le prix de sa réception).
- Prix en devise étrangère : valorisés seulement si un taux est saisi (`prixUnitaireMAD`), sinon « non valorisé ».
- Clôture avec reliquat : motif obligatoire ; une demande close ne compte plus « en commande ».
- Réception au-delà du reste attendu : refusée à l'écran (sur-livraison à traiter hors commande).
- Valeur du stock : un article sans aucun prix affiche « non valorisé », jamais 0,00 MAD.
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
