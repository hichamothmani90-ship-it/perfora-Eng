# Volet D — Énergie et eau : proposition de conception

Statut : **validé le 6 nov. 2026** avec les ajustements de la section 6. D1 (calculs et tests) et D2 (serveur) faits le 6 nov. 2026.
Références V3 : §19 (compteurs, modes de mesure, contrôle ciblé des relevés), §20 (factures, bilan combustible, air
comprimé et froid, de l'écart à l'intervention, ratios), §21 (écrans Énergie et eau, pilotage, qualité des données),
§36 (modèle : compteur, relevé et rupture, anomalie, facture et bilan, donnée externe), §37 (scénarios : index remplacé,
période chevauchante, mesure instantanée, relevé suspect, facture du 15 au 15, bilan combustible, sous-comptages).
Principe V3 : **saisie manuelle d'abord** (les compteurs connectés sont une évolution), et des chiffres honnêtes :
jamais d'addition entre unités, jamais de valeur inventée, jamais d'économie « prouvée » par une simple baisse.

## 1. Ce que l'on ajoute

| Fait | Qui | Rôle dans les calculs |
|---|---|---|
| **Compteur** (point de mesure) : code QR, ressource, mode, unité, coefficient, équipement ou zone desservis, compteur parent, fréquence de relevé, photo obligatoire ou non | responsable | référentiel |
| **Relevé** : date réelle, valeur (index ou quantité sur période), précision réel / estimé, source, photo | technicien désigné, responsable (exploitation selon choix) | base de toute consommation |
| **Rupture** : remplacement ou remise à zéro du compteur, changement de coefficient (ancien index final, nouvel index initial, motif) | responsable, technicien | évite une fausse « baisse d'index » |
| **Contrôle d'un relevé** : cohérent / suspect / confirmé / corrigé / invalidé, avec décision et motif | calculé, puis responsable | un suspect est gardé mais exclu des calculs |
| **Facture d'énergie** : fournisseur, référence, période exacte, lignes (quantité, unité, composante, montant HT, taxes) | responsable, achats | rapprochement facturé / mesuré ; coûts (lecture restreinte) |
| **Livraison de combustible** et niveau de cuve | magasinier, responsable | bilan : stock initial + livraisons − stock final |

## 2. Règles de calcul (dans `calculs.js`, testées)

- **Modes de mesure** (V3 §19) :
  - *cumulatif* (index) : consommation = (index fin − index début) × coefficient, entre deux relevés compatibles ;
    une rupture coupe la série (on additionne les tronçons, on ne soustrait jamais deux index de compteurs différents) ;
  - *période* : somme de quantités sur des périodes sans chevauchement (un index saisi comme quantité est refusé) ;
  - *instantané* (température, pression…) : dernière valeur et tendance, **jamais additionné** ;
  - *usage équipement* (heures de marche, cycles) : conservé tel quel, aucune conversion d'énergie en heures.
- **Consommation d'une période demandée** (mois, semaine…) : seulement sur la partie couverte par des relevés ;
  la couverture est affichée (« 27 jours sur 30 »). **Aucune interpolation** silencieuse, aucun zéro pour un manque ;
  une estimation au prorata n'existe que si elle est demandée explicitement et reste marquée « estimée ».
- **Contrôles automatiques** (V3 §19, §36) : doublon, unité incompatible, baisse d'index sans rupture, période
  chevauchante, date incohérente (future, avant le relevé précédent), variation inhabituelle (écart à la consommation
  habituelle du compteur), relevé manquant (en retard sur la fréquence). Une variation n'est pas une erreur démontrée :
  le relevé est **gardé, signalé**, exclu des calculs jusqu'à décision du responsable.
- **Sous-comptages** : principal et sous-compteurs ne s'additionnent jamais ; on affiche le **résidu** principal − Σ
  sous-compteurs, « à expliquer » (jamais une « fuite prouvée »). La hiérarchie de mesure est distincte de l'arborescence
  des équipements.
- **Totaux** : par ressource et par unité uniquement (kWh, m³, L…) ; jamais de total toutes énergies confondues.
- **Rapprochement facture / mesure** : sur l'intervalle exact de la facture (du 15 au 15 ≠ mois civil) ; bornes non
  couvertes par des relevés = rapprochement « incomplet », jamais un écart certain.
- **Bilan combustible** : stock initial + livraisons + transferts entrants − stock final − transferts sortants, même
  périmètre et même unité (exemple V3 : 1 000 + 2 000 − 800 = 2 200 L sortis) ; à rapprocher des usages mesurés.
- **Coûts** : montants des factures seulement, inconnus laissés vides (jamais zéro), lecture restreinte comme les achats.

## 3. Écrans

- **Terrain** : « Relevés à faire » (tournée des compteurs dus selon leur fréquence, par site) ; **scan du QR du compteur**
  → saisie en 10 secondes (valeur, photo si exigée, « estimé » possible), contrôle immédiat (« baisse d'index : vérifiez
  la valeur ou signalez un remplacement ») ; enregistrement hors ligne comme tout le reste.
- **Compteurs** (responsable) : liste par site et ressource, fiche (définition, hiérarchie, derniers relevés, ruptures,
  QR à imprimer), ajout d'une rupture.
- **Énergie** (responsable, pilote) :
  - consommations par ressource et période, avec couverture ; résidu des sous-comptages ;
  - **à examiner** : relevés suspects (confirmer, corriger, invalider, avec motif) et écarts facture / mesure ;
  - **créer une demande** depuis un écart (liée au compteur ou à l'équipement : fuite d'air, dérive…) ;
  - factures et rapprochement ; bilan des cuves (si utilisé).
- Accueil du technicien : « Relevés à faire aujourd'hui ».

## 4. Serveur (`supabase/energie.sql`)

- Types `compteurs`, `releves` (par site), `factures_energie` (par site, **lecture restreinte** comme achats via `voit_couts()`).
- Module « energie » du pack ; droits : responsable configure ; terrain (technicien, prestataire, exploitation selon
  choix) crée des relevés ; un relevé ne se modifie pas — seule sa qualification (qualité, décision, motif) par le
  responsable ; une correction est un **nouveau relevé** qui remplace l'ancien (lien), l'historique reste visible.
- Un compteur déjà utilisé ne change pas de mode, d'unité ni de coefficient sans rupture (continuité V3 §19).

## 5. Étapes

| Étape | Contenu | Vérification |
|---|---|---|
| D1 | Calculs : consommations par mode, ruptures, couverture, contrôles, résidu, rapprochement facture, bilan cuve | Tests des scénarios V3 §37 (index remplacé, chevauchement, instantané, suspect, facture du 15 au 15, bilan, sous-comptages) |
| D2 | Serveur : types, droits, lecture restreinte des factures, immuabilité des relevés | Tests SQL + étanchéité |
| D3 | Terrain : compteurs, QR, relevés à faire, saisie avec contrôle immédiat | Navigateur, hors ligne, 2 appareils |
| D4 | Énergie : consommations, à examiner, créer une demande, factures et rapprochement | Navigateur, rôles |
| D5 | Démo (compteurs, relevés dont un suspect et un remplacement, facture du 15 au 15), guide, recette, publication | — |

## 6. Choix validés (6 nov. 2026)

1. **Module « energie » dans le pack Entreprise.**
2. **Ressources** : électricité, eau, gasoil, fuel, gaz, air comprimé, froid, « autre » ; unités kWh, m³, L, kg, Nm³, h,
   cycles, °C, bar (`Calculs.UNITES_RESSOURCE`).
3. **Saisie des relevés** : techniciens, prestataires et exploitation ; **photo du compteur facultative** à chaque relevé.
   Deux modes à l'écran : **cumulatif** (index) ou **non cumulatif** (quantité consommée depuis le relevé précédent ou sur
   une période) ; la valeur instantanée (température, pression) existe dans les calculs et sera proposée en option.
   **Fréquence de relevé en jours** par compteur. Les factures sont mensuelles : le rapprochement se fait sur leurs dates
   exactes, quelle que soit la fréquence des relevés.
4. **Relevés jamais écrasés** (recommandation retenue) : à l'écran, un bouton « Corriger » ; on ressaisit la valeur, l'appli
   crée un nouveau relevé lié et affiche l'ancien barré « remplacé ». Même effort qu'une modification pour l'utilisateur,
   mais l'historique reste prouvable (contestation de facture, audit, deux appareils hors ligne qui corrigent en même temps).
5. **Relevé suspect gardé et exclu** jusqu'à décision. Seule une variation inhabituelle peut être « confirmée » ; une baisse
   d'index, un doublon, une unité fausse ou un chevauchement se corrigent (nouveau relevé ou rupture déclarée).
6. **Factures** : on joint le PDF ou la photo (pièce jointe, taille limitée) et on saisit à la main la période (du / au),
   la quantité (kWh, m³…), le montant HT (TTC facultatif) et les compteurs concernés. Pas de lecture automatique.
   Montants en lecture restreinte.
7. **Bilan des cuves** : calcul prêt (D1) ; écran en D5 si les étapes précédentes se passent bien, sinon petite étape D6.
8. **Ratios de production** (kWh par tonne…) : volet E, à discuter.

## 7. Fait en D1 (6 nov. 2026)

`js/calculs.js` : `analyserReleves` (statut de chaque relevé : retenu, suspect, invalidé, remplacé, rupture ; segments de
consommation), `consommationPeriode` (couverture, prorata seulement sur demande et « estimé »), `rapprochementFacture`
(bornes au plus proche du relevé, tolérance 1 jour ; incomplet si une borne manque), `residuSousComptage` (à expliquer,
incohérent, non comparable), `totauxParUnite`, `relevesDus`, `bilanCombustible`, `totalFactures`.
`tests/energie.test.js` : 16 tests dont les 7 scénarios V3 §37.

## 8. Fait en D2 (6 nov. 2026)

`supabase/energie.sql` exécuté sur Supabase (après `achats.sql`) :
- types `compteurs`, `releves`, `factures_energie` (module energie) et `parametres` (réglages de l'entreprise, une fiche
  `parametres-<entreprise>`, écrite par le responsable seul, lue par tous) ;
- droits : compteurs = responsable ; relevés = technicien, prestataire, exploitation, responsable ; factures = responsable
  et achats ; lecture des factures, de leur journal et de leurs pièces jointes réservée à responsable, magasinier, achats,
  pilote (`voit_couts`) ;
- relevé jamais modifié (seule la qualification par le responsable : decision, motifDecision, decideLe, decidePar) ;
  correction = nouveau relevé `remplaceId` du même compteur ; renvoi identique accepté ; site = celui du compteur ;
- compteur déjà relevé : mode, unité, coefficient figés (rupture) ;
- réglage `clotureParResponsable` : le serveur refuse la clôture par un autre rôle que le responsable.
`supabase/tests_energie.sql` : 25 tests conformes sur Supabase. Faux serveur aligné (`tests/energie_serveur_test.py`,
32 vérifications ; compte factice `expl@gmao.test`). Appli v24 : stockage local v6, réglage dans Réglages
(« Règles de l'entreprise »), « Terminer » → « À valider » quand le réglage est actif, accueil du responsable
« Interventions à valider ».

## 9. Fait en D3 (7 nov. 2026, v32)

- `js/vues/compteurs.js` : **Compteurs** (menu Plus) — relevés à faire, compteurs d'équipement (heures, cycles…) et
  d'énergie / eau, fiche compteur (définition, QR, relevés avec statut, anomalies, photo), création et modification par
  le responsable (usage, mesure, unité, coefficient figés après le premier relevé).
- **Saisie d'un relevé** (`#/releve?cpt=CODE`, ouverte par le QR du compteur, même hors ligne) : contrôle immédiat
  pendant la frappe (« ✓ Cohérent : +50 h » ou avertissement) ; index plus bas → choix « je corrige / compteur remplacé
  ou remis à zéro / garder à examiner » ; photo facultative ; valeur estimée ; heure réelle ; début de période (mode
  non cumulatif). **Corriger** = nouveau relevé lié. **Remplacement / remise à zéro** déclaré (nouveau départ proposé à 0).
- Responsable : **Confirmer** (variation inhabituelle seulement) ou **Invalider** un relevé à examiner, avec motif.
- **Préventif selon l'usage** : programme « toutes les N unités » et / ou « tous les N jours » (le premier des deux),
  marge d'alerte, reste affiché, date estimée (au moins 7 jours de relevés), « Préventif à lancer » ; à la clôture,
  **index obligatoire** → enregistré comme relevé et nouveau point de départ (`Calculs.echeanceCompteur`, testé).
- Accueil : « Relevés à faire aujourd'hui » ; fiche équipement : ses compteurs ; planche « QR des compteurs ».
- Après connexion, retour à la page demandée (QR scanné avant de se connecter).
Vérifié : 87 tests ; navigateur avec le serveur factice (responsable + technicien, hors ligne, photo, remplacement,
relevé invalidé, clôture avec index) ; aucun refus du serveur.
