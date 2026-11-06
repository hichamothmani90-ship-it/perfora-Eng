# Brancher GMAO terrain sur Supabase (prototype de synchronisation)

Durée : 15 minutes environ. Offre gratuite suffisante pour le prototype.

## 1. Créer le projet
1. Ouvrir https://supabase.com → **Start your project** → se connecter (avec GitHub, c'est le plus simple).
2. **New project** :
   - Name : `gmao-terrain`
   - Database password : un mot de passe fort, à garder (il ne servira pas dans l'appli)
   - Region : **Central EU (Frankfurt)** — la plus proche du Maroc
3. Attendre 1 à 2 minutes que le projet soit prêt.

## 2. Créer la table et les règles
1. Menu de gauche **SQL Editor** → **New query**.
2. Coller tout le contenu de [`schema.sql`](schema.sql) → **Run**.
3. Résultat attendu : « Success. No rows returned ».

## 2 bis. Rôles et droits
Toujours dans **SQL Editor** : coller [`roles.sql`](roles.sql) → **Run**, puis désigner le premier responsable :
`update public.profils set role = 'responsable' where email = 'votre.email@exemple.com';`
(Fait le 6 nov. 2026 pour othmanihicham99@gmail.com.)

Ensuite, les rôles se gèrent dans l'appli : **Réglages → Équipe et droits** (visible du responsable).
Tout nouveau compte arrive en **Technicien**.

| Rôle | Peut écrire |
|---|---|
| Responsable | tout, y compris configuration et correction d'une intervention clôturée |
| Technicien / Prestataire | demandes, interventions non clôturées, photos, sorties de pièces sur intervention |
| Magasinier | demandes, photos, articles, tous mouvements de stock |
| Exploitation | demandes et photos |
| Pilote | rien (consultation) |

Le serveur applique ces règles (fonction `push_fiches`) ; une modification interdite est refusée,
l'appareil reprend la version du serveur et affiche le motif.

## 2 ter. Multi-entreprise (volet A)
Coller [`multitenant.sql`](multitenant.sql) → **Run** (fait le 6 nov. 2026), puis l'administrateur plateforme
(ligne en fin de script). Vérification : [`tests_etancheite.sql`](tests_etancheite.sql) (une ligne de résultats, puis
supprimer la fonction de test). Tant que l'étape A3 n'est pas livrée, un compte invité doit être rattaché à son
entreprise par SQL : `update profils set entreprise_id = …, site_defaut = … where email = …;` +
`insert into profil_sites …`.

## 2 quater. Quotas et invitations (volet A3)
Coller [`quotas.sql`](quotas.sql) → **Run** (fait le 6 nov. 2026) ; tests : [`tests_quotas.sql`](tests_quotas.sql).
Fonction serveur : **Edge Functions → Deploy a new function → Via Editor**, nom `inviter`, coller
[`functions/inviter/index.ts`](functions/inviter/index.ts), « Verify JWT » activé (fait le 6 nov. 2026).
Les membres s'invitent ensuite depuis l'appli : **Réglages → Équipe et droits → + Inviter un membre**.

## 2 quinquies. Console plateforme (volet A4)
Coller [`plateforme.sql`](plateforme.sql) → **Run** (fait le 6 nov. 2026) ; tests : [`tests_plateforme.sql`](tests_plateforme.sql).
La fonction `inviter` accepte `entrepriseId` (administrateur plateforme uniquement) — redéployée le 6 nov. 2026.
Dans l'appli : **Plus → Console plateforme** (visible seulement de l'administrateur).

## 3. Fermer les inscriptions publiques
**Authentication** → **Sign In / Providers** (ou *Settings*) → désactiver **Allow new users to sign up**.
Seul le responsable crée les comptes.

## 4. Adresse de retour des e-mails (une seule fois)
**Authentication** → **URL Configuration** → **Site URL** =
`https://hichamothmani90-ship-it.github.io/perfora-Eng/` → Save. (Fait le 6 nov. 2026.)

## 5. Créer les comptes — méthode recommandée : l'invitation
**Authentication** → **Users** → **Add user** → **Send invitation** → e-mail de la personne.
La personne clique le lien reçu : l'appli s'ouvre, lui demande de **choisir son mot de passe**,
puis la connecte et synchronise. Elle utilise ensuite e-mail + mot de passe sur ses autres appareils.

Mot de passe oublié : fiche de l'utilisateur → **Send password recovery** (même parcours).
Alternative sans e-mail : **Create new user** avec un mot de passe et **Auto Confirm User**.

## 6. Récupérer l'adresse et la clé publique (déjà préremplies dans l'appli)
**Project Settings** → **API** (ou **Data API** / **API Keys**) :
- **Project URL** : `https://xxxxxxxx.supabase.co`
- **clé publique** : `anon` / `publishable` (commence souvent par `eyJ…` ou `sb_publishable_…`).

La clé publique peut figurer dans l'appli : sans compte connecté, elle ne donne accès à rien
(règles RLS du `schema.sql`). **Ne jamais utiliser la clé `service_role` / `secret` dans l'appli.**

## 7. Connecter chaque appareil
Dans l'appli : **Réglages → Synchronisation cloud → Connecter ce compte**, saisir l'adresse,
la clé publique, l'e-mail et le mot de passe de la personne.
- Au premier branchement, les données déjà présentes sur l'appareil sont envoyées automatiquement.
- Le voyant ☁ en haut indique : *À jour*, *n à envoyer*, *Erreur* ou *Reconnexion*.

## Limites du prototype
- Un seul site : toute personne connectée voit tout (les droits portent sur l'écriture).
- Ajouter un membre se fait encore dans Supabase (invitation) ; son rôle se règle dans l'appli.
- Les photos voyagent dans la base (≈150 Ko chacune) ; passage au stockage de fichiers prévu.
- Offre gratuite : mise en pause après 7 jours sans activité, pas de sauvegarde automatique.
  Pour la production : offre payante ou export quotidien.
- Données personnelles (noms) hébergées hors du Maroc : vérifier les formalités CNDP (loi 09-08)
  avant la mise en production.
