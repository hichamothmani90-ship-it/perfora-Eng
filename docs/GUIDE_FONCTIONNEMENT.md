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
| **Demande de pièce** | Ce que le technicien demande au magasin depuis l'intervention ; elle ne retire rien du stock | 1 rouleau tendeur, urgent |
| **Seuils** | Par article et site : sécurité, point de commande, cible ; proposés par le magasin, validés par le responsable | Joint : commander sous 4, viser 8 |
| **À réapprovisionner** | Liste calculée : disponible − demandes non couvertes + en commande, sous le point de commande ; propose une quantité, ne commande rien | « 6 joints proposés » |
| **Demande d'achat** | Besoin validé par le responsable, puis commande passée chez le fournisseur (hors Perfora) et réceptions, même partielles | 3 filtres commandés, 2 reçus, 1 attendu |
| **Valeur du stock** | Coût moyen pondéré par article et site ; une quantité sans prix est montrée à part, jamais à zéro | 58 L d'huile à 42 MAD |
| **Magasin** | Réserve, remet, vérifie les retraits urgents ; stock par site (physique, réservé, disponible) | Remise du rouleau → l'intervention redevient « Prête » |
| **Journal** | L'historique de toutes les saisies et corrections | « statut : en cours → clôturée, par Technicien A, 06/11 11:20 » |

## 4. Le parcours en 5 écrans

1. **Accueil** — ce qui demande une action aujourd'hui : équipements indisponibles, demandes à examiner, mes travaux, préventif à lancer.
2. **Signaler** (bouton bleu, ou scan du QR de la machine) — équipement, état, besoin, constat, impact. Case *« Je prends en charge et j'interviens »* : la demande et l'intervention sont créées d'un geste. Depuis une demande reçue : *J'interviens maintenant* (un clic) ou *Planifier une intervention* (créneau et intervenant).
3. **Intervention** — intervenants, arrêt oui/non, ce qui a été fait, résultat, cause (*non déterminée*, *probable*, *confirmée*), pièces, réserves. Tout s'enregistre au fil de la saisie.
4. **Terminer** — une seule fenêtre : ce qui a été fait, résultat, cause si connue, fin d'arrêt, suite à donner ; l'intervention est clôturée si tout y est, sinon la saisie est gardée et l'appli dit ce qui manque. Elle vérifie l'essentiel : nature, résultat, pas de réserve bloquante, une suite si le résultat est partiel.
5. **Indicateurs** — interventions par nature, délai de clôture, préventif réalisé à l'échéance, pannes répétitives, pièces par équipement, arrêts (seulement sur heures connues). Jamais de classement des personnes.

## 5. Qui fait quoi (rôles)

| Rôle | En pratique |
|---|---|
| **Responsable maintenance** | Configure (équipements, préventif, équipe), corrige une intervention clôturée, voit tout |
| **Technicien / Prestataire** | Signale, prend en charge, intervient, clôture ses interventions |
| **Magasinier** | Sert les demandes de pièces (réserver, remettre, indisponible + délai), vérifie les retraits urgents, propose les seuils, rédige les demandes d'achat, réceptionne (y compris partiellement), isole et inventorie |
| **Achats** (facultatif) | Renseigne la commande passée chez le fournisseur (référence, prix, délai) sur une demande validée ; ne valide rien |
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
| + 4 min | **Achats** (option, pack Entreprise) : **Magasin → À réapprovisionner** : le joint est sous son point de commande, 6 proposés → **Créer la demande d'achat** → Soumettre ; en responsable **Valider**. Puis **Plus → Achats** : la commande de filtres DA-DEMO-0001 → **Réceptionner** 2 dont 1 isolée → décision **Libérer**. Finir par **Valeur du stock** | « Le stock se pilote : seuils validés, rien n'est commandé sans décision, une livraison partielle reste visible, et les prix restent invisibles aux techniciens. » |
| + 3 min | **Magasin** (option) : sur l'intervention du convoyeur, la pièce « Rouleau tendeur » est demandée en urgence ; ouvrir **Magasin → À servir** → **Remettre**. Sur le téléphone du technicien : « Pièce remise : … peut reprendre ». Puis **À vérifier** : le retrait urgent d'huile → **Vérifié** | « Demande, réservation, remise, utilisation, retour : cinq faits distincts, un stock juste, sans ressaisie. » |
| + 4 min | **Énergie et eau** (option, pack Entreprise) : sur le téléphone du technicien, l'accueil montre **1 relevé à faire** (heures du compresseur) → **Relever** : on tape l'index, contrôle immédiat « ✓ Cohérent : +… h » ; taper un chiffre plus bas pour montrer l'alerte « index plus bas » et le choix « compteur remplacé ». Sur le PC : **Plus → Énergie et eau**, mois dernier : électricité totale **sur l'arrivée générale seulement**, sous-compteurs en retrait, couverture « 28 j sur 31 », résidu **≈ 7 % à expliquer** → **Créer une demande**. Onglet **À examiner** : l'eau lue 4 718 au lieu de 3 718 (exclue des calculs) → **Invalider** ; la facture ONEE en **écart +6,3 %**. Onglet **Factures** : la facture du 2 au 30 (dates exactes, pas le mois civil). Enfin **Préventif** : la vidange selon les heures est **en alerte** (reste 48 h) | « Des chiffres d'énergie honnêtes : jamais d'addition entre unités ni de valeur inventée ; un écart déclenche une vérification, pas une accusation. » |
| 9-10 | Montrer un compte **technicien** : pas de bouton de configuration ; une intervention clôturée est en lecture seule | « Chacun son rôle, contrôlé par le serveur. » |

Conseils : préparer la planche de QR **depuis l'adresse en ligne** ; charger les données de démonstration
la veille ; avoir un deuxième téléphone en secours.

## 8. Questions fréquentes de prospects

- **Faut-il installer quelque chose ?** Non : une adresse web, que l'on peut « ajouter à l'écran d'accueil » comme une application.
- **Et sans internet ?** Tout fonctionne ; l'envoi se fait au retour du réseau.
- **Où sont les données ?** Sur un serveur en Europe (Frankfurt) ; chaque client sera isolé (multi-entreprise, à venir). Formalités CNDP à valider avant mise en production.
- **Peut-on importer nos équipements ?** Prévu (import Excel contrôlé, volet F).
- **Suivez-vous le temps des techniciens ?** Non, volontairement : on suit les machines, pas la productivité individuelle.
- **Et le magasin, les achats, l'énergie ?** Le magasin est relié au terrain (demande de pièce, réservation, remise, retrait urgent vérifié, retour, stock par site) et aux achats : seuils validés, liste « à réapprovisionner », demande d'achat, commande saisie, réceptions partielles, pièces isolées, valeur du stock. L'énergie et l'eau aussi : compteurs avec QR, relevés hors ligne avec contrôle immédiat, consommations par mois avec couverture, sous-comptages, factures d'énergie (PDF joint) rapprochées des relevés, préventif selon les heures de marche.
- **Les techniciens voient-ils les prix ?** Non : le serveur ne leur envoie ni les demandes d'achat, ni les prix, ni les factures d'énergie, ni l'historique de ces montants.
- **L'appli lit-elle nos factures ou nos compteurs automatiquement ?** Pas encore : on saisit la facture (période, quantité, montant) et on joint le PDF ; les relevés se font au QR. Les compteurs connectés viendront ensuite.
- **Perfora passe-t-il les commandes ?** Non, volontairement : on suit le besoin, la décision et la livraison ; la commande reste dans votre circuit fournisseur habituel.

## 8 bis. Préparer et réinitialiser la démo commerciale

- Entreprise de démonstration : **Vitrine Perfora**, compte de présentation **hicham.othmani90@gmail.com**
  (responsable, site « Usine de démonstration »).
- **Avant** la présentation : sur votre compte principal, **Plus → Console plateforme → Vitrine Perfora →
  Réinitialiser la démo** ; sur l'appareil de présentation, **Réglages → Synchroniser maintenant**.
- **Achats et valeur du stock** : visibles seulement si l'abonnement de la démo inclut le module « achats » (pack Entreprise).
- **Énergie et eau** : la réinitialisation ajoute 6 compteurs, 9 semaines de relevés (le dernier la veille), un remplacement de compteur,
  une lecture d'eau erronée, 3 factures et la vidange selon les heures. Les dates suivent le jour de la réinitialisation :
  **réinitialiser la veille ou le matin** de la présentation. Module « energie » requis (pack Entreprise).
- Pour montrer le multi-site ou un client : la console permet aussi de créer une entreprise d'essai
  (pack, premier site, invitation du responsable) en une minute, devant le prospect.

## 9. Ce qui est disponible / ce qui arrive

| Disponible aujourd'hui | Prochains volets |
|---|---|
| Demandes, interventions, préventif (dates et heures de marche), QR codes, photos et PDF | Bilan des cuves (combustible) |
| Hors ligne + synchronisation, rôles et droits, multi-entreprise et multi-site, packs et quotas, invitations, console plateforme | Rapports mensuels, imports Excel |
| Indicateurs par équipement, journal d'audit, export CSV | Pilotage avancé |
| Magasin relié au terrain : demandes de pièces, réservation, remise, retrait urgent, retour, stock par site, accueil magasinier | Fiche fournisseurs, emplacements et transferts |
| Achats : seuils, à réapprovisionner (CSV), demandes d'achat, commande, réceptions partielles, isolés, valeur du stock (CUMP) | |
| Énergie et eau : compteurs et QR, relevés hors ligne, consommations avec couverture, sous-comptages, factures et rapprochement | Compteurs connectés, ratios de production (kWh par tonne) |

Feuille de route détaillée : [`FEUILLE_DE_ROUTE.md`](FEUILLE_DE_ROUTE.md).
