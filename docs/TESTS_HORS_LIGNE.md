# Tests hors ligne — rapport et protocole (7 nov. 2026)

## 1. Méthode

- Deux « téléphones » : l'appli ouverte sur deux adresses locales (stockages séparés), A = responsable, B = technicien
  du même site, reliés au serveur factice (`tests/serveur_factice.py`, miroir des règles de Supabase).
- Réseau simulé sans perdre les données du serveur : `python tests/reseau.py <port> panne | normal | lent <s> | coupures
  | portail | etat | raz` (panne = connexion coupée ; lent = réponse après N s, l'appli abandonne à 20 s mais le serveur a
  traité : réponse perdue ; coupures = une requête sur deux perdue ; portail = page HTML d'un Wi-Fi d'hôtel).
- Limite : le navigateur de test refuse le mode hors ligne (service worker) sur une adresse locale. L'ouverture de l'appli
  sans aucun réseau est donc vérifiée sur app.perfora.ma (cache complet) et doit être confirmée sur vrais téléphones (§4).

## 2. Résultats

| # | Scénario | Résultat |
|---|---|---|
| 1 | Ouvrir l'appli sans réseau | ✅ cache complet sur app.perfora.ma (14 fichiers, v27, service worker actif) ; à confirmer en mode avion sur téléphone |
| 2 | Tout saisir hors ligne : signalement + photo, J'interviens, demande de pièce, Terminer / clôture | ✅ 20 saisies en attente, rien perdu |
| 3 | Retour du réseau | ✅ tout envoyé, « À jour » ; l'autre téléphone reçoit intervention clôturée, photo (112 Ko), pièce ; aucun doublon |
| 4 | Deux téléphones hors ligne modifient la même intervention | ✅ champs différents fusionnés (cause de B + priorité de A) ; ⚠ même champ texte : le dernier envoyé l'emporte, l'autre texte reste dans l'historique (amélioration prévue, §3) |
| 5 | Réseau très lent (réponse perdue après 20 s) puis retour | ✅ renvoi sans doublon (1 demande, 1 ligne d'historique) |
| 6 | Appli fermée / téléphone redémarré avec des saisies en attente | ✅ 20 saisies, photo et clôture toujours là, session conservée |
| 7 | Saisie refusée au retour (intervention clôturée entre-temps par le responsable) | ✅ message clair, version du serveur rétablie, pas de boucle ; **corrigé** : le texte refusé est maintenant affiché pour être recopié |
| 8 | Plusieurs jours hors ligne : 30 signalements avec photo (120 saisies, 4,1 Mo) | ❌ avant : un seul envoi de 3,45 Mo, impossible sur réseau mobile faible (blocage de toute la file) ; ✅ **corrigé** : lots de 350 Ko maximum (plus gros envoi mesuré : 284 Ko), délai adapté à la taille ; 30 / 30 reçus |
| 9 | Session refusée par Supabase pendant la période hors ligne | ✅ saisies conservées, reconnexion, envoi complet |
| 10 | Wi-Fi d'hôtel (portail) ou serveur en panne qui répond une erreur | ❌ avant : la session était effacée (reconnexion obligatoire) ; ✅ **corrigé** : seule une réponse explicite de Supabase met fin à la session |
| 11 | Réseau intermittent (une requête sur deux perdue) | ✅ 8 / 8 signalements, aucun doublon |
| 12 | Voyant de synchronisation pendant une panne | ❌ avant : « ☁ Erreur · 12 » (inquiétant) ; ✅ **corrigé** : « ☁ Hors réseau · 12 en attente » + explication |

Corrections publiées en **v28** (`js/sync.js`, `js/app.js`).

## 3. Reste à améliorer

- **Même champ modifié sur deux téléphones** : prévenir (« modifié entre-temps par … ») au lieu de garder silencieusement
  la dernière version ; à faire avec la phase Stabilité.
- **Nouvelle version publiée pendant une période hors ligne** et **iPhone 8 jours sans ouverture** : à vérifier sur
  vrais téléphones (§4).

## 4. Protocole sur vrais téléphones (Android et iPhone)

Préparation : compte technicien de test sur la recette, appli ajoutée à l'écran d'accueil depuis app.perfora.ma,
connexion faite, synchro « À jour ».

| # | Action | Attendu |
|---|---|---|
| T1 | Mode avion, fermer complètement l'appli, la rouvrir | L'appli s'ouvre avec les données ; voyant « Hors réseau » |
| T2 | En mode avion : signaler avec 2 photos, J'interviens, Terminer | Tout s'enregistre ; « Hors réseau · N en attente » |
| T3 | Éteindre le téléphone, le rallumer, rouvrir (toujours en mode avion) | Saisies toujours là |
| T4 | Couper le mode avion | Envoi seul en moins d'une minute, « À jour » ; vérifier sur un 2e appareil |
| T5 | En 3G faible ou partage de connexion lointain : 5 signalements avec photos | Envoi complet, sans blocage |
| T6 | Mode avion pendant que je publie une nouvelle version ; couper le mode avion | Message « nouvelle version » ; saisies en attente conservées après rechargement |
| T7 | iPhone : appli installée, ne pas l'ouvrir 8 jours | À l'ouverture, données et session présentes |
| T8 | iPhone : même essai **sans** installer (dans Safari) | Noter ce qui est perdu (attendu : risque d'effacement) — sert au guide utilisateur |

Résultat attendu à noter pour chaque test : OK / KO + capture d'écran en cas de KO.

## 5. Résultat sur vrais téléphones (7 nov. 2026)

Après correction du flux de connexion (v29 – v30 : écran de connexion à l'ouverture, démo séparée jamais envoyée,
réinitialisation des démos), essai réussi sur téléphone par Hicham avec le compte technicien de test (VITRINE).
Reste en cours : **T7** (iPhone, appli installée, 8 jours sans ouverture) — à vérifier vers le 15 nov. 2026.
