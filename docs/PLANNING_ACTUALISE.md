# Perfora — planning actualisé (7 nov. 2026)

Priorités fixées : **1. stabilité, 2. sécurité, 3. expérience d'inscription et de connexion**, regroupées avec le reste.
Les semaines (S1 = semaine qui suit la validation) sont indicatives. Les fonctions nouvelles attendent que les phases 1 et 2
soient faites.

## 0. Où on en est (7 nov. 2026, appli v35 sur app.perfora.ma)

**Fait** : socle multi-entreprise (volet A), magasin et achats (B, C), parcours demande → intervention, domaine
perfora.ma, kit Excel et mise en service, centre de contrôle, hors ligne éprouvé (v28), écran de connexion et démo
séparée (v29 – v30), fichiers joints photos et PDF (v31), **énergie et eau complètes** (v32 – v34), **séquence SQL de
production et sauvegarde chiffrée testées** (étape 5), **sécurité** (v35 : double authentification de l'administrateur
**activée le 7 nov.**, journal des actions, limites d'envoi, règles de mot de passe, remontée des erreurs).

**État de santé (contrôle du 7 nov.)** : 90 tests de calcul, 13 fichiers de tests SQL conformes sur une base neuve,
serveur factice conforme (sécurité 14/14, fichiers 13/13, énergie 36/36) ; schéma de la recette identique à celui que
construit la séquence (62 fonctions) ; conseiller sécurité Supabase : **0 erreur** (41 avertissements acceptés :
fonctions appelables par un compte connecté qui vérifient elles-mêmes rôle, entreprise et site ; 1 réservé à l'offre
Pro) ; aucune fonction appelable sans compte ; aucune erreur remontée par les appareils ; base 13 Mo.
Seul bruit en ligne : le script de statistiques Cloudflare, bloqué par la politique de sécurité (voir A6).

**Refonte de l'organisation (audit du 7 nov., docs/AUDIT_UX_MODELE_DONNEES.md)** : lots R1 → R2 → R3 → R5 → R4 → R9 → R8
avant le pilote (≈ 4 semaines). **R1 fait (v36)** : navigation, accueils et menus par rôle, Mon compte / Entreprise,
droit administrateur de l'entreprise, prestataire limité à ses interventions, journal restreint. **R2 fait (v37)** : fiche
intervention en étapes, qualification proposée / validée, arrêts planifiés / non planifiés, saisie rapide, Signaler en
trois questions. **R3 fait (v38)** : une seule liste de membres (avec ou sans accès), équipes, sociétés prestataires, habilitations,
accès donnés par l'administrateur depuis la fiche du membre. Prochain : **R5** (magasin ↔ achats relié ; maquettes d'abord).

## 0 bis. Plan actualisé jusqu'au pilote

### A. Préparatifs (Hicham, courts, à faire maintenant — détails dans docs/SECURITE.md et docs/PRODUCTION_ET_SAUVEGARDE.md)

| # | Action | Durée | Débloque |
|---|---|---|---|
| A1 | Dépôt GitHub **privé** des sauvegardes + 4 secrets, premier lancement manuel | 20 min | sauvegarde de nuit, test de restauration réelle |
| A2 | Supabase → Authentication → Email : mot de passe 10 caractères, lettres et chiffres | 2 min | ✅ appli (v35) ; réglage Supabase : toi (A2) |
| A3 | Sonde de disponibilité gratuite (UptimeRobot) sur app.perfora.ma | 5 min | alerte si le site tombe |
| A4 | Adresse d'administration dédiée (ex. admin@perfora.ma, qui reçoit le courrier) | 10 min | compte admin séparé (2.1) |
| A5 | **Créer le projet Supabase de production** (gratuit, Frankfurt) et me le dire | 10 min | étape B |
| A6 | Cloudflare : désactiver Web Analytics sur app.perfora.ma (garder sur perfora.ma si voulu) ; supprimer les clés Resend inutilisées | 5 min | ménage 2.7 |

### B. Production (moi, 1 – 2 jours, dès A5)

1. Construire la base avec `supabase/production/construire_base.sql`, contrôles de fin, empreinte comparée à la recette.
2. Réglages Auth (adresse du site, modèles d'e-mail en français, SMTP Resend, mots de passe) ; fonction d'invitation
   déployée (clé secrète saisie par toi) ; administrateur = adresse dédiée + double authentification.
3. Tests d'étanchéité et de sécurité rejoués sur la production, puis fonctions de test supprimées ; sauvegarde de nuit
   branchée sur la production et **restauration réelle testée** en local.
4. **Décision à prendre à ce moment** : app.perfora.ma → production ; la recette (démos, tests) passe sur une adresse à
   part (ex. recette.perfora.ma) avec sa propre configuration.

### C. Avant le premier client (moi, 4 – 5 jours)

| # | Chantier | Pourquoi avant le pilote |
|---|---|---|
| C1 | **Revue de sécurité** (2.6) : conseiller à 0 erreur sur la production, tentatives d'accès entre entreprises et sans compte, petit test d'intrusion | données réelles |
| C2 | **Première connexion guidée** (3.2) : mot de passe → « Ajouter à l'écran d'accueil » (**indispensable sur iPhone**, §7.1) → site → visite de 3 écrans | les techniciens du pilote s'installent seuls |
| C3 | **Mon compte** (3.6) : changer son mot de passe, se déconnecter de partout, nom et téléphone | autonomie, sécurité |
| C4 | **Export complet des données d'un client** (4.6, réversibilité) | promesse contractuelle |
| C5 | Test T7 iPhone (8 jours hors usage, vers le 15 nov.) : vérifier qu'aucune donnée ne se perd | avec Hicham |

### D. Conditions du pilote (Hicham, en parallèle)

Dépôt **CNDP** (bloquant pour des données réelles), client pilote choisi (pack Entreprise ou module énergie accordé),
CGU / confidentialité / contrat simple, prix des packs (grille du centre de contrôle), modèle de facture avec le comptable.

### E. Pilote (4 – 6 semaines, gratuit, un site)

Mise en service avec le kit Excel, formation courte par rôle, point hebdomadaire (onglet Technique, demandes de
support), corrections rapides, indicateurs avant / après, premier témoignage.

### F. Après le pilote (selon les retours)

CC3 facturation (après le comptable) puis CC4 Payzone ; invitation par WhatsApp (3.3), premiers pas du responsable (3.4),
« Demander un essai » sur perfora.ma (3.5) ; classification du parc à l'écran ; inventaire du magasin (C bis) ; volet E
(rapports mensuels, ratios de production) ; bilan des cuves ; avertissement si deux téléphones modifient le même champ ;
aide intégrée ; langue arabe ; passage de la production en **Supabase Pro** dès le premier client payant (§8).

## 1. Phase « Stabilité » (S1 – S3) — priorité 1

| # | Chantier | Pourquoi | Qui |
|---|---|---|---|
| 1.1 | **Projet Supabase de production séparé** du projet actuel (qui devient la recette), avec **scripts SQL numérotés** (migrations) au lieu de scripts rejouables à passer dans un ordre précis | Aujourd'hui démo, tests et futurs clients partagent la même base ; un essai peut toucher un client | moi + toi (souscription) |
| 1.2 | **Fichiers joints dans Supabase Storage** (et non dans la base) : **photos et PDF** (factures d'énergie et d'eau, rapports de vérification réglementaire, certificats, notices, bons de livraison), taille limitée par fichier et quota par pack ; lecture restreinte pour les fichiers de coûts (factures) ; consultation hors ligne des fichiers déjà ouverts | Les fichiers en base font grossir la synchronisation et la sauvegarde : premier risque de lenteur ; les PDF sont indispensables aux factures (volet D) et aux contrôles réglementaires | moi |
| 1.3 | **Sauvegarde quotidienne + test de restauration** documenté (offre Supabase Pro) | Sans test de restauration, une sauvegarde n'est qu'un espoir | moi + toi (offre) |
| 1.4 | **Supervision** : erreurs de l'appli et refus du serveur remontés dans un onglet « Technique » du centre de contrôle ; alerte si le site ne répond plus | Savoir qu'un client est bloqué avant qu'il appelle | ✅ v35 (erreurs et refus → console Technique ; disponibilité : sonde externe, Hicham) |
| 1.5 | **Tests automatisés de bout en bout** (deux appareils, hors ligne puis retour du réseau, droits par rôle) lancés avant chaque publication | Les tests actuels sont surtout manuels dans le navigateur | moi |
| 1.6 | **Mises à jour sans surprise** : réglage Cloudflare « Browser Cache TTL → Respect Existing Headers », message « nouvelle version » fiable, numéro de version visible | Le cache de 4 h de Cloudflare a déjà servi une ancienne console | toi (1 clic) + moi |
| 1.0 | ✅ **Faite le 7 nov. 2026 (v28)** — 12 scénarios, 4 défauts corrigés ; essai sur téléphone réussi après correction de la connexion (v29 – v30) ; reste T7 (iPhone 8 jours) : [`TESTS_HORS_LIGNE.md`](TESTS_HORS_LIGNE.md). **Campagne de tests hors ligne**, sur vrais téléphones (Android et iPhone) et en automatique : voir le détail ci-dessous | Le hors ligne est la promesse de Perfora : il doit être prouvé, pas supposé | moi + toi (téléphones) |
| 1.7 | **Volumes réalistes** : essai avec 2 000 équipements, 20 000 fiches et un téléphone d'entrée de gamme (chargement, recherche, synchronisation) | L'appli charge tout en mémoire : à mesurer avant un gros client | moi |

### Détail de la campagne hors ligne (1.0)

| Scénario | Résultat attendu |
|---|---|
| Ouvrir l'appli en mode avion (déjà installée) | L'appli s'ouvre, toutes les données du site sont là |
| Signaler, démarrer et clôturer une intervention, prendre 3 photos, demander une pièce, saisir un relevé, tout en mode avion | Tout est enregistré sur le téléphone, compteur « en attente d'envoi » visible |
| Retour du réseau | Envoi automatique, « ☁ À jour », rien de perdu ni en double |
| Deux téléphones hors ligne modifient la même intervention, puis reviennent en ligne | Règle de fusion appliquée, aucune saisie perdue, l'historique montre les deux |
| Réseau très faible (2G, coupures pendant l'envoi) | Pas de blocage ; reprise propre au prochain essai |
| Téléphone éteint ou appli fermée pendant l'attente d'envoi | Les saisies sont toujours là au redémarrage, puis envoyées |
| Saisie refusée par le serveur au retour (droits changés, intervention clôturée entre-temps) | Message clair, version du serveur rétablie, pas de boucle d'erreurs |
| Plusieurs jours hors ligne (100 saisies et 30 photos en attente) | Envoi complet par lots, téléphone utilisable pendant l'envoi |
| Session expirée pendant la période hors ligne | Reconnexion demandée sans perdre les saisies en attente |
| Nouvelle version publiée pendant que le téléphone est hors ligne | Mise à jour proposée au retour, saisies en attente conservées |
| iPhone : appli installée sur l'écran d'accueil, 8 jours sans ouverture | Données toujours présentes (et mesure de ce qui se passe sans installation) |

## 2. Phase « Sécurité » (S2 – S4) — priorité 2

| # | Chantier | Qui |
|---|---|---|
| 2.1 | **Compte administrateur séparé** : ton compte plateforme ne doit plus être aussi responsable de l'entreprise « Perfora Démo » | toi (A4) puis moi (B2) |
| 2.2 | **Double authentification (MFA)** obligatoire pour l'administrateur, proposée aux responsables | ✅ v35, **activée le 7 nov.** pour ton compte |
| 2.3 | **Règles de mot de passe** dans Supabase : 10 caractères minimum, refus des mots de passe compromis (offre Pro), durée de session, confirmation d'e-mail | toi (réglages) + moi (guide) |
| 2.4 | **Journal des actions de l'administrateur** (création d'entreprise, changement d'abonnement, import, annulation de lot) | ✅ v35 (moi) |
| 2.5 | **Limites d'envoi** : invitations et demandes de support par heure et par entreprise (anti-abus) | ✅ v35 (moi) |
| 2.6 | **Revue de sécurité** avant le premier client : conseiller sécurité Supabase à 0 erreur, tests d'étanchéité rejoués sur la production, petit test d'intrusion | moi (C1) ; conseiller sur la recette : 0 erreur le 7 nov. |
| 2.7 | **Ménage** : supprimer les clés Resend inutilisées, retirer le script Cloudflare Web Analytics bloqué par la politique de sécurité (ou l'autoriser), DMARC « quarantine » après quelques semaines d'envois | toi (A6) + moi |

## 3. Phase « Inscription et connexion » (S2 – S4) — priorité 3

Constat : aujourd'hui la connexion se fait dans **Réglages**, avec des champs techniques (adresse du serveur, clé) ; un
nouvel utilisateur arrive sur une appli vide qui propose « Charger la démo ». C'est le point faible de l'expérience.

| # | Chantier |
|---|---|
| 3.1 | ✅ **Fait (v29, 7 nov. 2026)** : écran de connexion à l'ouverture, démo séparée (« Découvrir la démo », jamais envoyée, effacée à la connexion), plus de question d'envoi pour les comptes non responsables. **Écran de connexion dès l'ouverture** : e-mail + mot de passe, « Recevoir un lien de connexion », « Mot de passe oublié », messages d'erreur clairs ; plus aucun champ technique (le serveur est fixé) |
| 3.2 | (avant le pilote : C2) **Première connexion guidée** après invitation : choix du mot de passe → « Ajouter à l'écran d'accueil » (indispensable sur iPhone, voir §6) → choix du site → courte visite de 3 écrans selon le rôle |
| 3.3 | **Invitation par WhatsApp** en plus de l'e-mail (lien à usage unique, valable 24 h) : beaucoup de techniciens n'ouvrent pas leurs e-mails |
| 3.4 | **Premiers pas du responsable** : liste à cocher (inviter l'équipe, imprimer les QR, vérifier les criticités, créer 3 programmes préventifs) |
| 3.5 | **« Demander un essai »** sur perfora.ma : formulaire court qui crée un **prospect** dans le centre de contrôle (avec protection anti-robot), en plus du bouton WhatsApp. Pas d'inscription libre au départ : tu ouvres chaque essai toi-même (décision à confirmer) |
| 3.6 | (avant le pilote : C3) **Changer son mot de passe, se déconnecter de tous les appareils, gérer son profil** (nom, téléphone) |
| 3.7 | **Transition des téléphones** de l'ancienne adresse github.io vers app.perfora.ma, puis fermeture de l'ancienne adresse |

## 4. Conformité et offre (S3 – S6, en parallèle, surtout toi)

| # | Chantier | Qui |
|---|---|---|
| 4.1 | **Dossier CNDP** (loi 09-08) : déclaration des traitements, transfert vers l'Union européenne, prospection | toi + juriste, moi (inventaire technique) |
| 4.2 | **CGU / CGV, politique de confidentialité, contrat de sous-traitance**, mentions légales (7 champs restent à remplir sur perfora.ma) | toi + juriste |
| 4.3 | **Packs et prix** (la grille du centre de contrôle est vide) | toi, je propose des repères |
| 4.4 | **Structure juridique, compte bancaire, modèle de facture validé par ton comptable** | toi |
| 4.5 | **CC3 Facturation** (devis, factures numérotées, avoirs, paiements, export comptable) une fois 4.4 fait | moi |
| 4.6 | **Réversibilité** : export complet des données d'un client (Excel + photos) et procédure de suppression à la fin du contrat | moi |

## 5. Fonctions produit (S5 – S10, après les phases 1 à 3)

| # | Chantier |
|---|---|
| 5.0 | ✅ **Énergie et eau** : D1 – D5 faits (v32 – v34) |
| 5.1 | ✅ D3 (v32) : relevés sur le terrain, compteurs d'équipement, préventif selon l'usage |
| 5.2 | **Classification du parc** à l'écran (catalogue, criticité A/B/C guidée, parent, réglementaire, écran « À classer ») |
| 5.3 | **Inventaire du magasin** (prioritaire dans C bis), puis emplacement, conditionnement, liste des fournisseurs, achats non stockés |
| 5.4 | ✅ D4 – D5 (v33 – v34) : écran Énergie, démo, guide |
| 5.5 | **Aide intégrée** : guide court par rôle, vidéos de 1 minute, page d'aide accessible depuis l'appli |

## 6. Pilote et croissance (S6 et après)

- **Pilote** de 4 à 6 semaines sur un site (gratuit), indicateurs avant / après, premier témoignage, parrainage WhatsApp.
- **CC4 Payzone** (paiement en ligne) après contrat ; **volet E** (rapports mensuels PDF, objectifs, disponibilité) ;
  **imports en libre-service** (pack Entreprise) ; connexion Google / Microsoft pour les grands comptes ; ratios de
  production (kWh par tonne).

## 7. Points oubliés ou à ne pas oublier

1. **iPhone et données hors ligne** : Safari peut effacer les données d'un site non installé après 7 jours sans
   utilisation. L'appli doit être **ajoutée à l'écran d'accueil** sur iPhone (intégré à 3.2) et les saisies non envoyées
   signalées clairement.
2. **Données de démonstration en production** : la nouvelle base de production doit partir vide (DEMO et VITRINE
   restent en recette).
3. **Fin de contrat d'un client** : export, délai de conservation, suppression — à écrire dans le contrat (4.2, 4.6).
4. **Procédure de support** : délai de réponse promis par pack, horaires, qui répond quand tu es indisponible.
5. **Plan de continuité** : que se passe-t-il si Supabase ou Cloudflare tombe ? (l'appli continue hors ligne ; à dire aux
   clients) ; accès de secours à tes comptes (2e facteur, codes de récupération rangés en lieu sûr).
6. **Langues** : français seulement aujourd'hui ; l'arabe (et l'anglais pour certains groupes) est à décider avant
   d'élargir la cible.
7. **Heure du Maroc** : le passage à l'heure d'été et la suspension pendant le ramadan doivent être vérifiés sur les
   dates et durées d'arrêt.
8. **Téléphones partagés** (un appareil pour plusieurs techniciens) : changer d'utilisateur sans perdre les saisies en
   attente.
9. **Comptes de test** sur la base actuelle (`test@`, `tech2@`…) : à ne pas recréer en production.

## 8. Décisions (7 nov. 2026)

1. **Supabase Pro** : 25 USD / mois (prix relevé sur supabase.com le 7 nov. 2026 ; 1 projet inclus, projet supplémentaire
   à partir de 10 USD / mois) : sauvegardes quotidiennes conservées 7 jours, pas de mise en veille, 8 Go de base, support
   par e-mail. **Pas obligatoire techniquement, recommandé dès le premier client réel.** Plan : le projet de production en
   Pro ; la recette (démo, tests) dans une organisation gratuite (elle peut se mettre en veille, sans conséquence).
   **Décision du 7 nov. 2026 : démarrer gratuitement.** Deux projets gratuits (limite de l'offre : 2 projets actifs) :
   recette (l'actuel) et production (créée avant le pilote). Ce que l'offre gratuite ne fournit pas, on le compense :
   - **sauvegarde quotidienne automatique maison** : export chiffré de la base de production chaque nuit (tâche planifiée
     dans un dépôt GitHub **privé**, mot de passe de la base et clé de chiffrement en secrets saisis par Hicham), conservée
     30 jours, avec un test de restauration sur la recette ; l'export quotidien évite aussi la mise en veille après
     7 jours sans activité ;
   - limites à surveiller dans le centre de contrôle : base 500 Mo, fichiers 1 Go (≈ 9 000 photos), 5 Go de trafic / mois ;
   - pas de refus des mots de passe compromis (offre Pro) : règle de longueur et MFA administrateur à la place.
   Passage en Pro (25 USD / mois, un clic, sans migration) dès le premier client payant ou à 70 % d'une limite.
2. **Pas d'inscription libre** : les essais sont ouverts par l'administrateur ; le site propose « Demander un essai »
   (prospect dans le centre de contrôle) et WhatsApp.
3. **MFA** : obligatoire pour l'administrateur seulement.
4. **Langues** : français au lancement ; l'arabe (interface de droite à gauche) décidé après le pilote selon les
   retours des techniciens ; l'anglais à la demande d'un client. L'appli prépare dès maintenant la traduction (textes
   regroupés) pour que l'ajout ne coûte pas une réécriture.
5. **Premier pilote : au plus tôt.** Chemin le plus court vers le pilote : tests hors ligne → production séparée +
   sauvegardes → photos en fichiers → écran de connexion → MFA administrateur → revue de sécurité ; **et, de ton côté,
   le dépôt CNDP**, indispensable avant de saisir les données réelles d'un client.
