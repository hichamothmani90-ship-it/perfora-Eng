# Audit — modèle de données et expérience utilisateur (7 nov. 2026, appli v35)

Demandé par Hicham : auditer le modèle de données et l'expérience utilisateur, **sans rien modifier ni coder**.
Méthode : inventaire du code (31 écrans, 81 actions, 7 rôles), relecture du modèle et des documents de conception,
parcours de l'appli **au format téléphone** avec les données de démonstration, rôle par rôle (profil simulé en mémoire,
rien n'a été enregistré), mesure des écrans (hauteur, nombre de champs), comparaison avec la procédure PR MAINT 01 V3.

Gravité : 🔴 à traiter **avant le pilote** · 🟠 important (pendant le pilote) · 🟢 confort / après.

---

## 0. Synthèse

Le **fond** est solide : règles métier, hors ligne, sécurité, chiffres honnêtes, journal. La **forme** n'a pas suivi :
on a ajouté écran après écran, et l'appli montre aujourd'hui **tout à tout le monde, tout le temps**. Les dix constats
qui comptent :

| # | Constat | Gravité |
|---|---|---|
| 1 | La fiche intervention fait **4,4 écrans de téléphone, 42 champs, 36 puces**, tous modifiables quel que soit le statut ; la qualification (nature, priorité) est **tout en bas** alors qu'elle vient en premier | 🔴 |
| 2 | L'accueil et le menu « Plus » sont **presque identiques pour tous les rôles** (sauf magasinier et achats) : l'opérateur de production voit « Travaux ouverts », « Préventifs à lancer » ; le pilote voit « Mes travaux » | 🔴 |
| 3 | **Droits d'affichage trop larges** : un prestataire externe voit le journal d'audit, les indicateurs et le magasin ; un technicien peut changer la nature et la priorité d'une intervention | 🔴 |
| 4 | **Équipe mal organisée** : deux notions parallèles (« Personnes » sans compte et « Équipe et droits » avec compte), pas d'équipes, pas de société prestataire, **Réglages = 12 blocs** mélangés (appareil, entreprise, équipe, sauvegarde JSON, effacement…) | 🔴 |
| 5 | **Pas de MTBF, MTTR ni disponibilité** ; les indicateurs actuels (comptages, médianes) n'expliquent ni leur définition ni quoi en faire ; aucun tableau de bord par rôle | 🔴 |
| 6 | **Magasin ↔ achats non relié** : une pièce « indisponible » pour une intervention ne crée ni ne rattache aucune demande d'achat ; 11 scénarios courants sur 21 ne sont pas couverts (§8) | 🔴 |
| 7 | **Packs** : 3 sites dans « Pro » brouille l'offre ; il manque un pack **Multisite** (proposition §5) | 🟠 |
| 8 | **Fiche équipement trop pauvre** : 5 champs, famille en texte libre, criticité « 1-4 » sans signification, alors que la classification A/B/C et le catalogue de 80 classes sont validés (docs/CLASSIFICATION_PARC.md) | 🟠 |
| 9 | **QR codes** : dépendent d'un réglage manuel d'adresse, un seul format d'étiquette, ouvrent toujours « Signaler » (même pour le technicien), impression depuis le téléphone peu pratique | 🟠 |
| 10 | **Énergie** : l'écran est un tableau de chiffres, sans courbe, sans coût du mois, sans comparaison au mois précédent : ce n'est pas un tableau de bord « qui parle » | 🟠 |

**Recommandation globale** : une **refonte de l'organisation** (pas du moteur) avant le pilote, en 4 lots (§11) :
navigation par rôle, fiche intervention en étapes, équipe et comptes, tableaux de bord avec MTBF / MTTR.
Le modèle de données n'a besoin que de compléments ciblés (§6), pas d'une reprise.

---

## 1. Navigation et organisation des vues

**Constat**
- Barre du bas (téléphone) : Accueil · Demandes · Travaux · Parc · Plus. Sur ordinateur, Préventif, Magasin, Indicateurs,
  Journal et Réglages remontent dans la barre ; sur téléphone ils sont tous dans « Plus ».
- « Plus » est une **liste plate de 10 entrées** sans regroupement : Préventif, Compteurs, Énergie et eau, QR codes,
  Magasin, Achats, Valeur du stock, Indicateurs, Journal d'audit, Réglages.
- Le **magasinier** ouvre « Plus » pour aller au magasin, son outil principal ; l'**acheteur** aussi pour les achats.
- Bandeaux qui se cumulent en haut d'écran (démo) : « Démonstration », « Reconnexion » (rouge), « Aucune sauvegarde
  exportée · 112 modifications » — trois messages contradictoires avant le contenu.
- Pas de recherche globale (code équipement, référence DEM / OT, article).

**Recommandations**
- 🔴 **Barre du bas propre à chaque rôle** (5 entrées maximum, l'outil principal en premier) :

| Rôle | Barre du bas proposée |
|---|---|
| Technicien / prestataire | Ma journée · Signaler · Mes travaux · Parc · Plus |
| Responsable maintenance | Tableau de bord · Demandes · Travaux · Préventif · Plus |
| Magasinier | Magasin (à servir) · Articles · Réceptions · Inventaire · Plus |
| Achats | Achats · À commander · Réceptions · Fournisseurs · Plus |
| Exploitation (opérateur) | Signaler · Mes signalements · Relevés · Parc |
| Pilote / direction | Tableau de bord · Indicateurs · Énergie · Coûts |

- 🔴 « Plus » **regroupé par domaine** (Terrain · Magasin et achats · Énergie · Pilotage · Mon compte · Entreprise), et
  seulement ce que le rôle peut utiliser.
- 🟠 Un seul bandeau à la fois, par priorité (hors ligne > mode démo > saisies non envoyées) ; le rappel « exporter une
  sauvegarde » n'a plus de sens avec un compte (le serveur sauvegarde) : à réserver à l'usage sans compte.
- 🟠 Recherche globale (icône loupe dans l'en-tête) : équipement, DEM, OT, article, compteur.

## 2. Parcours clés

### 2.1 Intervention (OT) — l'exemple de la capture

**Constat** (OT en attente, téléphone) : 11 blocs dans l'ordre Intervenants → Arrêt → **Travail réalisé** (15 puces
d'activité) → Cause → Pièces → Pièces utilisées → Réserves → Photos → **Qualification** → Attentes → Historique.
Tout est modifiable dès la création, même « Travail réalisé » et « Cause » d'une intervention pas encore démarrée.
Deux blocs « Pièces » distincts (demandées / utilisées) difficiles à comprendre. Les boutons d'état (Démarrer, Terminer)
sont en haut, loin des champs à remplir avant de terminer.

**Recommandations**
- 🔴 **Fiche en 3 temps, selon le statut** (on ne voit que l'étape en cours, les autres repliées en résumé) :
  1. **Préparer** (responsable) : qualification (nature, priorité), créneau, intervenants, pièces à prévoir, consignes.
  2. **Réaliser** (technicien) : démarrer, arrêt oui/non, ce qui a été fait, pièces (une seule liste : demandée → remise
     → utilisée / rendue), photos, mise en attente.
  3. **Terminer** (technicien) puis **clôturer** (responsable) : résultat, cause et certitude, réserves et suites,
     index du compteur si préventif selon l'usage. Le bouton « Terminer » en bas, après les champs, avec la liste de ce
     qui manque.
- 🔴 **Activités** : 6 puces fréquentes (Diagnostic, Réglage, Remplacement, Réparation, Nettoyage, Essai) + « Autres… »
  qui déplie les 9 restantes ; ou choix proposé selon la nature (préventif → Inspection, Graissage, Mesure…).
- 🔴 Qualification non modifiable par le technicien (voir §3).
- 🟠 Un **mode « saisie rapide »** pour les petites interventions : ce qui a été fait + résultat + photo, en un écran.

### 2.2 Signaler (demande)

**Constat** : bon parcours (QR → équipement pré-rempli, doublons signalés), mais 24 puces sur un écran et demi
(état 5, besoin 8, impact 4, plus origine, heure, précision). Pour un opérateur de production, c'est beaucoup.
**Recommandation** 🟠 : 3 questions visibles (Quoi ? constat + photo · Gravité ? arrêt / dégradé / anomalie ·
Impact sur la production ?), le reste (besoin, heure du fait, demandeur) replié ; « besoin » déduit par défaut.

### 2.3 Demande → intervention (responsable)

Le parcours a été simplifié en v23 (4 boutons : J'interviens, Planifier, Je m'en occupe, Classer). 🟢 Ajouter un **tri par
criticité de l'équipement × état** dans « Demandes à examiner », et un écran de **planification de la semaine**
(qui fait quoi quand), absent aujourd'hui.

### 2.4 Préventif

🟠 Programmes en liste simple ; pas de vue **calendrier** (semaine / mois), pas de **charge** par technicien, pas de
**gamme** (liste de points à cocher avec valeurs mesurées) : l'instruction est un texte libre. Pas de pièces prévues
par programme (kit), donc pas de réservation anticipée.

## 3. Ce que voit chaque rôle (vérifié écran par écran)

| Rôle | Accueil actuel | Menu « Plus » actuel | Écarts constatés | Gravité |
|---|---|---|---|---|
| Responsable | Indisponibles, demandes, travaux, préventif, relevés, énergie | les 10 entrées | Pas de tableau de bord synthétique ; tout est en listes | 🟠 |
| Technicien | **même accueil que le responsable** | Préventif, Compteurs, QR, Magasin, Indicateurs, **Journal**, Réglages | Voit toutes les demandes à examiner et « Préventif à lancer » de l'entreprise ; peut modifier **nature et priorité** des OT ; accède au journal d'audit complet | 🔴 |
| Prestataire (externe) | même que le technicien | même que le technicien | **Société extérieure qui voit le journal d'audit, les indicateurs et tout le magasin** ; devrait ne voir que les interventions qui lui sont confiées | 🔴 |
| Exploitation (opérateur) | **même accueil que le technicien** (« Travaux ouverts », « Préventifs à lancer », « Mes travaux ») | Préventif, Compteurs, QR, Magasin, Indicateurs, Journal, Réglages | Son besoin : signaler, suivre **ses** signalements, faire ses relevés | 🔴 |
| Magasinier | accueil dédié (à servir, retraits à vérifier, à réapprovisionner) ✅ | + Préventif, Compteurs, Indicateurs, Journal | Accueil bon ; menu trop large ; magasin hors de la barre du bas | 🟠 |
| Achats | accueil dédié (à commander, en cours, en retard) ✅ | + Préventif, Compteurs, **Énergie**, QR | Accueil bon ; menu trop large | 🟠 |
| Pilote (direction) | accueil du responsable avec « Mes travaux » | les 10 entrées | Aucun tableau de bord de direction (disponibilité, coûts, énergie, tendance) | 🔴 |

Règle proposée : **chaque rôle a son accueil, sa barre, son menu** ; le serveur reste l'autorité des droits (déjà le
cas pour l'écriture) mais il faut aussi **restreindre la lecture** du journal d'audit (responsable, pilote) et, pour le
prestataire, des interventions (seulement celles où il est intervenant).

## 4. Équipe, comptes et invitations

**Constat**
- **Deux listes de personnes** : « Personnes » (fiches sans compte, créées à la main, pour signer et affecter) et
  « Équipe et droits » (comptes invités par e-mail). Un compte crée automatiquement sa fiche personne : les deux listes
  se recoupent sans qu'on le voie.
- Pas d'**équipes** (mécanique, électrique, équipe de nuit…), pas de **compétences** / habilitations (électrique B1V…),
  pas de **société prestataire** (on note une société en texte sur la personne), pas de téléphone.
- **Qui invite ?** Aujourd'hui : le **responsable** (Réglages → Équipe) et l'**administrateur plateforme** (console, un
  responsable par client). Pas de rôle « administrateur du client » distinct du responsable maintenance.
- **Réglages** = 12 blocs pour tout le monde : appareil, entreprise, synchronisation, règles, équipe, support, adresse
  de l'appli, personnes, lieux, sauvegarde JSON, démonstration, effacement.

**Recommandations**
- 🔴 **Une seule notion « Membre »** : une personne, avec ou sans compte (un intervenant sans téléphone reste possible),
  rôle, équipe(s), site(s), société (interne ou prestataire), téléphone, habilitations, actif / inactif.
  L'invitation devient une action sur le membre (« Donner un accès »).
- 🔴 **Qui invite** (à trancher, question Q1) — proposition : un rôle **Administrateur du client** (souvent le
  responsable maintenance, mais pas forcément : DSI, directeur de site) qui gère membres, sites, abonnement ; le
  responsable maintenance gère le métier. Perfora (plateforme) n'invite que le premier administrateur du client.
- 🔴 **Réglages éclatés** en : **Mon compte** (profil, mot de passe, déconnexion, appareil) · **Entreprise** (admin :
  membres et équipes, sites et lieux, règles, abonnement) · **Données** (export, effacement, réservé à l'admin).
  L'adresse de l'appli (QR) disparaît des réglages : elle est connue.
- 🟠 **Équipes** : liste simple (nom, chef d'équipe, membres) ; filtre « mon équipe » dans les travaux ; affectation
  d'une intervention à une équipe puis à une personne.
- 🟠 **Prestataires** : fiche société (nom, contrat, contact) ; un compte prestataire ne voit que ses interventions.

## 5. Packs et sites

**Actuel** : Essentiel (1 site, 5 utilisateurs, base + préventif) · Pro (**3 sites**, 15 par site, 45 au total,
+ magasin, rapports) · Entreprise (illimité, + achats, énergie, imports).

**Constat** : « Pro » mélange deux choses — plus de **fonctions** (magasin) et plus de **sites**. Une PME mono-site qui
veut le magasin paie des sites dont elle n'a pas besoin ; un groupe de 3 usines est en « Pro » sans achats ni énergie.

**Proposition** 🟠 (prix à fixer par Hicham) :

| Pack | Sites | Utilisateurs | Modules |
|---|---|---|---|
| Essentiel | 1 | 5 | demandes, interventions, préventif, QR, hors ligne |
| Pro | 1 | 15 | + magasin, compteurs d'équipement, indicateurs |
| **Multisite** (nouveau) | 2 à 5 | 15 par site | Pro + vue consolidée multi-sites, transferts entre sites |
| Entreprise | illimité | illimité | + achats, énergie et eau, imports, administration avancée |

Options à la carte possibles (énergie seule sur Pro, site supplémentaire). Le modèle actuel (packs + dérogations par
abonnement) le permet sans changement de structure : c'est surtout un changement de **données** et d'**écran console**.

## 6. Modèle de données

**Points forts** : une table `fiches` (JSON) synchronisée par numéro de séquence, multi-entreprise et multi-site
étanches (règles d'accès testées), journal par fiche, faits distincts pour le magasin (besoin ≠ réservation ≠ remise ≠
utilisation ≠ retour), relevés jamais modifiés, coûts en lecture restreinte. À garder.

**Incohérences**

| # | Constat | Gravité |
|---|---|---|
| M1 | **Site** (table serveur) et **lieu racine** (« Usine », « Site Tanger » dans les localisations) font doublon : deux arbres à tenir | 🟠 |
| M2 | **Criticité 1-4** dans l'appli ≠ **A/B/C + grille** validée ; **famille** en texte libre ≠ **classe** du catalogue | 🟠 |
| M3 | **Personnes** (fiches) et **profils** (comptes) : deux sources pour la même personne | 🔴 |
| M4 | Statuts d'OT `a_preparer` et `a_planifier` affichés tous deux « À planifier » | 🟢 |
| M5 | Pas d'**équipement parent** (ligne → machine → sous-ensemble) : impossible de remonter une panne de convoyeur à la ligne | 🟠 |
| M6 | Pas de **temps d'ouverture** (calendrier de production par site ou par équipement) : **MTBF et disponibilité impossibles** à calculer proprement | 🔴 |
| M7 | Fournisseur stocké en **texte** sur les achats alors que le type `fournisseurs` existe côté serveur (sans écran) | 🟠 |
| M8 | Références entre fiches vérifiées seulement pour certaines (équipement, compteur) : un article, une personne ou un lieu supprimé peut laisser des liens orphelins | 🟢 |

**Entités à ajouter** (par priorité) : Équipe · Société (prestataire / fournisseur, une seule fiche « tiers ») ·
Calendrier d'ouverture (par site, dérogation par équipement) · Équipement parent + classe + criticité A/B/C ·
Gamme de préventif (points de contrôle) · Kit de pièces par programme · Emplacement et conditionnement d'article ·
Inventaire (campagne, comptages) · Transfert entre sites · Achat non stocké · Document (notices, schémas) ·
Centre de coût (volet E).

## 7. Indicateurs et tableaux de bord

**Actuel** (Plus → Indicateurs, 30 / 90 / 365 jours) : interventions créées, délai médian de clôture, préventif à
échéance (%), demandes ouvertes, répartition par nature, pannes répétitives, pièces par équipement, arrêts (faits,
bornes connues, durée cumulée). Pas de définition affichée, pas de filtre site / équipement / famille, pas de tendance,
pas de lien « que faire ».

> Complété par la décision Q9 (§13) : arrêts suivis en **planifié / non planifié** ; MTTR et MTBF sur les arrêts
> **non planifiés** ; disponibilité avec la part planifiée et non planifiée ; temps des intervenants jamais suivis.

**MTBF, MTTR, disponibilité** 🔴 — définitions proposées, compatibles avec les données saisies :

| Indicateur | Définition | Données nécessaires | Disponible aujourd'hui ? |
|---|---|---|---|
| **Panne** | intervention corrective **avec arrêt** (ou demande « indisponible ») sur l'équipement | nature, arrêt oui/non | ✅ |
| **MTTR** (temps moyen de remise en service) | moyenne des durées d'arrêt (début → remise à disposition) des pannes **bornées** | début et fin d'arrêt | ✅ (afficher « n pannes sur m bornées ») |
| **MTBF** (temps moyen entre pannes) | (temps d'ouverture − durée des arrêts) ÷ nombre de pannes | **temps d'ouverture** | ❌ (M6) ; ou heures de marche si compteur d'équipement |
| **Disponibilité** | MTBF ÷ (MTBF + MTTR), ou (ouverture − arrêts) ÷ ouverture | idem | ❌ |
| Taux de préventif | heures ou nombre d'OT préventives ÷ total | nature | ✅ |
| Coût de maintenance par équipement | pièces valorisées + achats non stockés | valorisation (lecture restreinte) | partiel |

Règles d'honnêteté (comme l'énergie) : MTBF affiché seulement à partir de **2 pannes** ; mention « estimé » si le temps
d'ouverture est le calendrier par défaut ; pannes non bornées comptées à part.

**Tableaux de bord par rôle** 🔴
- **Responsable** : aujourd'hui (indisponibles, urgences, en attente de pièce), semaine (préventif dû, charge),
  tendance 12 mois (pannes, MTTR), top 5 équipements à problème (Pareto des arrêts).
- **Pilote / direction** : disponibilité des équipements critiques (A), MTBF / MTTR, coûts du mois, énergie du mois,
  préventif à l'heure — une page, 6 chiffres, chacun cliquable vers le détail.
- **Technicien** : « ma journée » (mes interventions, mes relevés, mes pièces à récupérer).
- **Fiche équipement** : ses propres MTBF, MTTR, dernières pannes, coût, compteurs — c'est là que la question se pose.

**Énergie** 🟠 : ajouter en tête un **résumé du mois** par ressource (quantité, coût facturé, **évolution vs mois
précédent et même mois N-1**, coût moyen €/kWh ou MAD/kWh), une **courbe 12 mois** par ressource, le **top 3 des
consommateurs** (sous-compteurs), les alertes (écarts, résidus, relevés manquants). Le tableau détaillé actuel reste en
dessous. Plus tard : ratio de production (kWh par tonne), volet E.

## 8. Magasin ↔ achats

**Flux actuel** : besoin de pièce (OT) → réservation → remise → utilisation / retour ; en parallèle, seuils →
« à réapprovisionner » → demande d'achat → validation → commande (fournisseur en texte) → réceptions partielles →
isolement éventuel → décision. **Les deux circuits ne se rejoignent pas.**

**Couverture des scénarios courants**

| # | Scénario | État |
|---|---|---|
| 1 | Pièce en stock demandée par une intervention → réservée → remise → utilisée ou rendue | ✅ |
| 2 | Retrait urgent sans magasinier, vérifié ensuite | ✅ |
| 3 | Pièce hors catalogue demandée, rattachée ensuite à un article | ✅ |
| 4 | Consommable sorti sans intervention | ✅ |
| 5 | Réapprovisionnement sur seuil → demande d'achat → validation → commande → réceptions partielles | ✅ |
| 6 | Réception non conforme → isolement → libérer / retour / rebut / réparation | ✅ |
| 7 | Valeur du stock (coût moyen pondéré par site) | ✅ |
| 8 | **Pièce indisponible pour une intervention → demande d'achat liée → à la réception, réservée pour cette intervention → attente levée** | ❌ |
| 9 | Demande d'achat **urgente** (panne) avec validation courte ou a posteriori | ⚠️ même circuit que le réapprovisionnement |
| 10 | Réception **sans commande** (achat au comptoir, livraison directe) | ⚠️ entrée de stock manuelle, sans lien achat |
| 11 | **Achat non stocké** (prestation, sous-traitance, location) lié à une intervention, coût ajouté | ❌ (décidé le 6 nov., pas fait) |
| 12 | **Retour fournisseur** tracé (garantie, erreur de livraison) | ⚠️ décision sur pièce isolée seulement |
| 13 | **Inventaire** tournant ou annuel (comptage, écart, validation) | ❌ ajustement à la main |
| 14 | **Transfert entre sites** | ❌ |
| 15 | **Emplacement** en magasin (allée, casier) | ❌ (décidé) |
| 16 | **Conditionnement** (acheté par carton, sorti à l'unité) | ❌ (décidé) |
| 17 | **Fournisseurs** : fiche, contacts, délai, prix habituels | ❌ écran (import seulement) |
| 18 | **Pièces prévues par le préventif** (kit, réservation à l'avance) | ❌ |
| 19 | Comparaison de **devis** / prix fournisseurs | ❌ |
| 20 | **Pièces réparables, numéros de série** | ❌ (plus tard) |
| 21 | **Budget / centre de coût** | ❌ (volet E) |

**Recommandations**
- 🔴 Relier les deux circuits : sur une pièce **indisponible**, bouton « Demander l'achat » (pré-rempli, lié à la
  pièce et à l'intervention) ; à la réception, **réservation automatique** pour l'intervention et notification au
  technicien ; l'attente « pièce » se lève toute seule. Afficher sur l'intervention « commandée le …, livraison prévue … ».
- 🔴 Circuit **urgent** : demande d'achat « urgente » validable a posteriori par le responsable (trace au journal).
- 🟠 C bis (déjà décidé) : inventaire, emplacement, conditionnement, fournisseurs, achats non stockés — dans cet ordre.
- 🟠 Un **schéma du flux** dans l'aide (une image vaut mieux que deux écrans).

## 9. QR codes

**Constat** : planche par lieu ou par équipement (filtre par lieu), étiquette fixe (QR 132 px + nom + code + lieu),
compteurs sur une planche à part ; le QR contient l'adresse de l'appli prise dans **Réglages → Adresse de l'application**
(réglage manuel, source d'erreur : une planche imprimée avec une mauvaise adresse est inutilisable) ; le QR ouvre
toujours **Signaler**, même scanné par un technicien ou le responsable.

**Recommandations** 🟠
- Adresse **fixe** (app.perfora.ma), plus de réglage.
- **Un QR = l'équipement** ; ce qu'il ouvre dépend du rôle : opérateur → Signaler ; technicien → fiche équipement avec
  « Signaler », « Intervenir », « Relever le compteur », historique ; magasinier → articles de l'équipement (plus tard).
- **Formats d'étiquettes** (petite 40×30 mm, moyenne, A4 par 12 / 24, étiquette industrielle), logo du client,
  sélection à la carte (cocher les équipements), **PDF à télécharger** pour l'imprimer depuis l'ordinateur.
- QR des **lieux** (ouvre la liste des équipements du lieu) et des **articles** (inventaire, remise).
- Un repère « déjà imprimé le … » pour savoir quels équipements n'ont pas encore leur étiquette.

## 10. Divers relevés pendant l'audit

- 🟠 Fiche équipement : sections « En cours / Compteurs / Préventif / Historique » sans indicateurs propres ni documents.
- 🟠 Listes (demandes, travaux) sans filtres croisés (site, équipe, criticité, période) ni tri.
- 🟢 Icônes typographiques (↻ ⏱ ⚡ ▣ ▤ ₪ ∑ ▥ ☰ ⚙) inégales selon les téléphones : un jeu d'icônes cohérent.
- 🟢 Pas d'aide intégrée ni de visite guidée (prévue : planning 3.2, 5.5).
- 🟢 Ordinateur : la mise en page reste celle du téléphone élargie ; le responsable gagnerait des tableaux (listes
  denses, colonnes triables) et un écran de planification.

## 11. Plan de refonte proposé (organisation, pas moteur)

| Lot | Contenu | Gravité | Effort indicatif |
|---|---|---|---|
| **R1 Navigation par rôle** | barre du bas, accueil et menu par rôle ; Réglages éclatés ; droits de lecture (journal, prestataire) ; un seul bandeau | 🔴 | 3 – 4 jours |
| **R2 Fiche intervention en étapes** | Préparer / Réaliser / Terminer, qualification réservée, activités fréquentes, une seule liste de pièces, saisie rapide ; Signaler allégé | 🔴 | 3 – 4 jours |
| **R3 Membres, équipes, invitations** | une seule notion « membre », équipes, société prestataire, rôle administrateur du client (selon Q1), écran Entreprise | 🔴 | 3 – 4 jours |
| **R4 Tableaux de bord et MTBF / MTTR** | calendrier d'ouverture, définitions affichées, tableaux de bord responsable / pilote / technicien, fiche équipement avec ses indicateurs, résumé énergie du mois | 🔴 | 4 – 5 jours |
| **R5 Magasin ↔ achats relié** | pièce indisponible → achat lié → réservation à la réception, achat urgent | 🔴 | 2 – 3 jours |
| R6 Fiche équipement et classification | parent, classe, criticité A/B/C avec grille, marque / modèle / série, documents | 🟠 | 3 jours |
| R7 QR | adresse fixe, ouverture selon le rôle, formats et PDF, QR lieux et articles | 🟠 | 2 jours |
| R8 Packs | Multisite, écran console, quotas | 🟠 | 1 jour (+ prix) |
| C bis | inventaire, emplacement, conditionnement, fournisseurs, achats non stockés | 🟠 | 5 – 6 jours |

Ordre conseillé : **R1 → R2 → R3 → R5 → R4**, puis R7, R6, R8 et C bis selon le client pilote. R1 à R5 font environ
**3 semaines** ; à placer **avant le pilote** (la production, étape B, peut se faire en parallèle car ces lots touchent
surtout l'appli). Chaque lot : maquette écran par écran validée par Hicham **avant** de coder.

## 12. Questions à trancher

| # | Question | Proposition |
|---|---|---|
| Q1 | **Qui invite** les membres d'un client ? | un rôle « administrateur du client » (gère membres, sites, abonnement) ; Perfora n'invite que le premier |
| Q2 | Quel **nouvel utilisateur** faut-il ajouter ? (« un user devra être ajouté ») | à préciser : administrateur du client ? chef d'équipe / superviseur (planifie et valide pour son équipe) ? |
| Q3 | Le prestataire voit-il **seulement ses interventions** ? | oui |
| Q4 | **Temps d'ouverture** pour le MTBF : calendrier par site (ex. 2×8, 5 j / 7) avec dérogation par équipement, ou heures de marche quand un compteur existe ? | les deux : compteur s'il existe, sinon calendrier du site |
| Q5 | **Packs** : 4 niveaux (Essentiel, Pro mono-site, Multisite, Entreprise) ? | oui, prix à fixer |
| Q6 | Le technicien peut-il **qualifier** (nature, priorité) quand il intervient de lui-même ? | proposition seulement, validée par le responsable |
| Q7 | Le **journal d'audit** est-il visible des techniciens ? | non : responsable, pilote, administrateur du client |
| Q8 | Ordinateur : faut-il une **vue planification** (semaine, par technicien) dès le pilote ? | oui pour le responsable, version simple |

## 13. Décisions de Hicham (7 nov. 2026)

| # | Décision | Conséquence dans la refonte |
|---|---|---|
| Q1 | **Administrateur du client** : nouveau rôle qui invite et gère les membres, les sites et l'abonnement de son entreprise (souvent le responsable maintenance, pas forcément). Perfora n'invite que le premier administrateur. | R3 : rôle « admin client », écran Entreprise ; le responsable maintenance garde le métier |
| Q2 | Le besoin exprimé est **celui qui lance l'achat au fournisseur** : c'est le rôle **Achats**, qui existe déjà mais reste peu visible. | R1 : rôle Achats mis en avant (barre, accueil, invitation) |
| Q2 bis | **Rôle Achats + repli** : si l'entreprise n'a pas d'acheteur, le responsable (ou le magasinier, selon un réglage de l'entreprise) passe la commande. | R5 : réglage « qui commande » ; commande possible par le repli désigné |
| Q3 | Le **prestataire** ne voit **que ses interventions** (et peut signaler sur le parc). | R1 : vue et droits de lecture du prestataire restreints (serveur + appli) |
| Q4 | **Temps d'ouverture = calendrier du site** (ex. 2×8, 5 j / 7), le même pour tous les équipements du site. | R4 : calendrier de production par site ; MTBF et disponibilité calculés dessus (estimés si calendrier non saisi) |
| Q5 | **4 packs** : Essentiel (1 site) · Pro (1 site, + magasin, compteurs, indicateurs) · **Multisite** (2 à 5 sites, vue consolidée) · Entreprise (illimité, + achats, énergie, imports). Prix fixés ensuite par Hicham. | R8 : packs et quotas mis à jour (production et recette), écran console |
| Q6 | Le technicien **propose** nature et priorité ; le **responsable valide** (trace au journal). | R2 : qualification « proposée » / « validée » sur l'intervention |
| Q7 | **Journal d'audit restreint** : responsable, direction, administrateur du client ; le technicien garde l'historique de ses fiches. | R1 : lecture du journal restreinte côté serveur |
| Q8 | **Planification de la semaine** (qui fait quoi quand), version simple pour le responsable, **dès le pilote**. | nouveau lot R9 |
| Q9 | **Temps des intervenants : jamais suivis.** **Arrêts de production : suivis** (début, remise à disposition), en distinguant **planifié** (préventif, arrêt programmé, travaux prévus) et **non planifié** (panne). Le type est proposé selon la nature de l'intervention (préventive / travaux → planifié ; corrective → non planifié) et modifiable. Indicateurs : **MTBF** = (temps d'ouverture du calendrier du site − arrêts non planifiés) ÷ nombre de pannes ; **MTTR** = durée moyenne des arrêts non planifiés (pannes bornées) ; **disponibilité** = (ouverture − tous les arrêts) ÷ ouverture, avec la part planifiée / non planifiée ; pannes non bornées comptées à part (« n sur m connues »). (Corrigé le 7 nov. : une première version retirait le suivi des arrêts.) | R2 : bloc « Arrêt de production » = oui / non + planifié / non planifié + début et fin (facultatifs, mais demandés à la clôture d'une panne) ; R4 : MTBF, MTTR, disponibilité par équipement et par site |

### Plan de refonte mis à jour (avant le pilote)

| Ordre | Lot | Contenu | Effort indicatif |
|---|---|---|---|
| 1 | ✅ **R1 Navigation et droits par rôle** (v36, 7 nov.) | barre du bas, accueil et menu par rôle ; Réglages éclatés (Mon compte · Entreprise · Données) ; rôle Achats visible ; prestataire limité à ses interventions ; journal restreint ; un seul bandeau | 4 – 5 jours |
| 2 | ✅ **R2 Fiche intervention en étapes** (v37, 7 nov.) | Préparer / Réaliser / Terminer ; qualification proposée puis validée ; activités fréquentes ; une seule liste de pièces ; saisie rapide ; Signaler allégé | 3 – 4 jours |
| 3 | ✅ **R3 Membres, équipes, administrateur du client** (v38, 7 nov.) | une seule notion « membre » (avec ou sans compte), équipes, société prestataire, rôle admin client, invitations par l'admin client | 3 – 4 jours |
| 4 | ✅ **R5 Magasin ↔ achats relié** (v40, 7 nov.) | pièce indisponible → achat lié → réservation à la réception → attente levée ; achat urgent ; « qui commande » (Achats ou repli) | 2 – 3 jours |
| 5 | **R4 Tableaux de bord, MTBF / MTTR / disponibilité** | calendrier de production par site ; arrêts planifiés et non planifiés ; MTBF et MTTR sur les arrêts non planifiés ; disponibilité avec la part planifiée / non planifiée ; définitions affichées ; tableaux de bord responsable / direction / technicien ; indicateurs sur la fiche équipement ; résumé énergie du mois | 4 – 5 jours |
| 6 | **R9 Planification de la semaine** | vue semaine par technicien / équipe, glisser une intervention sur un créneau, charge du préventif | 2 – 3 jours |
| 7 | R8 Packs (4 niveaux) | packs et quotas, console | 1 jour |
| après | R7 QR · R6 fiche équipement et classification · C bis | selon le client pilote | — |

Environ **4 semaines** pour R1 à R9 + R8. Méthode : pour chaque lot, **maquettes écran par écran** (téléphone et
ordinateur) validées par Hicham avant de coder ; tests par rôle à la fin de chaque lot.
Questions restant ouvertes : prix des 4 packs (Hicham) ; réglage par défaut du repli « qui commande » (responsable ou
magasinier).
