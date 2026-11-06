# Recette du volet A — multi-entreprise (6 novembre 2026)

Version de l'appli : **v18** (<https://hichamothmani90-ship-it.github.io/perfora-Eng/>).
Serveur : Supabase `gmao-terrain` (Frankfurt). Entreprises en place : **Perfora Démo** (`DEMO`, pack Pro,
Site Tanger) et **Vitrine Perfora** (`VITRINE`, démo commerciale réinitialisable).

## 1. Résultat

| Domaine | Vérification | Résultat |
|---|---|---|
| Appli | 25 tests automatisés (règles, indicateurs, scénarios S01–S08, QR codes) | ✅ 25 / 25 |
| Isolation | 12 tests (`supabase/tests_etancheite.sql`) : deux entreprises, deux sites, lecture réelle sous RLS | ✅ 12 / 12 |
| Quotas | 12 tests (`supabase/tests_quotas.sql`) : sites, utilisateurs par entreprise et par site, invitation | ✅ 12 / 12 |
| Console | 11 tests (`supabase/tests_plateforme.sql`) : droits admin, création, abonnement, démo | ✅ 11 / 11 |
| Accès sans compte | 8 tables, 13 fonctions, écriture directe, inscription, fonction d'invitation | ✅ tout refusé |
| Parcours réel | invitation par e-mail, choix du mot de passe, technicien sur son site ; démo ouverte avec le compte de présentation | ✅ validé par Hicham |
| Non-régression v18 | signalement + intervention, clôture contrôlée, hors ligne (7 saisies en attente puis envoyées), technicien d'un autre site sans visibilité ni écriture | ✅ (faux serveur, 2 appareils) |

## 2. Corrections de sécurité faites pendant la recette (`supabase/durcissement.sql`)

1. `nb_actifs_entreprise` / `nb_actifs_site` étaient appelables **sans compte** : un tiers connaissant l'identifiant
   interne d'une entreprise pouvait connaître son nombre d'utilisateurs actifs. → Fermées.
2. Fonctions internes (`exiger_admin`, `peut_ecrire`, `module_de`, `uuid_ou_null`, `pf_j`) et fonctions de
   déclencheurs (`creer_profil`, `quota_*`) : plus appelables par l'API. Déclencheurs vérifiés après coup.
3. `droits_entreprise(ent)` : plus appelable directement par un compte connecté.
4. Chemin de recherche fixé pour les fonctions utilitaires.

Conseiller sécurité Supabase : **0 erreur** ; avertissements passés de 30 à 18 (puis `droits_entreprise` fermée en plus), tous du type « fonction appelable
par un compte connecté » — **acceptés** : ce sont les fonctions de l'appli (synchro, équipe, console), chacune
vérifie elle-même rôle, entreprise et site ; `mon_role`, `mon_entreprise`, `mes_sites`, `est_admin_plateforme`
sont nécessaires aux règles de lecture.

## 3. Limites connues (non bloquantes pour une démonstration)

- E-mails envoyés par Supabase : quelques-uns par heure, souvent classés en indésirables (Outlook).
- Photos stockées dans la base (≈150 Ko chacune) : à déplacer vers le stockage de fichiers.
- Offre gratuite : pause après 7 jours sans activité, pas de sauvegarde automatique.
- `Perfora Démo` contient des données de test : à ne pas utiliser comme client réel.
- Pas de console « clé secrète » dans l'appli : tout passe par les fonctions serveur (voulu).
- Les tests de l'appli avec fenêtres de saisie demandent que le panneau navigateur soit visible
  (le navigateur retarde la fermeture des fenêtres dans un onglet masqué) — limite de l'environnement de test.

## 4. Avant le premier client payant (liste de contrôle)

| # | Action | Pourquoi | Qui |
|---|---|---|---|
| 1 | Service d'envoi d'e-mails dédié (Brevo, Resend…) + adresse d'expéditeur de la marque, réglé dans Supabase → Authentication → SMTP | Invitations reçues en boîte de réception, à votre nom | Claude + vous (compte du service) |
| 2 | Offre Supabase payante (Pro) | Pas de mise en pause, sauvegardes quotidiennes, limites relevées | Vous (paiement) |
| 3 | Projet de **production** séparé (le projet actuel devient la recette) : rejouer les scripts SQL dans l'ordre, créer le client | Données client jamais mélangées aux essais | Claude |
| 4 | Photos dans Supabase Storage (avec les mêmes règles d'accès par entreprise) | Base légère, coût maîtrisé | Claude |
| 5 | Nom de domaine (ex. `app.perfora.ma`) et adresse publique dans l'appli + Supabase (Site URL) | Image professionnelle, QR codes durables | Vous (achat) + Claude (réglages) |
| 6 | Formalités CNDP (loi 09-08) pour l'hébergement des données personnelles hors du Maroc ; mentions légales, contrat, politique de confidentialité | Conformité | Vous (conseil juridique) |
| 7 | Export régulier des données de chaque client (sauvegarde indépendante) | Réversibilité | Claude |
| 8 | Pilote de 4 à 6 semaines sur un site, indicateurs avant / après | Preuve de valeur | Vous |

## 5. Rejouer la recette

1. `node --test "tests/*.test.js"` dans le dossier du projet.
2. Supabase → SQL Editor : exécuter chacun des fichiers `supabase/tests_*.sql`, lire la ligne de résultats,
   puis supprimer la fonction de test (ligne en commentaire en fin de fichier).
3. `supabase/durcissement.sql` : la dernière requête doit lister **aucune** fonction ouverte sans compte.
4. Faux serveur pour l'appli : `python tests/serveur_factice.py 8096`, appli `python serveur.py 8081`,
   deux appareils = `http://localhost:8081` et `http://127.0.0.1:8081` (comptes dans l'en-tête du faux serveur).
