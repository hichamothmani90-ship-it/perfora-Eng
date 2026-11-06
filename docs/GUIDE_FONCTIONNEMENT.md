# GMAO terrain — comprendre et présenter l'application

Guide simplifié pour comprendre le fonctionnement et faire une démonstration.
Version du 6 novembre 2026.

---

## 1. En une phrase

**Une application de maintenance qui tient dans la poche du technicien** : on signale une panne en
30 secondes, on clôture une intervention en 2 minutes, même sans réseau, et le responsable obtient
des indicateurs fiables par équipement, avec une traçabilité complète pour les audits.

## 2. Trois promesses

| Promesse | Concrètement |
|---|---|
| **Simple sur le terrain** | Pas de chronomètre, pas de formulaire interminable. On choisit l'équipement (ou on scanne son QR code), on coche, on écrit une phrase. |
| **Fonctionne partout** | Atelier sans Wi-Fi, sous-sol, zone blanche : tout est enregistré sur le téléphone et part au serveur dès que le réseau revient. |
| **Preuves d'audit** | Chaque saisie est signée et datée ; rien n'est effacé ; une correction garde l'ancienne valeur et son motif (ISO 9001 / 14001 / 45001). |

## 3. Les notions à connaître

| Notion | Ce que c'est | Exemple |
|---|---|---|
| **Équipement** | Une machine ou une utilité, rangée dans un lieu, avec son QR code | Presse hydraulique 200 t — Atelier presses |
| **Demande** | Ce qu'on constate ou ce qu'on nous demande | « Le vérin ne tient plus la position », état *indisponible* |
| **Intervention (OT)** | Le travail organisé pour y répondre | Remplacement du joint, résultat *résolu* |
| **Arrêt de production** | Oui / Non / Inconnu, avec début et fin **facultatifs** | La durée n'apparaît que si les deux heures sont connues |
| **Préventif** | Un programme répété (tous les 30 jours…) qui crée les interventions à faire | Vidange compresseur tous les 90 jours |
| **Magasin** | Articles, stock, pièces sorties sur une intervention | 1 joint de vérin utilisé sur l'OT |
| **Journal** | L'historique de toutes les saisies et corrections | « statut : en cours → clôturée, par Technicien A, 06/11 11:20 » |

## 4. Le parcours en 5 écrans

1. **Accueil** — ce qui demande une action aujourd'hui : équipements indisponibles, demandes à examiner, mes travaux, préventif à lancer.
2. **Signaler** (bouton bleu, ou scan du QR de la machine) — équipement, état, besoin, constat, impact. Case *« Je prends en charge et j'interviens »* : la demande et l'intervention sont créées d'un geste.
3. **Intervention** — intervenants, arrêt oui/non, ce qui a été fait, résultat, cause (*non déterminée*, *probable*, *confirmée*), pièces, réserves. Tout s'enregistre au fil de la saisie.
4. **Clôture** — l'appli vérifie l'essentiel : nature, résultat, pas de réserve bloquante, une suite si le résultat est partiel.
5. **Indicateurs** — interventions par nature, délai de clôture, préventif réalisé à l'échéance, pannes répétitives, pièces par équipement, arrêts (seulement sur heures connues). Jamais de classement des personnes.

## 5. Qui fait quoi (rôles)

| Rôle | En pratique |
|---|---|
| **Responsable maintenance** | Configure (équipements, préventif, équipe), corrige une intervention clôturée, voit tout |
| **Technicien / Prestataire** | Signale, prend en charge, intervient, clôture ses interventions |
| **Magasinier** | Gère les articles et les mouvements de stock |
| **Exploitation** | Signale des demandes |
| **Pilote / Direction** | Consulte les indicateurs, ne modifie rien |

Les droits sont vérifiés **par le serveur** : un téléphone modifié ne peut pas les contourner.

## 6. Hors ligne et synchronisation, expliqués simplement

- Le téléphone garde **sa propre copie** des données : l'appli s'ouvre et enregistre sans réseau.
- Un voyant en haut indique l'état : **☁ À jour**, **☁ 3 à envoyer**, **☁ Erreur**.
- Quand deux personnes modifient la même intervention, **les deux saisies sont conservées** si elles portent sur des champs différents (l'une la cause, l'autre les travaux).
- Une saisie refusée par le serveur (manque de droits) est annoncée, et l'appareil reprend la bonne version.

## 7. Scénario de démonstration (10 minutes)

Matériel : un PC (vidéoprojecteur) + un téléphone, connectés au même compte de démonstration.

| Minute | Action | Message à faire passer |
|---|---|---|
| 0-1 | Ouvrir l'**Accueil** sur le PC : 1 équipement indisponible, 1 demande à examiner, préventif en retard | « Le responsable voit d'un coup d'œil ce qui compte aujourd'hui. » |
| 1-3 | Sur le téléphone : **scanner le QR** collé sur une machine (planche imprimée) → *Signaler* → état *Indisponible*, besoin *Corriger*, une phrase, cocher *Je prends en charge* | « 30 secondes, sans saisie de code ni de liste. » |
| 3-4 | Passer le téléphone **en mode avion**, ajouter une photo et une pièce utilisée | « Pas de réseau ? Aucun problème. » Montrer le voyant *☁ 2 à envoyer*. |
| 4-5 | Réactiver le réseau : le voyant passe à *À jour* ; sur le PC, l'intervention apparaît | « Tout le monde voit la même chose, sans ressaisie. » |
| 5-7 | Sur le téléphone : résultat *Résolu*, cause *Probable* → **Clôturer** (essayer d'abord sans résultat : l'appli bloque) | « Les règles de qualité sont dans l'outil, pas dans un classeur. » |
| 7-8 | Sur le PC : ouvrir l'historique de l'intervention, puis le **Journal** | « Preuve d'audit : qui, quoi, quand, ancienne et nouvelle valeur. » |
| 8-9 | **Indicateurs** : pannes répétitives (le convoyeur), préventif à l'échéance, arrêts « 2 sur 3 renseignés » | « Des chiffres honnêtes : on montre ce qu'on sait, et ce qui manque. » |
| 9-10 | Montrer un compte **technicien** : pas de bouton de configuration ; une intervention clôturée est en lecture seule | « Chacun son rôle, contrôlé par le serveur. » |

Conseils : préparer la planche de QR **depuis l'adresse en ligne** ; charger les données de démonstration
la veille ; avoir un deuxième téléphone en secours.

## 8. Questions fréquentes de prospects

- **Faut-il installer quelque chose ?** Non : une adresse web, que l'on peut « ajouter à l'écran d'accueil » comme une application.
- **Et sans internet ?** Tout fonctionne ; l'envoi se fait au retour du réseau.
- **Où sont les données ?** Sur un serveur en Europe (Frankfurt) ; chaque client sera isolé (multi-entreprise, à venir). Formalités CNDP à valider avant mise en production.
- **Peut-on importer nos équipements ?** Prévu (import Excel contrôlé, volet F).
- **Suivez-vous le temps des techniciens ?** Non, volontairement : on suit les machines, pas la productivité individuelle.
- **Et le magasin, les achats, l'énergie ?** Magasin simple disponible ; lien terrain ↔ magasin, réapprovisionnement et énergie / eau sont les prochains volets.

## 8 bis. Préparer et réinitialiser la démo commerciale

- Entreprise de démonstration : **Vitrine Perfora**, compte de présentation **hicham.othmani90@gmail.com**
  (responsable, site « Usine de démonstration »).
- **Avant** la présentation : sur votre compte principal, **Plus → Console plateforme → Vitrine Perfora →
  Réinitialiser la démo** ; sur l'appareil de présentation, **Réglages → Synchroniser maintenant**.
- Pour montrer le multi-site ou un client : la console permet aussi de créer une entreprise d'essai
  (pack, premier site, invitation du responsable) en une minute, devant le prospect.

## 9. Ce qui est disponible / ce qui arrive

| Disponible aujourd'hui | Prochains volets |
|---|---|
| Demandes, interventions, préventif, QR codes, photos | Magasin relié au terrain (réservation, remise, retour) |
| Hors ligne + synchronisation, rôles et droits, multi-entreprise et multi-site, packs et quotas, invitations, console plateforme | Réapprovisionnement et achats |
| Indicateurs par équipement, journal d'audit, export CSV | Énergie et eau |
| Magasin simple (stock, sorties sur intervention) | Rapports mensuels, imports Excel |

Feuille de route détaillée : [`FEUILLE_DE_ROUTE.md`](FEUILLE_DE_ROUTE.md).
