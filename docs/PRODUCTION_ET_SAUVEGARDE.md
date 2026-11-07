# Production, sauvegarde et restauration

Étape 5 du chemin vers le pilote (docs/PLANNING_ACTUALISE.md §0 bis). Offre Supabase **gratuite** : pas de sauvegarde
téléchargeable côté Supabase, d'où une **sauvegarde maison chiffrée**, chaque nuit, dans un dépôt GitHub **privé**.

## 1. Construire une base neuve (production)

Une seule séquence, dans l'ordre, générée depuis les scripts de `supabase/` :

| Fichier | Rôle |
|---|---|
| `supabase/production/01_schema.sql` … `16_demo_energie.sql` | copies numérotées (lecture, vérification) |
| `supabase/production/99_controles.sql` | contrôles de fin : 0 fonction ouverte sans compte, RLS partout, espace « fichiers » créé |
| `supabase/production/construire_base.sql` | **tout en un seul fichier** : à exécuter une fois dans le SQL Editor du projet neuf |
| `supabase/production/MANIFESTE.txt` | ordre et empreinte de chaque script source |

- Régénérer après toute modification d'un script : `python scripts/assembler_sql.py` ;
  vérifier avant un commit : `python scripts/assembler_sql.py --verifier`.
- Les fichiers de `supabase/production/` ne se modifient **jamais à la main**.
- Les scripts de test (`tests_*.sql`) ne font pas partie de la séquence. Après un test sur la recette, supprimer la
  fonction de test (`drop function …`) : un oubli a été trouvé le 7 nov. (`gmao_test_cc`, sans danger mais visible).

Après la construction (fait par Hicham, compte administrateur) :
1. créer son compte administrateur dans Authentication (adresse **dédiée**, MFA : étape 6) ;
2. `insert into public.admins_plateforme (user_id) select id from auth.users where email = '<adresse>';`
3. réglages Auth (adresse du site, modèles d'e-mail en français, SMTP Resend) : comme la recette
   (docs/MISE_EN_LIGNE_PERFORA_MA.md).

## 2. Sauvegarde quotidienne chiffrée

Contenu de chaque sauvegarde (`perfora-AAAA-MM-JJ-HHMM.tar.gz.gpg`, chiffrée AES-256) :
données de l'appli (schéma public), comptes (auth.users, auth.identities), fichiers joints (photos, PDF),
schéma pour information, comptages de contrôle. Le schéma se reconstruit avec `construire_base.sql`.

Scripts : `scripts/sauvegarde/sauvegarder.sh`, `restaurer.sh`, `fichiers.py`, `workflow_sauvegarde.yml`.

### Mise en place (Hicham — les secrets ne passent jamais par Claude)

1. Créer un dépôt GitHub **privé**, par exemple `perfora-sauvegardes` (jamais public : le workflow refuse de
   tourner dans un dépôt public).
2. Y copier `scripts/sauvegarde/workflow_sauvegarde.yml` sous `.github/workflows/sauvegarde.yml`.
3. Settings → Secrets and variables → Actions → New repository secret :
   - `SUPABASE_DB_URL` : Supabase → Connect → **Session pooler** (port 5432), avec le mot de passe de la base ;
   - `SUPABASE_URL` : `https://<projet>.supabase.co` ;
   - `SUPABASE_SERVICE_KEY` : Settings → API Keys → clé secrète (service_role). **Uniquement ici**, jamais dans l'appli ;
   - `BACKUP_PASSPHRASE` : une phrase de 20 caractères et plus, **notée aussi hors de GitHub** (gestionnaire de mots
     de passe, papier au coffre) : sans elle, aucune sauvegarde ne peut être relue.
4. Actions → « Sauvegarde Perfora » → **Run workflow** : vérifier qu'un fichier `.gpg` apparaît dans `sauvegardes/`.

Ensuite : chaque nuit à 02:15 (heure du Maroc) ; on garde 30 jours + la sauvegarde du 1er de chaque mois.
Effet utile : l'accès quotidien empêche la mise en pause du projet gratuit après 7 jours sans activité.

## 3. Restaurer

Dans un projet **neuf** (ou une base locale de test) :
1. exécuter `supabase/production/construire_base.sql` (même version de l'appli que la sauvegarde) ;
2. dans un terminal Linux / WSL avec `psql` 17 et `gpg` :
   ```
   DB_URL='<connexion de la base cible>' PHRASE='<phrase>' SUPABASE_URL='<url cible>' SERVICE_KEY='<clé cible>' \
     bash scripts/sauvegarde/restaurer.sh perfora-AAAA-MM-JJ-HHMM.tar.gz.gpg
   ```
   (taper les secrets soi-même ; ne jamais les écrire dans un fichier du dépôt).
3. Le script refuse une base qui contient déjà des comptes ou des fiches (`FORCER=1` pour remplacer, en connaissance
   de cause), recharge tout en une transaction, puis compare les comptages à ceux de la sauvegarde.
4. Les comptes gardent leur mot de passe (empreintes restaurées) ; les appareils doivent se reconnecter si l'adresse
   du projet change (nouvelle clé publique dans l'appli).

## 4. Tests faits le 7 nov. 2026

| Vérification | Résultat |
|---|---|
| Séquence rejouée sur une base **vide** (image `supabase/postgres:17.11.0.018`, même version que le projet) | sans erreur ; contrôles de fin : 0 fonction ouverte sans compte, RLS sur les 13 tables, espace « fichiers » créé |
| Empreinte du schéma reconstruit / projet de recette (fonctions, règles d'accès, déclencheurs, colonnes, index, contraintes, droits, espace de fichiers) | **identiques** (10 sections sur 10) |
| Sauvegarde chiffrée d'une base avec 2 comptes et la démo complète (110 fiches) | 32 Ko ; illisible sans la phrase ; mauvaise phrase refusée |
| Restauration dans une seconde base neuve | comptages identiques (14 tables) ; administrateur, profil du technicien et séquence des fiches retrouvés |
| Règles d'accès sur la base restaurée | le technicien voit 102 fiches de son site, 0 facture |
| Restauration sur une base non vide | refusée (garde-fou) |
| Copie des fichiers joints (`fichiers.py`, serveur factice) | 4 fichiers déposés, recopiés identiques octet par octet, redépôt reconnu « déjà présent », refus sans clé secrète |

Pas encore testé : la sauvegarde **réelle** depuis Supabase (pooler, fichiers réels) — premier lancement du workflow
une fois le dépôt privé et les secrets en place (§2), puis restauration de cette sauvegarde dans une base locale.

Constat pendant l'étape : une fonction de test oubliée (`gmao_test_cc`, test du centre de contrôle) restait sur la
recette et était appelable sans compte (sans effet : elle s'exécute avec les droits de l'appelant). Supprimée ;
l'empreinte (`appelables_sans_compte`) la signalerait désormais.

## 5. Refaire les tests

`scripts/sauvegarde/test_local.sh` (Linux / WSL avec Docker, image `supabase/postgres` de la même version que le
projet) : construit une base neuve, ajoute des données d'essai (comptes fictifs, démo complète), sauvegarde, vérifie
le chiffrement (illisible sans la phrase, mauvaise phrase refusée), construit une seconde base neuve, restaure,
compare les comptages, vérifie que les règles d'accès fonctionnent sur la base restaurée (un technicien ne voit pas
les factures), et que la restauration est refusée sur une base non vide.

Sur ce PC : Docker Desktop plante au démarrage (sa fonction d'IA ne supporte pas l'espace dans le dossier Windows
« lenovo ideapad ») ; on utilise le moteur Docker installé dans Ubuntu (WSL), sans Docker Desktop :
```
wsl -d Ubuntu-22.04 -u root -- dockerd          (laisser ouvert)
wsl -d Ubuntu-22.04 -u root -- bash -c 'cd "/mnt/c/Users/lenovo ideapad/Desktop/Claude Perfora/gmao-terrain" && bash scripts/sauvegarde/test_local.sh'
```
Comparer le schéma : `comparer_schema.sh` (base reconstruite) et `empreinte_schema.sql` dans le SQL Editor du projet,
puis `comparer_empreintes.py projet.json locale.json`.

À refaire : à chaque version qui modifie le schéma, et **une fois par trimestre** avec une vraie sauvegarde
(déchiffrée par Hicham) restaurée dans une base locale.
