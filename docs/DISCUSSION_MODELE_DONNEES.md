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
2. **Plusieurs magasins par site** (magasin central + armoire d'atelier) ou un seul par site ?
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

Proposition à discuter :
- **Un seul type de compteur** avec un champ « usage » (ressource ou équipement) et l'équipement mesuré. Les relevés,
  ruptures (remplacement du compteur horaire), contrôles et corrections restent les mêmes. Un compresseur peut avoir les
  deux : compteur kWh (ressource) et compteur horaire (équipement).
- **Programme préventif sur compteur** : « toutes les 500 h » ; échéance = index de la dernière réalisation + 500 ;
  alerte à l'approche (ex. 90 %) ; date estimée à partir du rythme moyen des relevés. Option « le premier des deux »
  (500 h ou 6 mois).
- À la clôture d'une intervention préventive, on note l'**index du compteur** : il devient le point de départ suivant.
- **Pack** : les compteurs d'équipement relèvent du préventif (pack Pro), les compteurs de ressources de l'énergie
  (pack Entreprise). Le serveur décidera le module selon l'usage du compteur.

Questions à trancher :
1. Vos clients relèvent-ils déjà des heures de marche ? À quelle fréquence, et qui ?
2. Préventif sur compteur seul, ou « le premier des deux » (compteur ou calendrier) ?
3. Seuil d'alerte avant l'échéance : fixe (ex. 50 h avant) ou en pourcentage ?
4. Compteurs d'équipement dans le pack Pro (avec le préventif) : d'accord ?
