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

## 3. Fermer les inscriptions publiques
**Authentication** → **Sign In / Providers** (ou *Settings*) → désactiver **Allow new users to sign up**.
Seul le responsable crée les comptes.

## 4. Créer les comptes
**Authentication** → **Users** → **Add user** → **Create new user** :
e-mail + mot de passe, cocher **Auto Confirm User**. Un compte par personne.

## 5. Récupérer l'adresse et la clé publique
**Project Settings** → **API** (ou **Data API** / **API Keys**) :
- **Project URL** : `https://xxxxxxxx.supabase.co`
- **clé publique** : `anon` / `publishable` (commence souvent par `eyJ…` ou `sb_publishable_…`).

La clé publique peut figurer dans l'appli : sans compte connecté, elle ne donne accès à rien
(règles RLS du `schema.sql`). **Ne jamais utiliser la clé `service_role` / `secret` dans l'appli.**

## 6. Connecter chaque appareil
Dans l'appli : **Réglages → Synchronisation cloud → Connecter ce compte**, saisir l'adresse,
la clé publique, l'e-mail et le mot de passe de la personne.
- Au premier branchement, les données déjà présentes sur l'appareil sont envoyées automatiquement.
- Le voyant ☁ en haut indique : *À jour*, *n à envoyer*, *Erreur* ou *Reconnexion*.

## Limites du prototype
- Toute personne connectée voit et modifie tout (un seul site). Rôles et périmètres : étape suivante.
- Les photos voyagent dans la base (≈150 Ko chacune) ; passage au stockage de fichiers prévu.
- Offre gratuite : mise en pause après 7 jours sans activité, pas de sauvegarde automatique.
  Pour la production : offre payante ou export quotidien.
- Données personnelles (noms) hébergées hors du Maroc : vérifier les formalités CNDP (loi 09-08)
  avant la mise en production.
