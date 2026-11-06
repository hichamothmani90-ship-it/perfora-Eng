# Volet A — Multi-entreprise, sites, packs et quotas : proposition de conception

Statut : choix 1 à 5 **validés** le 6 nov. 2026. **A1 fait** (serveur : `supabase/multitenant.sql`, tests `supabase/tests_etancheite.sql` tous conformes). A2 à A5 à venir.

Références V3 : §24 (droits appliqués aux API, listes, exports, pièces jointes), §25 (modules désactivables
par site), §30 (« toutes les références sont rattachées à la même entreprise et au périmètre autorisé »),
§31 (champs communs : id, entreprise, site, référence lisible…), §37 (contrôle serveur et isolation par
entreprise ; ordre : référentiels et droits d'abord).

## 1. Hiérarchie

```
Plateforme (vous : administrateur plateforme)
 └─ Entreprise cliente (tenant)  ── abonnement → pack (limites, modules)
     ├─ Sites (Tanger, Casablanca…)  ── lieux › équipements, demandes, interventions, préventif, stock
     ├─ Profils (comptes) : rôle dans l'entreprise + sites autorisés
     └─ Référentiels communs : personnes, catalogue d'articles
```

## 2. Modèle de données (serveur)

| Table | Champs principaux | Rôle |
|---|---|---|
| `entreprises` | id, nom, code, statut (essai / actif / suspendu / résilié), créée le | Le client |
| `sites` | id, entreprise_id, nom, code, fuseau (Africa/Casablanca), actif | Périmètre opérationnel |
| `packs` | code (essentiel / pro / entreprise), max_sites, max_utilisateurs_site, max_utilisateurs_total, modules[], stockage_photos_mo | Offre commerciale |
| `abonnements` | entreprise_id, pack, début, fin, statut, **dérogations** (limites négociées) | Ce que le client a acheté |
| `profils` (étendu) | + entreprise_id, + rôle (inchangé) | Un compte = une entreprise |
| `profil_sites` | user_id, site_id | Sites autorisés (le responsable : tous les sites) |
| `admins_plateforme` | user_id | Vous |
| `fiches` (étendu) | + **entreprise_id** (obligatoire), + **site_id** (null = commun à l'entreprise) | Toutes les données |

Portée des fiches :
- **par site** : lieux, équipements, demandes, interventions, programmes, mouvements de stock, photos, journal ;
- **commun à l'entreprise** : personnes, catalogue d'articles (le stock reste par site, volet B).

## 3. Règles serveur

1. **Lecture** (RLS) : `entreprise_id = mon entreprise` **et** (`site_id` nul **ou** site autorisé). Un appareil ne
   télécharge donc que ses sites ; une autre entreprise est invisible, même par l'API.
2. **Écriture** (`push_fiches`) : l'entreprise est posée par le serveur (jamais par l'appareil) ; le site envoyé
   doit appartenir à l'entreprise et être autorisé ; une fiche existante ne change pas de site (sauf responsable).
3. **Modules** : une écriture dans un module absent du pack est refusée (ex. articles sans le module magasin).
4. **Abonnement** suspendu ou expiré : lecture seule (les données restent consultables et exportables).
5. **Quotas**, vérifiés côté serveur à chaque invitation, activation ou affectation de site :
   - utilisateurs actifs **par site** ≤ `max_utilisateurs_site` (un compte compte sur chaque site où il est affecté) ;
   - utilisateurs actifs **par entreprise** ≤ `max_utilisateurs_total` ;
   - sites actifs ≤ `max_sites`.
   Désactiver un compte libère sa place. Message clair en cas de dépassement.
6. **Invitation depuis l'appli** : une fonction serveur (Edge Function `inviter`) détient la clé secrète, vérifie
   rôle + quotas, crée le profil (entreprise, rôle, sites) puis envoie l'e-mail. La clé secrète ne quitte jamais le serveur.

## 4. Côté appli

- **Site actif** dans la barre du haut (sélecteur si plusieurs sites) : les listes, l'accueil et les indicateurs
  se limitent au site actif (option « tous mes sites » pour le responsable) ; les créations portent ce site.
- Changement de compte vers une autre entreprise : l'appli refuse tant que des saisies attendent l'envoi, puis
  vide les données locales de l'ancienne entreprise (aucune fuite d'une entreprise à l'autre sur un appareil partagé).
- Menus selon les modules du pack ; écran **Équipe** : inviter, affecter des sites, compteur de places
  (« 4 / 5 sur Site Tanger ») ; écran **Abonnement** (lecture) pour le responsable.
- **Console plateforme** (vous seul) : créer une entreprise, son premier site et son responsable, choisir le pack,
  voir l'usage (utilisateurs, sites, photos), suspendre ; entreprise **Démo** réinitialisable (volet H).

## 5. Migration de l'existant (sans perte)

Création de l'entreprise « Perfora Démo » et du site « Site Tanger » ; toutes les fiches actuelles et votre
compte y sont rattachés ; vous devenez aussi administrateur plateforme. Les appareils déjà connectés se
mettent à jour à la synchronisation suivante.

## 6. Étapes

| Étape | Contenu | Vérification |
|---|---|---|
| A1 | Tables, colonnes, RLS, `push_fiches` à périmètre, migration de l'existant | Tests d'étanchéité SQL : deux entreprises, deux sites, aucun croisement |
| A2 | Appli : site actif, créations rattachées au site, purge au changement d'entreprise, menus par module | Faux serveur multi-entreprise, deux appareils |
| A3 | Quotas + Edge Function `inviter` + écran Équipe (places, sites) | Dépassement refusé côté serveur, même via le tableau de bord Supabase |
| A4 | Console plateforme + entreprise Démo réinitialisable | Création d'un client de bout en bout |
| A5 | Recette complète, docs, skill, publication | Scénarios hors ligne + droits + quotas |

## 7. Choix proposés (à confirmer)

1. **Un compte = une seule entreprise** (les prestataires multi-clients auront un compte par client) — simple et sûr.
2. **Rôle unique par entreprise + liste de sites** (et non un rôle différent par site) ; le responsable voit tous les sites.
3. **Tous les comptes actifs comptent dans les quotas**, y compris pilote et exploitation (ajustable par dérogation).
4. **Packs initiaux** : Essentiel (1 site, 5 utilisateurs/site, demandes + interventions + préventif + QR) ·
   Pro (3 sites, 15/site, + magasin, rapports) · Entreprise (limites sur mesure, + achats, énergie, imports).
5. Table unique `fiches` conservée pour ce volet (synchro inchangée) ; tables typées introduites avec les volets C et D.
