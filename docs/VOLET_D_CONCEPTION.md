# Volet D — Énergie et eau : proposition de conception

Statut : **proposition à valider** (6 nov. 2026). Rien n'est encore codé.
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

## 6. Choix à valider

1. **Module « energie » dans le pack Entreprise** (comme prévu) ; option possible pour le Pro plus tard.
2. **Ressources proposées** : électricité, eau, gasoil, fuel, gaz, air comprimé, froid (+ « autre ») ; unités par
   ressource (kWh, m³, L, Nm³, h, cycles, °C, bar).
3. **Qui saisit les relevés** : techniciens et prestataires, **plus l'exploitation** (souvent ce sont les opérateurs qui
   font la tournée) ; le responsable désigne un relevé « attendu de » par compteur, sans exclure les autres.
4. **Relevés immuables** : une erreur se corrige par un nouveau relevé lié (historique conservé), jamais en écrasant.
5. **Relevé suspect gardé et exclu des calculs** jusqu'à décision ; couverture affichée ; aucune interpolation.
6. **Factures saisies à la main** (photo du PDF possible), montants en lecture restreinte (pas d'OCR dans ce volet).
7. **Bilan des cuves de combustible** inclus en D5 (si tu as des clients avec gasoil / fuel stockés) ; sinon reporté.
8. **Ratios de production** (kWh par tonne…) reportés au volet E (pilotage), car ils exigent une donnée de production
   datée et fiable.
