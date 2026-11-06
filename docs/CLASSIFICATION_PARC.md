# Classification du parc : proposition à relire

Statut : **à relire** (6 nov. 2026). Rien n'est codé. Inspirée de l'ISO 14224 (taxonomie des équipements) et du
vocabulaire EN 13306, simplifiée pour l'industrie et les sites tertiaires. Les **codes sont stables** : un libellé peut
changer, un code jamais (un code retiré est désactivé, pas effacé).

## 1. Cinq axes de classement

| Axe | Champ | Saisie |
|---|---|---|
| Où il est | `localisationId` (site › zone › ligne), existe | obligatoire |
| De quoi il fait partie | `parentId` (équipement parent), nouveau | facultatif |
| Ce que c'est | `classe` (code ci-dessous, qui donne la catégorie) + `sousType` (texte libre du client) | obligatoire, « à classer » par défaut |
| Son importance | `criticite` A / B / C + réponses à la grille (§3) | obligatoire, proposée par la grille |
| Contrôle réglementaire | `reglementaire` (liste §4) | facultatif |

Le **parent** et le **lieu** sont indépendants : un moteur est rattaché à sa pompe (parent) et se trouve dans la même
zone. Un équipement sans parent est une « tête » (machine, installation). Profondeur conseillée : 3 niveaux.

## 2. Catalogue : catégories et classes

Code de classe = `CATÉGORIE-CLASSE`. Chaque catégorie a une classe « Autre » (`…-AUTRE`).

**ROT — Machines tournantes**
| Code | Classe |
|---|---|
| ROT-POMPE | Pompe |
| ROT-COMPR | Compresseur |
| ROT-VENTIL | Ventilateur, soufflante, extracteur |
| ROT-MOTTH | Moteur thermique |
| ROT-REDUC | Réducteur, boîte de vitesses |
| ROT-TURB | Turbine |
| ROT-AGIT | Agitateur, mélangeur |
| ROT-CENTRI | Centrifugeuse, décanteuse |

**ELE — Électrique**
| Code | Classe |
|---|---|
| ELE-MOTEUR | Moteur électrique |
| ELE-TRANSFO | Transformateur |
| ELE-TGBT | Tableau, armoire, TGBT, cellule HT |
| ELE-VARIAT | Variateur, démarreur |
| ELE-ONDUL | Onduleur, batteries |
| ELE-GROUPE | Groupe électrogène |
| ELE-CONDENS | Batterie de condensateurs |
| ELE-SOLAIRE | Installation photovoltaïque |

**AUT — Automatisme et instrumentation**
| Code | Classe |
|---|---|
| AUT-AUTOMATE | Automate, supervision |
| AUT-CAPTEUR | Capteur, détecteur (position, présence, niveau) |
| AUT-MESURE | Transmetteur de mesure (pression, débit, température) |
| AUT-ANALYSE | Analyseur (pH, gaz, conductivité) |
| AUT-VANREG | Vanne de régulation, actionneur |
| AUT-PESAGE | Bascule, pesage |
| AUT-COMPTEUR | Compteur (énergie, eau, horaire) |

**STA — Équipements statiques**
| Code | Classe |
|---|---|
| STA-CUVE | Réservoir, cuve, silo |
| STA-PRESSION | Appareil à pression (ballon, autoclave) |
| STA-ECHANG | Échangeur de chaleur |
| STA-TUYAU | Tuyauterie, réseau |
| STA-VANNE | Vanne, robinetterie (hors régulation) |
| STA-FILTRE | Filtre, séparateur |

**PRO — Machines de production**
| Code | Classe |
|---|---|
| PRO-PRESSE | Presse |
| PRO-CONVOY | Convoyeur, transporteur |
| PRO-EMBALL | Machine d'emballage, conditionnement, étiqueteuse |
| PRO-REMPLI | Remplisseuse, doseuse |
| PRO-FOUR | Four, étuve, sécheur |
| PRO-BROYEUR | Broyeur, concasseur, crible |
| PRO-USINAGE | Machine-outil, usinage |
| PRO-INJECT | Injection, extrusion, soufflage |
| PRO-ROBOT | Robot, manipulateur |
| PRO-TEXTILE | Machine textile, couture |
| PRO-SOUDURE | Poste de soudure, découpe |

**MAN — Manutention et levage**
| Code | Classe |
|---|---|
| MAN-PONT | Pont roulant, portique |
| MAN-PALAN | Palan, treuil |
| MAN-CHARIOT | Chariot élévateur, transpalette électrique |
| MAN-NACELLE | Nacelle, plateforme élévatrice |
| MAN-QUAI | Niveleur de quai, porte sectionnelle |

**UTI — Utilités**
| Code | Classe |
|---|---|
| UTI-CHAUD | Chaudière, générateur de vapeur |
| UTI-FROID | Groupe froid, chambre froide |
| UTI-CLIM | Climatisation, CTA, ventilation |
| UTI-AIR | Centrale d'air comprimé, sécheur d'air |
| UTI-EAU | Traitement d'eau, adoucisseur, osmoseur |
| UTI-STEP | Station d'épuration, relevage |
| UTI-TOUR | Tour aéroréfrigérante |
| UTI-GAZ | Poste gaz, stockage gaz |

**SEC — Sécurité et incendie**
| Code | Classe |
|---|---|
| SEC-EXTINCT | Extincteur |
| SEC-RIA | RIA, poteau incendie |
| SEC-SPRINK | Sprinkler, extinction automatique |
| SEC-DETECT | Détection incendie, alarme |
| SEC-DESENF | Désenfumage, porte coupe-feu |
| SEC-ECLSEC | Éclairage de sécurité |

**BAT — Bâtiment**
| Code | Classe |
|---|---|
| BAT-CLOS | Toiture, façade, menuiseries |
| BAT-ECLAIR | Éclairage |
| BAT-ACCES | Portail, barrière, contrôle d'accès |
| BAT-ASCENS | Ascenseur, monte-charge |
| BAT-SANIT | Plomberie, sanitaires |

**VEH — Véhicules et engins**
| Code | Classe |
|---|---|
| VEH-LEGER | Véhicule léger, utilitaire |
| VEH-LOURD | Camion, car |
| VEH-ENGIN | Engin de chantier, tracteur |

**INF — Informatique et communication** (facultatif, souvent hors maintenance)
| Code | Classe |
|---|---|
| INF-POSTE | Poste, terminal, imprimante |
| INF-RESEAU | Réseau, radio, téléphonie |

Total : 11 catégories, 69 classes + 11 « Autre » = 80 codes.

## 3. Criticité A / B / C (grille guidée)

Cinq questions, réponse faible / moyen / fort :

| Question | Faible | Moyen | Fort |
|---|---|---|---|
| Production si panne | aucun effet | ralentie | arrêtée |
| Sécurité, environnement | aucun risque | risque maîtrisé | risque grave ou réglementaire |
| Qualité du produit | aucun effet | défauts rattrapables | non-conformité, rebut |
| Réparation (coût et délai) | faible, rapide | moyen | élevé ou pièce à long délai |
| Secours | secours en place | secours partiel ou manuel | aucun secours |

Règle proposée :
- **A (critique)** : sécurité-environnement « fort », ou production « fort » sans secours ;
- **B (important)** : au moins une réponse « fort », ou au moins deux « moyen » ;
- **C (standard)** : le reste.

L'appli propose la note, le responsable confirme ou force (avec motif). Correspondance avec l'ancienne échelle :
1 → A, 2 → B, 3 et 4 → C (à confirmer à la reprise).

Effets : la criticité oriente la priorité proposée des demandes, l'ordre des listes, les seuils de stock critiques et
les filtres d'indicateurs.

## 4. Contrôle réglementaire

| Code | Type |
|---|---|
| levage | Appareils de levage |
| pression | Appareils à pression |
| electrique | Installations électriques |
| incendie | Moyens de secours incendie |
| ascenseur | Ascenseurs et monte-charges |
| vehicule | Visite technique des véhicules |
| autre | Autre contrôle |

Le type indique **qu'un contrôle existe** ; la périodicité et l'organisme sont saisis dans un programme préventif
« vérification externe » (déjà prévu), selon la réglementation applicable et l'organisme agréé du client. L'appli ne
fixe aucune périodicité légale par défaut.

## 5. Fiche d'identité et statut

- Identité (facultatif) : fabricant, modèle, numéro de série, année de mise en service, fin de garantie, fournisseur.
- Statut : **en service**, **en secours** (redondance, déjà utilisé dans les indicateurs), **à l'arrêt** (hors
  exploitation, sans être réformé), **réformé** (n'apparaît plus, historique conservé).

## 6. Usages prévus

- Filtres du parc : catégorie, classe, criticité, réglementaire, statut, lieu, parent.
- Indicateurs par catégorie ou classe (pannes, délais, coûts), comparables entre sites.
- Bibliothèque de programmes préventifs par classe (proposés à la création d'un équipement).
- Import Excel : correspondance des colonnes du client vers les codes de classe.
- Famille du défaut sur l'intervention (mécanique, électrique…) : inchangée, c'est un autre axe (la nature de la panne,
  pas de l'équipement).

## 7. Reprise de l'existant

- Champ texte `famille` actuel conservé et affiché ; classe = « à classer » jusqu'au choix.
- Écran « À classer » pour le responsable : liste des équipements sans classe, choix rapide par lot.
- Criticité 1-4 convertie selon §3, marquée « à confirmer ».
- Aucun changement serveur (les équipements n'ont pas de règle côté serveur) ; stockage local inchangé (champs nouveaux
  dans la même fiche).

## 8. Questions de relecture

1. Catégories ou classes à ajouter pour tes premiers clients (secteur : agroalimentaire, textile, BTP, tertiaire…) ?
2. INF (informatique) : garder ou retirer ?
3. Règle A / B / C : d'accord avec la proposition ?
4. Criticité 4 actuelle → C : d'accord ?
