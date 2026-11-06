# Discussion à tenir : modèle de données (magasin, achats, compteurs)

Demandée le 6 nov. 2026, après D2. Objet : valider ce qui existe et décider des évolutions **avant** les écrans
compteurs (D3), pour ne pas devoir migrer des données plus tard.

## 1. Magasin (en place, volets B et C)

| Fiche | Rôle | Règle clé |
|---|---|---|
| Article | catalogue, commun à l'entreprise | réf., désignation, unité |
| Mouvement | entrée, remise, retour, sortie, rebut, ajustement, isolement… par site | jamais modifié ; le stock est **calculé** à partir des mouvements |
| Besoin | pièce demandée par une intervention | réservé par le magasin ; « remis » déduit des remises |
| Seuil | point de commande / cible par article et par site | proposé par le magasin, validé par le responsable |

Questions à trancher :
1. **Emplacements** dans le magasin (allée, étagère, casier) : utile pour vos clients ?
2. ~~Plusieurs magasins par site~~ — **décidé le 6 nov. 2026 : un seul magasin par site au départ.** Évolution sans
   reprise de données : une fiche « magasin » par site sera ajoutée plus tard ; tout mouvement sans magasin désigné
   appartient au magasin principal du site (les mouvements ne sont jamais réécrits) ; les seuils suivent la même règle ;
   un transfert entre magasins sera un nouveau type de mouvement.
3. **Conditionnement** : acheté par carton de 10, sorti à l'unité ?
4. **Inventaire** : comptage périodique → écart → ajustement motivé (aujourd'hui : ajustement à la main).
5. **Pièces suivies une à une** (numéro de série, pièces réparables qui reviennent en stock) ?
6. **Valorisation du stock** : coût moyen pondéré (CUMP) ou dernier prix connu ?

## 2. Achats (en place, volet C)

Demande d'achat (lignes article ou texte libre) → validation du responsable → commande externe renseignée par les
achats (fournisseur en texte libre) → réception = entrée de stock liée → prix de l'entrée (lecture restreinte).

Questions à trancher :
1. **Fournisseurs en liste** (fiche fournisseur, contacts, délais) plutôt qu'en texte libre ?
2. **Achats non stockés** : prestations, sous-traitance, location, liées directement à une intervention ?
3. **Budget / centres de coût** par site ou par équipement ?
4. **Factures fournisseurs** : à rapprocher des réceptions, ou hors périmètre (comptabilité) ?

## 3. Compteurs : deux familles

| Famille | Exemples | Sert à |
|---|---|---|
| **Ressources** (volet D, en cours) | électricité, eau, gasoil, air comprimé | consommations, factures, écarts |
| **Équipements** (nouveau) | heures de marche, cycles, kilomètres, tonnes produites | **préventif selon l'usage** : « vidange toutes les 500 h » |

Aujourd'hui, le préventif est seulement **calendaire** (tous les N jours, échéance fixe ou après réalisation).

**Décidé le 6 nov. 2026 :**
- **Un seul type de compteur** avec un champ `usage` : `ressource` ou `equipement` (+ `equipementId`). Mêmes relevés,
  ruptures, contrôles et corrections. Un équipement peut avoir les deux (compresseur : kWh et heures).
- **Pack** : le serveur choisit le module selon l'usage : `equipement` → preventif (pack Pro), `ressource` → energie
  (pack Entreprise). L'usage est figé après le premier relevé (comme le mode, l'unité et le coefficient).
- **Relevés des compteurs d'équipement** : fréquence en jours par compteur ; saisis par techniciens, prestataires,
  exploitation (conducteurs de machine).
- **Programme préventif sur compteur** : « toutes les N unités » (ex. 500 h) ; échéance = index de la dernière
  réalisation + N ; **« le premier des deux »** facultatif (ex. 500 h ou 6 mois) ; **alerte par marge en unités du
  compteur** fixée par programme (ex. 50 h avant) ; date **estimée** au rythme des derniers relevés retenus, affichée
  comme estimation.
- **Index noté à la clôture** d'une intervention préventive sur compteur : obligatoire, devient le départ suivant.

Mise en œuvre prévue : D2 bis (serveur : module selon l'usage, usage figé) regroupé avec les éventuels changements
magasin / achats pour une seule mise à jour de Supabase ; calculs (échéance, estimation, alerte) testés ; écrans avec D3.

## 4. Décisions magasin et achats (6 nov. 2026)

Magasin :
1. **Emplacement** : champ texte par article et par site (ex. « A3-02 »), affiché à la remise et à l'inventaire.
2. **Un magasin par site** (voir §1, évolution sans reprise).
3. **Conditionnement** : unité d'achat + contenu (ex. carton de 10) sur la ligne d'achat ; conversion en unités de stock
   à la réception.
4. **Inventaire** (prioritaire) : comptage par lots, écart calculé, ajustement motivé, validation du responsable au-delà
   d'un seuil.
5. **Suivi unitaire** (numéro de série, pièces réparables) : plus tard.
6. **Valorisation** : coût moyen pondéré (CUMP) par site ; entrées sans prix exclues et signalées.

Achats :
1. **Fournisseurs** : liste simple (nom, contact, téléphone, e-mail, délai habituel) ; texte libre toujours possible.
2. **Achats non stockés** (prestation, sous-traitance, location) liés à une intervention ; coût ajouté à l'intervention
   (lecture restreinte).
3. **Budgets / centres de coût** : volet E.
4. **Factures fournisseurs** : hors périmètre ; pièce jointe possible à la réception.

Mise en œuvre : étape « C bis » après le volet D (inventaire avant si un premier client en a besoin).

## 5. Démarrage d'un client (6 nov. 2026)

Kit Excel standard (`kit/Kit_demarrage_Perfora.xlsx`, généré par `scripts/kit_demarrage.py`) rempli par le client ou
avec lui ; import par l'administrateur de la plateforme depuis la page « Mise en service » de la console — **faite
(v25, 6 nov. 2026)**, procédure : [`MISE_EN_SERVICE_CLIENT.md`](MISE_EN_SERVICE_CLIENT.md). D2 bis (module d'un
compteur selon son usage) et type `fournisseurs` faits en même temps. Plus tard : import en libre-service (module
imports, pack Entreprise).
