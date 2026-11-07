# Perfora — planning actualisé (7 nov. 2026)

Priorités fixées : **1. stabilité, 2. sécurité, 3. expérience d'inscription et de connexion**, regroupées avec le reste.
Les semaines (S1 = semaine qui suit la validation) sont indicatives. Les fonctions nouvelles attendent que les phases 1 et 2
soient faites.

## 0. Ce qui est fait

| Domaine | État |
|---|---|
| Socle multi-entreprise, sites, packs, quotas, rôles, invitations | ✅ volet A |
| Magasin relié au terrain, achats, seuils, valorisation | ✅ volets B et C |
| Parcours demande → intervention simplifié, clôture validée par le responsable | ✅ v23 – v24 |
| Énergie : calculs (D1) et serveur (D2, D2 bis compteurs d'équipement) | ✅ écrans à faire (D3 – D5) |
| Domaine perfora.ma, app.perfora.ma, HTTPS, e-mails en français (Resend) | ✅ phase 1 du cadrage |
| Kit Excel de démarrage + page Mise en service | ✅ v25 |
| Centre de contrôle : tableau de bord, clients, abonnements, prospects, support, communication | ✅ v26 – v27 |

## 1. Phase « Stabilité » (S1 – S3) — priorité 1

| # | Chantier | Pourquoi | Qui |
|---|---|---|---|
| 1.1 | **Projet Supabase de production séparé** du projet actuel (qui devient la recette), avec **scripts SQL numérotés** (migrations) au lieu de scripts rejouables à passer dans un ordre précis | Aujourd'hui démo, tests et futurs clients partagent la même base ; un essai peut toucher un client | moi + toi (souscription) |
| 1.2 | **Photos dans Supabase Storage** (fichiers) au lieu de la base, avec limite par pack | Les photos en base font grossir la synchronisation et la sauvegarde : premier risque de lenteur | moi |
| 1.3 | **Sauvegarde quotidienne + test de restauration** documenté (offre Supabase Pro) | Sans test de restauration, une sauvegarde n'est qu'un espoir | moi + toi (offre) |
| 1.4 | **Supervision** : erreurs de l'appli et refus du serveur remontés dans un onglet « Technique » du centre de contrôle ; alerte si le site ne répond plus | Savoir qu'un client est bloqué avant qu'il appelle | moi |
| 1.5 | **Tests automatisés de bout en bout** (deux appareils, hors ligne puis retour du réseau, droits par rôle) lancés avant chaque publication | Les tests actuels sont surtout manuels dans le navigateur | moi |
| 1.6 | **Mises à jour sans surprise** : réglage Cloudflare « Browser Cache TTL → Respect Existing Headers », message « nouvelle version » fiable, numéro de version visible | Le cache de 4 h de Cloudflare a déjà servi une ancienne console | toi (1 clic) + moi |
| 1.0 | **Campagne de tests hors ligne** (en premier, demandée le 7 nov. 2026), sur vrais téléphones (Android et iPhone) et en automatique : voir le détail ci-dessous | Le hors ligne est la promesse de Perfora : il doit être prouvé, pas supposé | moi + toi (téléphones) |
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
| 2.1 | **Compte administrateur séparé** : ton compte plateforme ne doit plus être aussi responsable de l'entreprise « Perfora Démo » | moi + toi |
| 2.2 | **Double authentification (MFA)** obligatoire pour l'administrateur, proposée aux responsables | moi |
| 2.3 | **Règles de mot de passe** dans Supabase : 10 caractères minimum, refus des mots de passe compromis (offre Pro), durée de session, confirmation d'e-mail | toi (réglages) + moi (guide) |
| 2.4 | **Journal des actions de l'administrateur** (création d'entreprise, changement d'abonnement, import, annulation de lot) | moi |
| 2.5 | **Limites d'envoi** : invitations et demandes de support par heure et par entreprise (anti-abus) | moi |
| 2.6 | **Revue de sécurité** avant le premier client : conseiller sécurité Supabase à 0 erreur, tests d'étanchéité rejoués sur la production, petit test d'intrusion | moi |
| 2.7 | **Ménage** : supprimer les clés Resend inutilisées, retirer le script Cloudflare Web Analytics bloqué par la politique de sécurité (ou l'autoriser), DMARC « quarantine » après quelques semaines d'envois | toi + moi |

## 3. Phase « Inscription et connexion » (S2 – S4) — priorité 3

Constat : aujourd'hui la connexion se fait dans **Réglages**, avec des champs techniques (adresse du serveur, clé) ; un
nouvel utilisateur arrive sur une appli vide qui propose « Charger la démo ». C'est le point faible de l'expérience.

| # | Chantier |
|---|---|
| 3.1 | **Écran de connexion dès l'ouverture** : e-mail + mot de passe, « Recevoir un lien de connexion », « Mot de passe oublié », messages d'erreur clairs ; plus aucun champ technique (le serveur est fixé) |
| 3.2 | **Première connexion guidée** après invitation : choix du mot de passe → « Ajouter à l'écran d'accueil » (indispensable sur iPhone, voir §6) → choix du site → courte visite de 3 écrans selon le rôle |
| 3.3 | **Invitation par WhatsApp** en plus de l'e-mail (lien à usage unique, valable 24 h) : beaucoup de techniciens n'ouvrent pas leurs e-mails |
| 3.4 | **Premiers pas du responsable** : liste à cocher (inviter l'équipe, imprimer les QR, vérifier les criticités, créer 3 programmes préventifs) |
| 3.5 | **« Demander un essai »** sur perfora.ma : formulaire court qui crée un **prospect** dans le centre de contrôle (avec protection anti-robot), en plus du bouton WhatsApp. Pas d'inscription libre au départ : tu ouvres chaque essai toi-même (décision à confirmer) |
| 3.6 | **Changer son mot de passe, se déconnecter de tous les appareils, gérer son profil** (nom, téléphone) |
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
| 5.1 | **D3** : relevés de compteurs sur le terrain (QR, hors ligne, contrôle immédiat), compteurs d'équipement et **préventif selon l'usage** (heures) |
| 5.2 | **Classification du parc** à l'écran (catalogue, criticité A/B/C guidée, parent, réglementaire, écran « À classer ») |
| 5.3 | **Inventaire du magasin** (prioritaire dans C bis), puis emplacement, conditionnement, liste des fournisseurs, achats non stockés |
| 5.4 | **D4 – D5** : écrans Énergie (consommations, à examiner, factures, rapprochement), démo et guide |
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

## 8. Décisions à prendre (toi)

1. Souscrire **Supabase Pro** pour la production (sauvegardes, mots de passe compromis, pas de mise en veille) : maintenant
   ou au premier pilote ? (recommandé : maintenant, pour la phase 1)
2. **Inscription libre** (essai créé automatiquement) ou **essais ouverts par toi** (recommandé au départ) ?
3. **MFA** : obligatoire pour toi seul, ou aussi pour les responsables ?
4. **Langue arabe** : à prévoir dans l'année ou non ?
5. Date visée pour le **premier pilote** : elle fixe l'ordre fin des phases 1 à 3.
