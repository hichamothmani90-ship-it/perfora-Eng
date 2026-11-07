# Prompt de reprise — GMAO terrain (Perfora)

À coller au début d'une nouvelle session Claude Code ouverte **dans le dossier du projet**
(le dossier qui contient `index.html`, `js/`, `supabase/`, `docs/`). Remplacer la dernière ligne
par le volet à traiter.

---

```text
Tu reprends le projet GMAO terrain (Perfora). Tu interviens comme expert en gestion de maintenance
industrielle, chef de projet / planning, architecte (modèle de données, offline-first, SaaS
multi-entreprise) et concepteur d'interfaces terrain mobile-first. Langue : français.

1. AVANT TOUTE CHOSE, LIS :
   - .claude/skills/gmao-perfora/SKILL.md  (règles métier non négociables, architecture, modèle,
     parcours, interface, méthode projet, pièges) — il s'applique à tout le travail ;
   - docs/FEUILLE_DE_ROUTE.md  (fait / à faire par volets, décisions en attente) ;
   - README.md, supabase/GUIDE.md, supabase/schema.sql, supabase/roles.sql ;
   - le code : js/store.js (stockage local + journal + file d'envoi), js/sync.js (synchro Supabase,
     comptes), js/calculs.js (règles et indicateurs testés), js/app.js (écrans, droits côté interface),
     js/qr.js, sw.js, tests/.

2. SOURCES MÉTIER (hors dépôt, sur le PC de Hicham) :
   - « Perfora_V3_Procedure_Terrain_SaaS_Modele_Donnees_20261103.docx »
     (Bureau\Perfora) : procédure terrain §2-20, correspondance SaaS §21-29, modèle de données
     §30-36, adoption §37. C'est la référence fonctionnelle ; cite la section utilisée.
   - « gmao (2).zip » (Bureau) : premier socle FastAPI/SQLAlchemy et son CLAUDE.md
     (décision du 6 nov. 2026 : traçabilité légère, pas de chronomètre).
   Si tu as besoin d'un passage précis, demande à lire le fichier.

3. ÉTAT (7 nov. 2026, appli **v37** sur app.perfora.ma) — **lire d'abord docs/PLANNING_ACTUALISE.md** (§0 « où on en est »,
   §0 bis « chemin vers le pilote », §8 décisions). Volet D (énergie et eau) **terminé** (docs/VOLET_D_CONCEPTION.md §7-11). Étapes 5 et 6 faites (docs/PRODUCTION_ET_SAUVEGARDE.md, docs/SECURITE.md).
   Plan à jour : PLANNING_ACTUALISE.md §0 bis (A préparatifs Hicham → B production → C avant le premier client → D/E pilote).
   Prochaine étape : **B — production**, dès que Hicham a créé le projet Supabase de production (A5).
   Refonte en cours (docs/AUDIT_UX_MODELE_DONNEES.md §13) : R1 fait (v36, docs/MAQUETTES_R1.md), R2 fait
   (v37, docs/MAQUETTES_R2.md §10) ; prochain lot **R3** (maquettes d'abord, validées par Hicham avant de coder). Comptes factices ajoutés : presta@ (prestataire), dir@ (direction).
   Administrateur : double authentification ACTIVÉE (7 nov.) : droits seulement en session « aal2 » (code de l'appli d'authentification) ;
   dans le SQL Editor, pour agir en administrateur : claims avec 'aal':'aal2'. Autres repères : docs/TESTS_HORS_LIGNE.md, docs/CENTRE_CONTROLE_CONCEPTION.md, docs/MISE_EN_SERVICE_CLIENT.md,
   docs/CLASSIFICATION_PARC.md, docs/DISCUSSION_MODELE_DONNEES.md.
   - Décisions récentes : offre Supabase gratuite au départ (2 projets : recette actuelle + production créée avant le
     pilote, sauvegarde maison) ; pas d'inscription libre (essais ouverts par l'administrateur) ; MFA administrateur
     seulement ; français au lancement (arabe décidé après le pilote) ; énergie et eau avant le pilote ; rester sur
     Supabase (pas Neon).
   - Comptes de recette : DEMO « Perfora Démo » et VITRINE sont des **démos** (demo = true, réinitialisables, 110 fiches dont l’énergie) ;
     compte technicien de test hicham.othmani90.tech@gmail.com (VITRINE). Faux serveur actuel : port 8093 (comptes test@,
     tech2@, tech3@ technicien Tanger, mag@, achat@, expl@, autre@ ; mot de passe test-gmao ; réseau simulé par
     `python tests/reseau.py 8093 panne|normal|lent|coupures|portail`). Appli locale : ports 8081 et 8082 (deux appareils).
   - Historique (avant le 7 nov.) : volets A, B et C terminés — détail : docs/FEUILLE_DE_ROUTE.md et docs/RECETTE_VOLET_A.md
   - Appli PWA statique, hors ligne, sans dépendance, sur GitHub Pages :
     https://hichamothmani90-ship-it.github.io/perfora-Eng/ (dépôt hichamothmani90-ship-it/perfora-Eng,
     branche main ; chaque push publie en ~5 min ; si le déploiement Pages échoue, pousser un commit vide).
     Copie de travail : Bureau\Claude Perfora\gmao-terrain (clone git complet, skill inclus).
   - Fait : lot 0 (tests, QR, photos), lot 1 (synchro Supabase, invitations, rôles), volet A complet
     (multi-entreprise, multi-site, packs et quotas, invitation depuis l'appli, console plateforme,
     démo réinitialisable, recette + durcissement). Volet B terminé (docs/VOLET_B_CONCEPTION.md) : magasin relié au
     terrain, écrans Magasin dans js/vues/magasin.js. Volet C terminé (docs/VOLET_C_CONCEPTION.md) : seuils, à
     réapprovisionner, achats, réception partielle, isolés, valeur du stock ; prix lisibles seulement par responsable,
     magasinier, achats, pilote. Cadrage du lancement : docs/CADRAGE_LANCEMENT.md ;
     phase 1 faite : https://app.perfora.ma (appli, Cloudflare Pages perfora-app) et https://perfora.ma
     (site, dépôt perfora-site) en ligne ; DNS chez Cloudflare (docs/MISE_EN_LIGNE_PERFORA_MA.md). E-mails pro en place (contact@ → Gmail ; envois Supabase par Resend depuis no-reply@perfora.ma). Ensuite volet D (énergie et eau). Ou mise
     en production (docs/RECETTE_VOLET_A.md §4). Démo VITRINE à réinitialiser une fois (nouvelles données magasin).
   - Supabase « gmao-terrain » (réf. oihaqzkqhvyjybijsonc, Frankfurt). Scripts dans l'ordre :
     schema.sql → roles.sql → multitenant.sql → quotas.sql → plateforme.sql → durcissement.sql → magasin.sql → achats.sql → energie.sql → mise_en_service.sql → centre_controle.sql → centre_controle_cc2.sql → references.sql → fichiers.sql → securite.sql → roles_r1.sql (généré : python scripts/generer_roles_r1.py) → interventions_r2.sql (généré : python scripts/generer_interventions_r2.py) → demo.sql → demo_energie.sql (généré : python scripts/generer_demo_energie.py) ; séquence unique pour une base neuve :
     supabase/production/construire_base.sql (générée : python scripts/assembler_sql.py ; --verifier avant un commit) ; tests : tests_etancheite, tests_quotas, tests_plateforme, tests_magasin, tests_demo, tests_achats, tests_energie, tests_mise_en_service, tests_centre_controle, tests_centre_controle_cc2, tests_references, tests_fichiers, tests_securite (tous rejouables en local : bash scripts/sauvegarde/tester_sql.sh) ;
     Edge Function supabase/functions/inviter. Entreprises : DEMO « Perfora Démo » (Site Tanger, pack Pro ;
     othmanihicham99@gmail.com responsable + administrateur plateforme ; hothmani36@outlook.fr magasinier)
     et VITRINE « Vitrine Perfora » (démo réinitialisable, **pack Entreprise** depuis le 6 nov. 2026 pour montrer les achats,
     réinitialisée avec la démo du volet C ; hicham.othmani90@gmail.com responsable). DEMO reste en pack Pro.
   - Tests : node --test tests/*.test.js (97) ; supabase/tests_*.sql (à rejouer dans le SQL Editor).
     Faux serveur : python tests/serveur_factice.py 8094 (comptes test@ responsable, tech2@ technicien,
     mag@ magasinier, achat@ achats, autre@ autre entreprise ; mot de passe test-gmao ; pack de DEMO modifiable par
     POST /test/abonnement) ; appli : python serveur.py 8081 ;
     deux appareils = http://localhost:8081 et http://127.0.0.1:8081 (les ports 8080 / 8099 peuvent
     être tenus par d'anciens processus).

4. RÈGLES DE TRAVAIL :
   - Respecte les règles du skill : pas de chronomètre ; l'inconnu reste inconnu ; rien n'est
     supprimé (statuts, mouvements inverses, journal) ; un fait = un comptage ; aucun classement
     individuel ; le serveur est l'autorité sur les droits, l'interface n'en est qu'un miroir.
   - Avant un changement de modèle de données : plan court, attendre validation.
   - Toute règle métier ou tout calcul va dans js/calculs.js (ou en SQL côté serveur) avec un test.
   - Évolution du stockage local : incrémenter DB_VER, migrer sans perte. Toute livraison :
     incrémenter VERSION dans sw.js et ajouter les nouveaux fichiers à FILES.
   - Toute nouvelle règle serveur : la reporter dans app.js (DROITS / autorise) et dans
     tests/serveur_factice.py ; la tester dans Supabase par une fonction plpgsql temporaire qui
     fixe request.jwt.claims puis nettoie ses données.
   - Vérifie dans le navigateur (390 px, hors ligne, deux appareils) avant de dire « terminé ».
   - Ne saisis jamais de mot de passe ; ne touche pas à la clé secrète Supabase ; demande avant
     de publier, d'envoyer un e-mail ou de modifier un réglage de compte.
   - Commits en français, terminés par la ligne Co-Authored-By habituelle.

5. VOLET À TRAITER MAINTENANT :
   Étape 7 — production : construire la base du projet de production, réglages Auth, tests d'étanchéité et de sécurité
   rejoués, appli branchée (après création du projet par Hicham et dépôt privé des sauvegardes).
   Commence par me proposer le modèle de données, les règles serveur et le découpage en étapes,
   en citant les sections V3 concernées, puis attends ma validation.
```

---

## Volets disponibles (copier l'un d'eux en section 5)

- **A** — Multi-entreprise (multitenant), sites, packs, quotas d'utilisateurs par site et par pack, invitation depuis l'appli.
- **B** — Magasin en lien avec le terrain : besoin depuis l'intervention, réservation, remise, utilisation, retour, retrait urgent, attente pièce.
- **C** — Magasin et achats : définition des stocks (sécurité, point de commande, cible, délai), récapitulatif à réapprovisionner, demande d'achat, commande, réception partielle, CUMP.
- **D** — Énergie et eau : compteurs, relevés terrain par QR, contrôles de cohérence, ruptures, consommations, factures, ratios.
- **E** — Pilotage avancé et rapports (temps requis, disponibilité, objectifs, rapport mensuel).
- **F** — Imports Excel contrôlés.
- **G** — Industrialisation (photos en stockage de fichiers, recette / production, sauvegardes, CNDP).
- **H** — Démo et commercialisation (entreprise de démonstration, script, page de présentation).

Détail de chaque volet : [`FEUILLE_DE_ROUTE.md`](FEUILLE_DE_ROUTE.md).
