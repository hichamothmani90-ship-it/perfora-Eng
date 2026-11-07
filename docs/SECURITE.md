# Sécurité (étape 6 du chemin vers le pilote, 7 nov. 2026, v35)

Script serveur : `supabase/securite.sql` (dans la séquence `supabase/production/`, après `fichiers.sql`).
Tests : `supabase/tests_securite.sql` (14 contrôles, conformes sur Supabase et sur une base neuve),
`tests/securite_serveur_test.py` (14 contrôles sur le serveur factice).

## 1. Double authentification de l'administrateur (MFA)

- Les droits d'administrateur plateforme (console, fonctions `pf_*`, lecture de toutes les entreprises) ne valent que
  dans une session **confirmée par un code** d'application d'authentification (niveau « aal2 »). Vérifié par le serveur :
  un mot de passe volé ne suffit plus.
- **Activer (une fois)** : centre de contrôle → bandeau « Double authentification pas encore activée » → *Activer
  maintenant* → scanner le QR avec Google Authenticator, Microsoft Authenticator ou 2FAS → saisir le code.
  Dès ce code accepté, il devient **obligatoire** pour ce compte (aucun retour en arrière par l'API).
- Ensuite, à chaque nouvelle connexion, la console demande le code à 6 chiffres ; la session le garde ensuite.
- Sur la recette, le compte administrateur actuel reste en « mot de passe seul » tant que tu n'as pas activé la MFA ;
  en production, tout nouvel administrateur l'a d'emblée (obligatoire dès l'inscription).
- **Téléphone perdu** (procédure de secours, dans le tableau de bord Supabase, avec ton compte Supabase) :
  1. Authentication → Users → ton compte → supprimer le facteur MFA ;
  2. SQL Editor : `update public.admins_plateforme set mfa_obligatoire = false where user_id = (select id from auth.users where email = '<adresse>');`
  3. console → réactiver la double authentification avec le nouveau téléphone (le journal garde la trace de l'étape 2).
  Conseil : à l'inscription, enregistrer aussi la clé affichée sous le QR dans ton gestionnaire de mots de passe.
- Les responsables et techniciens n'ont pas de MFA (décision du 7 nov. : administrateur seulement).

## 2. Compte administrateur séparé (à faire par Hicham)

Ton compte actuel est à la fois administrateur plateforme et responsable de « Perfora Démo ». Avant la production :
1. créer une adresse dédiée (ex. `admin@perfora.ma`, boîte qui reçoit le courrier) ;
2. en production : créer une entreprise interne « Perfora — administration » (console → Nouveau client), y inviter
   cette adresse comme responsable, puis dans le SQL Editor :
   `insert into public.admins_plateforme (user_id) select id from auth.users where email = 'admin@perfora.ma';`
3. se connecter à la console avec ce compte et activer la MFA ;
4. retirer les droits plateforme de l'ancien compte : `delete from public.admins_plateforme where user_id = (select id from auth.users where email = '<ancienne adresse>');`
Ce compte ne sert qu'à la console, jamais sur un téléphone de démonstration.

## 3. Mots de passe

- Appli : 10 caractères minimum, lettres et chiffres, sans l'adresse e-mail, refus des suites évidentes
  (`regleMotDePasse` dans js/app.js, à la première connexion et au changement de mot de passe).
- **Réglage Supabase (Hicham)** : Authentication → Providers → Email → *Minimum password length* = **10**, *Password
  requirements* = **Letters and digits** ; le même réglage le refuse côté serveur. (Le refus des mots de passe compromis
  et la durée de session limitée sont réservés à l'offre Pro : à activer si on passe à Pro.)

## 4. Journal des actions de la plateforme

- Table `pf_journal_admin` : chaque création, modification ou suppression sur les entreprises, abonnements, sites,
  packs, tarifs, annonces, imports (lots), mise en service, droits d'administrateur, profils et affectations modifiés par
  l'administrateur ; objets de la console (prospects, tickets, échanges) modifiés par l'administrateur.
- Pour chaque ligne : qui (compte, ou « SQL / service »), quand, niveau de session (avec code ou non), fonction appelée
  (`pf_creer_entreprise`, `pf_modifier_abonnement`, `pf_importer`…), table, avant / après (champs modifiés seulement ;
  valeurs longues résumées).
- **Ajout seulement** : modification et suppression refusées, même pour l'administrateur. Lecture : console → Technique.

## 5. Limites d'envoi (anti-abus)

| Action | Limite |
|---|---|
| Invitations par un responsable | 20 par heure et par entreprise |
| Invitations par l'administrateur | 50 par heure |
| Demandes de support | 5 par heure et par compte, 15 par heure et par entreprise (et 20 ouvertes au plus) |
| Erreurs remontées par un appareil | 30 envois par heure et par compte |
S'ajoutent les limites de Supabase Auth (e-mails par heure, liens « mot de passe oublié »).

## 6. Supervision

- Les appareils remontent leurs **erreurs JavaScript**, les **refus du serveur** et les **échecs de synchronisation**
  (hors coupures réseau, normales sur le terrain) : regroupées par compte et message sur 24 h, gardées 90 jours,
  aucune donnée métier (message, page, version, navigateur).
- Console → **Technique** : erreurs des 7 derniers jours (client, compte, page, version, détail), place occupée
  (fichiers / 1 Go, base / 500 Mo de l'offre gratuite), fichiers par client, journal des actions.
- **Disponibilité du site** (Hicham, 5 minutes) : créer une sonde gratuite (ex. UptimeRobot) sur
  `https://app.perfora.ma` toutes les 5 minutes avec alerte par e-mail. La sauvegarde de nuit (dépôt privé) échoue aussi
  visiblement si la base ne répond plus.

## 7. Contrôles de fin

- Aucune fonction du schéma public appelable sans compte (contrôle dans `securite.sql`, `99_controles.sql`, l'empreinte).
- Les fonctions de test ne sont jamais appelables par l'API (droits retirés à la création ; `drop` après usage).
- Empreinte du schéma recette / base reconstruite : identique (62 fonctions, 7 nov. 2026).

Reste de la phase sécurité (§2 du planning) : revue avant le premier client (conseiller sécurité Supabase à 0 erreur,
tests d'étanchéité rejoués sur la production, petit test d'intrusion) et ménage (clés Resend, DMARC).
