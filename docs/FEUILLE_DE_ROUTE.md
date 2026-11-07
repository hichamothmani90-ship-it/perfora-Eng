# GMAO terrain (Perfora) — feuille de route

> **Planning actualisé (7 nov. 2026, v32)** : où on en est et chemin vers le pilote (prochaine étape : D4 écran Énergie) — [`PLANNING_ACTUALISE.md`](PLANNING_ACTUALISE.md).
> **Production et sauvegarde** : construire une base neuve, sauvegarde quotidienne chiffrée, restauration — [`PRODUCTION_ET_SAUVEGARDE.md`](PRODUCTION_ET_SAUVEGARDE.md).

État au 6 novembre 2026. Référence métier : *Perfora V3 — Procédure terrain, SaaS et modèle de données*
(PR MAINT 01 V3, 3 nov. 2026). Règles de conception : [`.claude/skills/gmao-perfora/SKILL.md`](../.claude/skills/gmao-perfora/SKILL.md).

## 1. Ce qui est fait

| Lot | Contenu | État |
|---|---|---|
| Socle | PWA mobile-first, hors ligne, sans dépendance : signalement < 30 s, interventions sans chronomètre, préventif, magasin simple, indicateurs par équipement, journal d'audit append-only | En ligne |
| Lot 0 | Règles et indicateurs testés (S01–S08, 25 tests), QR codes hors ligne + planche imprimable, photos, rappel de sauvegarde | En ligne |
| Lot 1 | Synchronisation cloud offline-first (Supabase), fusion champ par champ, invitations et mot de passe par e-mail | En ligne, validé sur 2 appareils |
| Lot 1 · étape 2 | Rôles contrôlés par le serveur (responsable, technicien, prestataire, magasinier, exploitation, pilote), équipe gérée dans l'appli | En ligne (v14) |
| Volet A · A1 | Serveur multi-entreprise : entreprises, sites, packs, abonnements, lecture et écriture limitées à l'entreprise et aux sites autorisés, modules du pack, abonnement suspendu = lecture seule. Données actuelles = « Perfora Démo » / « Site Tanger » (pack Pro) | En place sur Supabase, testé (12 tests d'étanchéité) |
| Volet A · A2 | Appli multi-site : site actif et sélecteur (« tous mes sites »), créations rattachées au site du parent ou au site actif, appareil vidé au changement d'entreprise (refusé si saisies en attente), resynchronisation complète au premier passage, menus selon les modules du pack, abonnement suspendu = consultation seule | v15, testé avec le faux serveur (2 entreprises, 2 sites, 2 appareils) |
| Volet A · A3 | Quotas par déclencheurs (utilisateurs par entreprise et par site, sites), invitation depuis l'appli par la fonction serveur `inviter` (seule détentrice de la clé secrète), affectation des sites, compteur de places | v17 en ligne ; quotas testés sur Supabase (12 tests) ; invitation réelle validée de bout en bout le 6 nov. 2026 |
| Volet A · A4 | Console plateforme (administrateur) : clients avec usage, création d'entreprise + premier site + invitation du responsable, abonnement / statut / échéance / dérogations, ajout de site, démo commerciale réinitialisable (appareils resynchronisés d'eux-mêmes) | v18 ; 11 tests sur Supabase ; console testée avec le faux serveur ; démo « Vitrine Perfora » créée et ouverte |
| Volet A · A5 | Recette complète : 25 + 35 tests conformes, accès sans compte entièrement fermé, durcissement (`supabase/durcissement.sql`), conseiller sécurité 0 erreur — voir [`RECETTE_VOLET_A.md`](RECETTE_VOLET_A.md) | ✅ Volet A terminé |
| Volet B · B1 | Calculs du magasin relié au terrain (stock physique / réservé / disponible par site, état du besoin déduit des remises, contrôle remis = utilisé + retourné + détenu, retraits urgents à vérifier) | 33 tests verts (25 + 8) ; pas encore branché à l'interface |
| Volet B · B2 | Serveur : type « besoins », réservation réservée au magasin, terrain limité au retrait urgent et au retour, mouvements non modifiables (sauf vérification), site hérité de l'intervention | En place sur Supabase, 15 tests conformes ; appli v18 inchangée et compatible |
| Volet B · B3 | Intervention : section « Pièces » — demander (article ou hors catalogue, urgent, mise en attente liée), retrait urgent (« à vérifier »), J'ai utilisé, Je rends, annuler ; attente « pièce » levée d'elle-même à la remise complète (fin = date de la remise, intervention « Prête ») ; avertissement non bloquant à la clôture si des pièces restent en main ; stockage local v4 (`besoins`) | v19 en local (pas encore publiée) ; 35 tests verts ; scénario 2 appareils passé avec le faux serveur (refus de réservation par le technicien, remise partielle puis complète, retour, retrait urgent, clôture). Ajout à `magasin.sql` : renvoi identique d'un mouvement accepté sans effet — **à exécuter sur Supabase en B5** |
| Volet B · B4 | Magasin : onglets **À servir** (urgents puis plus anciens ; Réserver, Remettre, Indisponible + délai, Rattacher un besoin hors catalogue), **À vérifier** (retraits urgents → « Vérifié », quantité jamais modifiée), **Stock** (physique / réservé / disponible par site, sous le mini) ; accueil du magasinier ; réception et inventaire exigent un site précis. Écrans sortis dans `js/vues/magasin.js` (objet `App`) | v19 locale (branche `volet-b`) ; 37 tests verts ; scénario 3 appareils (technicien, magasinier, responsable) passé avec le faux serveur, aucun refus |
| Volet B · B5 | Supabase : `magasin.sql` mis à jour (renvoi identique accepté), 16 tests magasin + 12 tests d'étanchéité conformes ; démo commerciale enrichie (rouleau demandé en urgence, retrait d'huile à vérifier) testée sur une entreprise temporaire (`tests_demo.sql`) ; guide de démo à jour ; publication v19 | ✅ Volet B terminé |
| Volet C · C1 | Calculs : seuil actif (validé, sinon repère stockMin), couverture = disponible − besoins non couverts + en commande, récapitulatif trié (rupture, critique, écart), réception partielle (reçu = utilisable + isolé, reliquat), pièces isolées et décisions, état d'achat déduit des réceptions, CUMP mobile par site avec coûts figés, prix inconnu ≠ 0 | 47 tests verts (37 + 10) ; branche `volet-c`, rien de publié |
| Volet C · C2 | Serveur : types seuils / achats / valorisations, rôle « achats », prix lisibles seulement par responsable, magasinier, achats, pilote (fiches et journal), validation des seuils et des demandes d'achat par le responsable, correction de prix réservée au responsable | `achats.sql` en place sur Supabase ; 21 tests conformes ; non-régression magasin 16/16 et étanchéité 12/12 ; appli v19 inchangée et compatible |
| Volet C · C3 | Seuils par article et site (proposer, valider, refuser, historique, seuil indicatif), onglet « À réapprovisionner » + export CSV, demande d'achat en brouillon puis soumise ; accueil magasinier « À réapprovisionner » | v20 locale (branche `volet-c`) ; 48 tests verts ; scénario 3 appareils avec le faux serveur : auto-validation du magasinier refusée, validation du responsable, récapitulatif juste (joint : couverture 2 < 4, proposé 6), technicien : 0 demande d'achat et 0 ligne de journal d'achat reçues ; 375 px sans débordement |
| Volet C · C4 | Écran Achats (validation, commande externe par le rôle achats, réception partielle avec isolé, décisions sur isolés, clôture avec reliquat motivé), Valeur du stock (CUMP, non valorisé visible), accueil du rôle achats | v20 locale (branche `volet-c`) ; 50 tests verts ; scénario 4 rôles avec le faux serveur : demande → validation → commande 6 × 100 MAD → réception 4 dont 1 isolée (reste 2, stock 5, couverture 7) → libération → solde → reçue → close (stock 8), aucun refus ; technicien : 0 demande, 0 prix, 0 ligne de journal de coûts, stock 8 visible ; 375 px sans débordement |
| Volet C · C5 | Démo commerciale et démo locale enrichies (prix des entrées dont un provisoire, seuil validé du joint, seuil proposé du filtre, commande DA-DEMO-0001 à réceptionner) — `supabase/demo.sql` (remplace la fonction de plateforme.sql) + `tests_demo.sql` à jour ; guide de démonstration ; publication v20 | ✅ Volet C terminé ; démo testée sur entreprise temporaire (39 fiches) ; 50 tests verts |

Adresses : appli <https://hichamothmani90-ship-it.github.io/perfora-Eng/> · code <https://github.com/hichamothmani90-ship-it/perfora-Eng> ·
Supabase projet `gmao-terrain` (réf. `oihaqzkqhvyjybijsonc`, Frankfurt).

## 2. Volets à venir

Ordre recommandé : **A → B → C → D → E**, le volet **H** (démo et commercial) avance en parallèle.
Raison : le multi-entreprise touche toutes les données ; l'ajouter après le magasin et l'énergie
coûterait une reprise de chaque table et de chaque règle.

### Volet A — Socle SaaS multi-entreprise (multitenant), packs et quotas  · ~3 semaines
Objectif : plusieurs clients isolés sur la même plateforme, chacun avec ses sites, ses utilisateurs et son pack.

- **Modèle** : `entreprises` (client), `sites`, `abonnements` (pack, dates, état), `profils` rattachés à une
  entreprise + sites autorisés. Chaque fiche porte `entreprise_id` et `site_id` (colonnes, posées par le serveur).
- **Isolation** : règles RLS par entreprise et par site ; `push_fiches` refuse toute écriture hors périmètre.
  Tests d'étanchéité automatiques (un utilisateur de A ne voit jamais B, même par l'API).
- **Packs et quotas** (contrôlés côté serveur, jamais seulement à l'écran) :
  - nombre d'utilisateurs actifs **par site** et **par entreprise** selon le pack ;
  - nombre de sites ; modules activés (magasin, achats, énergie) ; volume de photos.
  - Invitation depuis l'appli via une fonction serveur (Edge Function) qui vérifie le quota avant d'envoyer l'e-mail.
  - Dépassement : invitation refusée avec message clair ; désactiver un compte libère une place.
- **Rôles à deux niveaux** : administrateur plateforme (vous) / administrateur client (responsable) / rôles terrain.
- **Sélecteur de site** dans l'appli pour les personnes multi-sites ; données hors ligne limitées aux sites autorisés.
- Proposition de packs (à valider commercialement) :

  | Pack | Sites | Utilisateurs / site | Modules |
  |---|---|---|---|
  | Essentiel | 1 | 5 | Demandes, interventions, préventif, QR |
  | Pro | 3 | 15 | + magasin, photos étendues, rapports |
  | Entreprise | sur devis | sur devis | + achats, énergie et eau, imports, API |

- Décision à prendre : garder la table unique `fiches` (jsonb, simple pour la synchro) **ou** passer à des tables
  typées pour le magasin, les achats et l'énergie (requêtes et rapports plus solides). Recommandation : tables
  typées pour ces nouveaux volets, synchronisées par le même mécanisme.

### Volet B — Magasin en lien avec le terrain  · ~2-3 semaines  (V3 §6, §15 demander / remettre / utiliser / retourner, §16 réceptionner / isoler / inventorier, §35)
- **Besoin matériel** depuis l'intervention (article ou description libre, quantité, unité) : la demande ne consomme pas le stock.
- **Réservation** par le magasinier, **remise** physique, **utilisation**, **retour**, rebut : cinq faits distincts, un seul mouvement par fait.
- **Retrait urgent** par une personne autorisée, marqué « à vérifier » puis vérifié par le magasinier.
- Lien avec l'attente : une intervention « en attente de pièce » pointe vers le besoin ; levée automatique quand la pièce est remise.
- Stock par magasin et emplacement, états utilisable / isolé / à réparer ; compatibilité article ↔ équipement.
- Inventaire tournant avec écart justifié ; pièces consommées par équipement (déjà en indicateur).
- Prix masqués aux techniciens.

### Volet C — Magasin et achats : définition des stocks et réapprovisionnement  · ~2 semaines  (V3 §14 articles et seuils, §17 besoins achats, §18 valorisation, §35)
- **Définition des stocks** par article et magasin : stock de sécurité, point de commande (seuil), stock cible (maxi),
  délai de réapprovisionnement de référence, article critique (lié aux équipements critiques), justification et validateur.
- **Récapitulatif « à réapprovisionner »** : `disponible = physique utilisable − réservé` ; alerte quand
  `disponible + en commande < point de commande` ; quantité proposée = `cible − (disponible + en commande)`.
  Tri par criticité et rupture ; export Excel pour l'acheteur.
- **Circuit achat limité** : demande d'achat → validation (délégation) → commande externe (fournisseur, référence,
  délai, quantités) → réceptions partielles → contrôle / isolement → mise en stock.
- **Valorisation** : coût moyen pondéré (CUMP), coût inconnu signalé (jamais zéro), historique figé sur les mouvements.
- Profil « Achats » facultatif (V3 §24).
- **Proposition détaillée** : [`VOLET_C_CONCEPTION.md`](VOLET_C_CONCEPTION.md) (choix à valider, étapes C1 à C5).

### Volet D — Énergie et eau  · ~3 semaines  (V3 §19 mesures énergie et eau, §20 rapprochements, §36)
- **Compteurs** : ressource (électricité, gaz, eau, air, fioul…), mode (cumulatif, par période, instantané), unité,
  coefficient, périmètre, compteur parent / sous-compteurs, fréquence de relevé, photo obligatoire ou non.
- **Relevés terrain** hors ligne, par QR code du compteur, avec photo ; tournée de relevés à faire.
- **Contrôles automatiques** : baisse d'index, variation anormale, doublon, unité, relevé manquant ; un relevé suspect
  est isolé des calculs jusqu'à décision (jamais supprimé ni interpolé en silence).
- **Ruptures** : remplacement ou remise à zéro du compteur (ancien index final / nouvel index initial).
- **Consommations** par période, usage et site ; jamais d'addition entre unités différentes ; sous-compteurs ≠ total site.
- **Factures** et rapprochement facturé / mesuré ; coûts ; ratios facultatifs (kWh par tonne produite) si donnée de production fournie.
- Tableau de bord énergie ; lien avec actions (fuite d'air → intervention).
- **Conception** : [`VOLET_D_CONCEPTION.md`](VOLET_D_CONCEPTION.md) (choix validés le 6 nov. 2026, étapes D1 à D5 ; D1 fait).
- **Avant D3** : simplification du parcours demande → intervention, faite (v23) : [`PARCOURS_DEMANDE_INTERVENTION.md`](PARCOURS_DEMANDE_INTERVENTION.md).
- **D2 fait (v24)** : serveur énergie + réglage « clôture validée par le responsable ».
- **Classification du parc** (validée ; écrans à faire) : [`CLASSIFICATION_PARC.md`](CLASSIFICATION_PARC.md).
- **Centre de contrôle** (CC1 + CC2 faits, v27 : `app.perfora.ma/console/`) : [`CENTRE_CONTROLE_CONCEPTION.md`](CENTRE_CONTROLE_CONCEPTION.md).
- **Mise en service des clients** (v25, fait) : kit Excel + page de la console : [`MISE_EN_SERVICE_CLIENT.md`](MISE_EN_SERVICE_CLIENT.md).
- **Avant D3** : discussion du modèle de données (magasin, achats, compteurs de ressources et d'équipements) : [`DISCUSSION_MODELE_DONNEES.md`](DISCUSSION_MODELE_DONNEES.md).

### Volet E — Pilotage avancé et rapports  · ~2 semaines  (V3 §10-11, §26, §29)
- Calendriers de temps requis ; disponibilité sur requis ; MTTR « délai de rétablissement calendaire » ; MTBF seulement avec heures de marche.
- Objectifs par équipement ; rapport mensuel PDF + export Excel détaillé ; qualité des données.

### Volet F — Imports Excel contrôlés  · ~1-2 semaines  (V3 §27-28)
Classeur modèle (sites, équipements, articles, compteurs, programmes) ; prévisualisation, conflits, aucune suppression par absence.

### Volet G — Industrialisation (en continu, avant tout client payant)
- **E-mails d'invitation par un service d'envoi dédié** (Brevo, Resend…) avec l'adresse d'expéditeur de la marque :
  l'envoi par défaut de Supabase est limité (quelques e-mails par heure) et classé en indésirable par Outlook
  (constaté le 6 nov. 2026 ; l'invitation réelle a fonctionné une fois l'e-mail retrouvé).
- Photos dans Supabase Storage (et non dans la base).
- Environnements séparés : **recette** (projet `Perfora-recette` existant) et **production** ; migrations SQL numérotées.
- Base de production propre (sans données de démo) ; sauvegarde quotidienne ; offre Supabase payante.
- Conformité : formalités CNDP (loi 09-08) pour l'hébergement des données personnelles ; mentions et contrat.
- Tests de bout en bout automatisés (deux appareils, hors ligne, droits) ; supervision des erreurs.

### Volet H — Démonstration et commercialisation (en parallèle)
- **Entreprise de démonstration** isolée (volet A) avec un jeu de données crédible et réinitialisable.
- Script de démo de 10 minutes : voir [`GUIDE_FONCTIONNEMENT.md`](GUIDE_FONCTIONNEMENT.md).
- Page de présentation (bénéfices, packs, contact), fiche PDF, vidéo courte téléphone + PC.
- Pilote terrain gratuit de 4 à 6 semaines chez un premier site, avec indicateurs avant / après.

## 2 ter. Cadrage du lancement
Domaine perfora.ma, hébergement, CNDP, Payzone, packs, site de présentation, préréglages, WhatsApp, rôles, tableaux de bord,
sécurité, authentification, parcours et planning en phases : [`CADRAGE_LANCEMENT.md`](CADRAGE_LANCEMENT.md).

## 2 bis. Avant le premier client payant
Liste de contrôle détaillée : [`RECETTE_VOLET_A.md` §4](RECETTE_VOLET_A.md) — e-mails dédiés, Supabase payant, projet de production séparé, photos en stockage de fichiers, nom de domaine, CNDP, exports, pilote.

## 3. Décisions à prendre (vous)
1. Packs, limites et prix (tableau du volet A à confirmer).
2. Tables typées pour magasin / achats / énergie (recommandé) ou maintien du modèle jsonb unique.
3. Hébergement de production (Supabase payant en Europe) et validation CNDP.
4. Nom commercial (Perfora ?) et domaine propre (ex. app.perfora.ma) à la place de github.io.
5. Premier site pilote et interlocuteurs (maintenance, exploitation, magasin).
