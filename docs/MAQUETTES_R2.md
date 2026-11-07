# Lot R2 — fiche intervention en étapes et signalement allégé : maquettes et spécification (à valider)

Source : audit (docs/AUDIT_UX_MODELE_DONNEES.md §2.1, §2.2) ; décisions Q6 (qualification proposée par le technicien,
validée par le responsable) et Q9 corrigée (arrêts suivis, planifiés / non planifiés ; temps des intervenants jamais
suivis). Maquette interactive présentée dans la conversation du 7 nov. **Validé le 7 nov. 2026 ; fait en v37 (voir §10).**

Constat de départ : la fiche fait 4,4 écrans de téléphone, 42 champs, 36 puces, tout modifiable à tout statut, la
qualification en bas, deux blocs « Pièces ».

## 1. Principe : trois étapes selon le statut

| Étape | Statuts | Qui | Contenu visible et modifiable |
|---|---|---|---|
| **Préparer** | à préparer, à planifier, planifiée, prête | responsable (le technicien voit un résumé et « Démarrer ») | qualification (nature, priorité), créneau, intervenants, **arrêt prévu** (oui / non ; s'il est prévu : planifié, heures prévues), pièces à prévoir, consignes |
| **Réaliser** | en cours, en attente | technicien, prestataire | **machine à l'arrêt ?** (oui / non → planifié / non planifié, début prérempli), ce qui a été fait, activités, pièces (une seule liste), photos, mise en attente (motif, qui lève) |
| **Terminer** | en cours → terminer ; à valider ; clôturée | technicien puis responsable | résultat, cause et certitude, **remise à disposition** si arrêt, réserves et suites, index du compteur (préventif selon l'usage), **liste de ce qui manque** ; validation par le responsable si la règle est active |

- En tête : référence, statut, équipement, demande liée, **frise Préparer · Réaliser · Terminer** (étapes passées cochées).
- Les étapes passées restent visibles **en résumé replié** ; une seule étape ouverte à la fois.
- Les boutons d'état sont **en bas de l'étape** (après les champs à remplir), pas en haut.
- Clôturée : résumé en lecture, historique ; correction avec motif (inchangé).

## 2. Qualification proposée puis validée (Q6)

- Le **technicien** qui intervient de lui-même (sans préparation) choisit nature et priorité : elles sont enregistrées
  comme **proposées** (`natureProposee`, `prioriteProposee`).
- Le **responsable** voit « Proposé par … : corrective · critique » en tête de la fiche, et dans son accueil une liste
  **« À qualifier »** ; il **valide** (`qualificationValidee`, `qualifieePar`, `qualifieeLe`) ou change.
- La clôture n'attend pas la validation (pas de blocage du terrain) ; les indicateurs utilisent la nature validée, sinon
  la proposée, avec la mention « non validée ».
- Serveur : un technicien ou un prestataire ne peut plus écrire `nature`, `priorite`, `qualificationValidee` ; seulement
  les champs « proposés ».

## 3. Arrêts de production (Q9)

- Champs : `avecArret` (oui / non / inconnu, inchangé), **`arretType`** (`planifie` / `non_planifie`, nouveau),
  `arretDebut`, `arretFin` (inchangés), **`arretPrevuDebut` / `arretPrevuFin`** (préparation d'un arrêt planifié, nouveaux).
- Type **proposé** selon la nature : préventive, travaux techniques → planifié ; corrective → non planifié ; modifiable.
- Début prérempli : heure du fait de la demande, sinon heure de démarrage.
- À **Terminer** une intervention avec arrêt **non planifié** : remise à disposition demandée ; si les heures ne sont pas
  connues, case « heures inconnues » (`arretHeuresInconnues`) : la panne compte dans le MTBF mais pas dans le MTTR
  (« n pannes, dont m avec heures connues »).
- Les temps des intervenants ne sont **jamais** demandés.

## 4. Activités et pièces

- **6 activités fréquentes** visibles (Diagnostic, Réglage, Remplacement, Réparation, Nettoyage, Essai) ; les 9 autres
  derrière « Autres… ». Pour une préventive, les fréquentes sont Inspection, Mesure, Graissage, Nettoyage, Réglage, Essai.
- **Une seule liste de pièces** : chaque ligne montre son état (demandée → réservée → remise / en main → utilisée ou
  rendue) et ses boutons (J'ai utilisé, Je rends, Retrait urgent, Annuler). « Pièce hors stock » devient une option de
  « Demander une pièce ». Pas de changement des faits magasin (volet B).

## 5. Saisie rapide

- Pour les petits travaux faits sur le moment : **un écran** (équipement, ce qui a été fait, résultat, arrêt oui / non avec
  durée approximative, photo) → crée une intervention **corrective, qualification proposée**, et la clôture
  (ou la passe « à valider » si la règle est active).
- Accès : « Signaler » → « j'ai déjà réglé le problème » ; fiche équipement → « Intervention rapide ».

## 6. Signaler allégé

- Trois questions visibles : **quelle machine** (QR ou liste), **que se passe-t-il** (texte + photo), **dans quel état**
  (« à l'arrêt » · « fonctionne mal » · « fonctionne, à vérifier »).
- L'état choisi remplit `etat` et `impact` (à l'arrêt → indisponible + interrompu ; fonctionne mal → dégradé + réduit ;
  à vérifier → anomalie + aucun) ; le **besoin** est déduit (corriger / vérifier).
- Repliés dans « Plus de détails » : besoin, heure du fait et précision, origine et demandeur.
- « J'interviens maintenant » (techniciens) inchangé.

## 7. Modèle de données et serveur

| Changement | Détail |
|---|---|
| `ots` : nouveaux champs | `natureProposee`, `prioriteProposee`, `qualificationValidee`, `qualifieePar`, `qualifieeLe`, `arretType`, `arretPrevuDebut`, `arretPrevuFin`, `arretHeuresInconnues` |
| Reprise de l'existant | interventions existantes : nature et priorité considérées **validées** ; `arretType` déduit de la nature (préventive / travaux → planifié, sinon non planifié) — calculé à la lecture, rien n'est réécrit |
| `push_fiches` | technicien / prestataire : refus d'écrire `nature`, `priorite`, `qualificationValidee` ; `verifierCloture` : arrêt non planifié → fin d'arrêt ou « heures inconnues » |
| Calculs (`calculs.js`, testés) | qualification effective (validée sinon proposée) ; type d'arrêt effectif ; préparation de R4 (MTTR sur arrêts non planifiés bornés) |

## 8. Tests d'acceptation

- Par statut et par rôle : seule l'étape en cours est ouverte ; boutons d'état en bas ; champs non pertinents absents.
- Fiche intervention au téléphone : **au plus 1,5 écran** pour l'étape en cours (contre 4,4) ; moins de 15 puces visibles.
- Technicien : qualification proposée enregistrée ; écriture directe de `nature` refusée par le serveur ; le responsable
  valide depuis la fiche et depuis « À qualifier ».
- Arrêt non planifié : impossible de terminer sans fin d'arrêt ou « heures inconnues » ; durée calculée affichée.
- Saisie rapide : une intervention clôturée (ou à valider) en un écran, hors ligne compris.
- Signaler : 3 questions, état / impact / besoin correctement déduits ; anciens signalements inchangés.
- Hors ligne et deux appareils : aucune perte (tests T1 – T8).

## 9. Durée

3 – 4 jours : calculs et serveur (champs, règles, tests) → fiche en étapes → saisie rapide et signalement → recette par
rôle, téléphone et ordinateur.

## 10. Fait (7 nov. 2026, v37)

- **Calculs** (`js/calculs.js`, `tests/interventions_r2.test.js`) : `qualification(o)` (validée, sinon proposée ; une
  intervention sans le champ `qualificationValidee` est considérée validée), `typeArret(o)` (choisi, sinon déduit de la
  nature), `aQualifier`, `ETAT_SIGNALE` ; `verifierCloture` exige la remise à disposition ou « heures inconnues » pour un
  arrêt non planifié ; indicateurs : nature effective, pannes (`arrets.nonPlanifies`, dont `nonPlanifiesBornes`),
  arrêts planifiés, nombre à qualifier (préparation de R4).
- **Serveur** `supabase/interventions_r2.sql` (généré par `scripts/generer_interventions_r2.py`, après `roles_r1.sql`) :
  - nature / priorité écrites par un technicien ou un prestataire **rangées en proposition** (plutôt que refusées : une
    ancienne version de l'appli encore en cache sur un téléphone ne perd donc pas sa saisie) ; exception : préventif
    lancé depuis un programme ;
  - refus : validation par le terrain ; proposition sur une qualification déjà validée par le responsable ;
    terminer / clôturer un arrêt non planifié sans fin ni « heures inconnues » (arrêts saisis depuis R2, champ
    `arretType` présent ; l'appli contrôle aussi les plus anciens).
  - Tests : `tests_interventions_r2.sql` 13/13 sur une base neuve (15 fichiers de tests SQL rejoués) ; serveur factice
    aligné (`tests/interventions_r2_serveur_test.py` 11/11).
- **Appli** (`js/app.js`) : fiche en trois étapes (frise, étapes passées repliées, boutons en bas, « Ce qui manque pour
  clôturer ») ; bandeau « Proposé par … » avec Valider / Changer ; liste « À qualifier » (accueil du responsable, filtre
  des travaux) ; arrêt oui / non + planifié / non planifié (type proposé, début prérempli) ; « Terminer » propose la
  remise à disposition à l'heure actuelle et la case « heures inconnues » ; 6 activités fréquentes + « Autres… » ; une
  seule liste de pièces (« pièce hors stock » = option de « Demander une pièce ») ; consignes de préparation ;
  **saisie rapide** (`#/rapide`, depuis Signaler, la fiche équipement et les travaux ; arrêt saisi en durée approximative,
  marqué « estimé ») ; **Signaler** en trois questions.
- Mesures au téléphone (375 × 812) : étape en cours 1,36 à 1,48 écran (fiche entière 2,25 contre 4,4), 10 à 12 puces.
- Hors périmètre, inchangé : le « Proposé par » affiche l'auteur de la fiche (pas de champ dédié).
