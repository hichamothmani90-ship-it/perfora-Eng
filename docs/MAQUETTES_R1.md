# Lot R1 — navigation et droits par rôle : maquettes et spécification (à valider)

Source : audit (docs/AUDIT_UX_MODELE_DONNEES.md §1, §3, §4) et décisions du 7 nov. 2026 (Q1, Q2 bis, Q3, Q7, Q9).
Note (décision Q9 corrigée) : les tuiles de la direction restent Disponibilité, MTBF et MTTR ; arrêts suivis en planifié /
non planifié ; temps des intervenants jamais suivis.
Maquette interactive présentée dans la conversation du 7 nov. (rôle par rôle : accueil, menu, mon compte, entreprise).
**Validé le 7 nov. 2026 ; fait en v36 (voir §8).**

## 1. Principes

1. Chaque rôle a **sa barre du bas** (5 entrées au plus, l'outil principal en premier), **son accueil** et **son menu**.
2. Le menu ne montre **que ce que le rôle peut utiliser**, regroupé par domaine ; une entrée déjà dans la barre n'y
   est pas répétée.
3. **Administrateur du client** = un **droit cumulable** avec un rôle métier (souvent le responsable maintenance ;
   possible pour la direction ou un autre rôle), pas un rôle à part. Il ajoute le groupe « Entreprise ».
   *(Point à valider : droit cumulable plutôt que 8e rôle — plus simple pour les petites entreprises.)*
4. Le rôle « pilote » est renommé **Direction** à l'écran (même droits : lecture).
5. Les restrictions de lecture (prestataire, journal) sont appliquées **par le serveur**, pas seulement à l'écran.
6. **Un seul bandeau** en haut à la fois, par priorité : hors ligne / saisies en attente > démonstration > annonce.
   Le rappel « exporter une sauvegarde » disparaît pour les comptes connectés (le serveur sauvegarde).
7. **Recherche** (loupe dans l'en-tête) : équipement, DEM, OT, article, compteur — dans ce que le rôle peut voir.

## 2. Barre du bas et accueil par rôle

| Rôle | Barre du bas | Accueil |
|---|---|---|
| Technicien | Ma journée · Signaler · Mes travaux · Parc · Plus | « Ma journée » : intervention en cours, mes travaux du jour, pièces prêtes à récupérer, mes relevés, préventifs de la semaine qui me sont affectés |
| Prestataire | Mes interventions · Signaler · Mon compte | ses interventions confiées (à venir, en cours) |
| Responsable maintenance | Tableau de bord · Demandes · Travaux · Préventif · Plus | « À décider » (demandes à examiner, qualifications proposées, interventions à valider) puis « Cette semaine » (charge, préventif dû / en retard) ; indicateurs du jour en tuiles |
| Exploitation (opérateur) | Signaler · Mes signalements · Relevés · Parc | grand bouton « Signaler un problème » (QR), mes signalements avec leur suivi, mes relevés |
| Magasinier | Magasin · Articles · Réappro · Réceptions · Plus | accueil actuel conservé (à servir, retraits à vérifier, à réapprovisionner) + livraisons attendues |
| Achats | Achats · À commander · Commandes · Réceptions · Plus | accueil actuel conservé (à commander, en cours, en retard) + urgences |
| Direction | Tableau de bord · Indicateurs · Énergie · Coûts | 6 chiffres cliquables (disponibilité avec part planifiée / non planifiée, MTBF, MTTR, préventif à l'heure, énergie du mois, coût du mois) — **contenu réel au lot R4** ; en R1 : tuiles disponibles aujourd'hui + emplacements |

« Travaux » du responsable s'ouvre en **Liste | Semaine** (le planning de la semaine est le lot R9 ; en R1 l'onglet
« Semaine » n'apparaît pas encore).

## 3. Menu « Plus » : qui voit quoi

| Groupe · entrée | Tech. | Presta. | Resp. | Expl. | Mag. | Achats | Dir. | Admin client (droit) |
|---|---|---|---|---|---|---|---|---|
| Terrain · Préventif | ✓ | | barre | | | | | |
| Terrain · Compteurs et relevés | ✓ | | ✓ | barre | | | | |
| Terrain · QR codes | ✓ | | ✓ | | | | | ✓ |
| Terrain · Parc | barre | | ✓ | barre | ✓ | ✓ | ✓ | |
| Magasin · Magasin (stock) | consultation | | ✓ | | barre | ✓ | | |
| Magasin · Achats | | | ✓ | | ✓ | barre | ✓ | |
| Magasin · Valeur du stock | | | ✓ | | ✓ | ✓ | ✓ | |
| Énergie · Énergie et eau | | | ✓ | | | ✓ (factures) | barre | |
| Pilotage · Indicateurs | | | ✓ | | | | barre | |
| Pilotage · Journal d'audit | | | ✓ | | | | ✓ | ✓ |
| Entreprise · Membres et équipes, Sites et lieux, Règles, Abonnement, Données | | | | | | | | ✓ |
| Mon compte, Aide et support | ✓ | barre | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

Modules du pack : une entrée dont le module n'est pas dans l'abonnement est masquée (comme aujourd'hui).

## 4. Réglages éclatés

- **Mon compte** (tout le monde) : nom et téléphone · changer mon mot de passe · cet appareil et la synchronisation ·
  aide et support · se déconnecter de tous les appareils · se déconnecter. *(Les écrans « mot de passe » et
  « déconnecter partout » sont le chantier C3 ; en R1 : les entrées et ce qui existe déjà.)*
- **Entreprise** (droit administrateur du client) : membres et équipes (R3 ; en R1 : l'actuel « Équipe et droits »),
  sites et lieux, règles (clôture validée par le responsable, **qui commande** en l'absence d'acheteur), abonnement,
  données (export).
- Disparaissent des réglages : « Adresse de l'application » (fixée), « Personnes » (devient « Membres » au R3),
  sauvegarde JSON et « Effacer cet appareil » (déplacés : Données pour l'admin ; « effacer cet appareil » dans
  « Cet appareil », avec confirmation renforcée).

## 5. Changements côté serveur

| # | Règle | Mise en œuvre |
|---|---|---|
| S1 | **Prestataire** : lit seulement les interventions où il est intervenant actif, leurs demandes, leurs équipements et lieux, ses propres signalements ; écrit seulement sur ces interventions | règle de lecture (RLS) et contrôle dans `push_fiches` ; tests d'étanchéité dédiés |
| S2 | **Journal d'audit** : fiches `journal` lisibles par responsable, direction, administrateur du client ; pour les autres, seulement les lignes de leurs propres fiches (historique d'une intervention qu'ils voient) | règle de lecture ; l'historique d'une fiche reste visible sur la fiche |
| S3 | **Droit administrateur du client** : colonne sur le profil ; invitations, sites, règles, abonnement (lecture) réservés à ce droit ; Perfora n'invite que le premier administrateur | `profils.admin_client` ; `preparer_invitation` exige ce droit (plus le rôle responsable) |
| S4 | **Qui commande** : réglage d'entreprise `commandePar` = achats (par défaut s'il existe un compte Achats) / responsable / magasinier | fiche `parametres` ; contrôle de `achat-commande` (lot R5 pour l'écran) |
| S5 | **Nature et priorité** : proposées par le technicien, validées par le responsable (lot R2) | — |

Migration : les responsables actuels reçoivent le droit administrateur du client (aucun client ne perd l'accès).

## 6. Tests d'acceptation (fin du lot)

- Pour chacun des 7 rôles (+ droit admin) : barre, accueil et menu conformes aux tableaux §2-§3, au téléphone et sur
  ordinateur.
- Prestataire : par l'API (pas seulement l'écran), ne lit aucune fiche hors de ses interventions ; écriture refusée
  ailleurs.
- Technicien, exploitation, magasinier, achats : lecture du journal d'audit refusée par l'API, historique de leurs
  fiches visible.
- Un responsable sans droit administrateur ne peut plus inviter ; avec le droit, oui.
- Un seul bandeau affiché ; plus de rappel de sauvegarde pour un compte connecté.
- Hors ligne inchangé (tests T1–T8), aucune donnée perdue au changement de version.

## 7. Durée et ordre

4 – 5 jours : serveur (S1 – S3) et tests d'étanchéité → navigation (barre, menu, accueils) → réglages éclatés →
recette par rôle. Le lot R3 (membres, équipes) s'appuie ensuite sur le droit administrateur posé ici.

## 8. Fait (7 nov. 2026, v36)

- **Serveur** `supabase/roles_r1.sql` (généré par `scripts/generer_roles_r1.py`, dans la séquence après `securite.sql`) :
  droit `profils.admin_client` (responsables existants migrés ; le premier compte d'une entreprise l'obtient à
  l'invitation ; jamais retiré au dernier administrateur), invitations / rôles / sites réservés à l'administrateur,
  périmètre du prestataire en lecture et en écriture (`prestataire_voit`, `prestataire_refus`), journal restreint
  (`journal_visible`). Tests : `tests_roles_r1.sql` 16/16 sur Supabase et sur une base neuve ; 13 fichiers de tests SQL
  conformes ; serveur factice aligné (`tests/roles_r1_serveur_test.py` 15/15 ; comptes `presta@` et `dir@` ajoutés).
- **Appli** : `js/vues/navigation.js` (barre, menu groupé, accueils technicien / prestataire / opérateur / direction,
  recherche) ; `app.js` : Mon compte (changer son mot de passe, se déconnecter de tous les appareils, appareil, support)
  et Entreprise (abonnement, membres et droits avec ★ Admin, règles, lieux, personnes sans compte, données) ; un seul
  bandeau ; plus de rappel d'export pour un compte connecté ; « Pilote » affiché « Direction » ; filtres « Les miens » /
  « Les miennes » ; resynchronisation unique des appareils pour appliquer les nouveaux périmètres (si rien en attente).
- **Robustesse** (trouvé pendant la recette) : une fiche sans date de création ne fait plus échouer les indicateurs ni les
  listes ; un écran qui échoue affiche « Écran indisponible » (erreur remontée) au lieu de laisser l'écran précédent figé.
- Libellés de barre raccourcis pour tenir sur une ligne : « Aujourd'hui » (responsable), « Synthèse » (direction),
  « Mes demandes » (opérateur).
- Reporté : S4 « qui commande » (réglage et contrôle au lot R5), onglet « Semaine » des travaux (lot R9).
