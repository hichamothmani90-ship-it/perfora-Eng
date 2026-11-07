# Lot R5 — magasin ↔ achats relié : maquettes et spécification

Source : audit (docs/AUDIT_UX_MODELE_DONNEES.md §8, scénarios 8, 9, 10 ; M7) ; décisions Q2 (rôle Achats = celui qui
commande) et Q2 bis (repli si l'entreprise n'a pas d'acheteur). Maquette interactive présentée dans la conversation du
7 nov. **Validé le 7 nov. 2026 (propositions R5-a à R5-d retenues) ; fait en v40 (voir §14).**

Constat de départ (v39) : une pièce « indisponible » pour une intervention affiche un délai, mais ne crée ni ne
rattache aucune demande d'achat. À la réception, rien ne dit qu'une intervention attend cette pièce : il faut s'en
souvenir. Une panne urgente suit le même circuit que le réapprovisionnement (validation d'abord). Le fournisseur est
écrit en texte sur la commande, alors que la fiche Société existe (R3).

## 1. Le circuit relié

```
Technicien            Magasin                    Responsable        Qui commande         Magasin
Demande une pièce ─► Indisponible ─► « Demander l'achat » ─► Valide ─► Commande passée ─► Réception
   (intervention         (1 geste,     DA pré-remplie,                 (fournisseur,        │
    en attente)          délai)        liée à la pièce)                 livraison prévue)    ▼
                                                                                    « Réserver pour OT-0042 »
                                                                                    (proposé, coché)
Technicien ◄──────────── voit chaque étape sur sa pièce ◄──────────── « Pièce arrivée, réservée » ─► Remise ─► attente levée
```

- **Une pièce suit sa demande d'achat** : chaque ligne de pièce de l'intervention affiche son étape, et le technicien
  n'a plus à demander au magasin où en est sa pièce.
- **Urgent** : la commande peut partir avant la validation, puis le responsable valide après coup (§4).

## 2. Magasin : pièce indisponible → demande d'achat (scénario 8)

```
┌─ À servir ────────────────────────────────────────┐
│ Roulement 6205-2RS · 2 · OT-K3-0042 Presse 200 t  │
│ Indisponible · stock 0 · en commande 0  [Urgent]  │
│ [ Demander l'achat ]  [ Ajouter à DA-K3-0012 ]    │
│ [ Délai seulement ]                               │
└───────────────────────────────────────────────────┘
```

- « **Demander l'achat** » crée une demande d'achat **pré-remplie** :
  - article (ou désignation pour une pièce hors catalogue) et quantité manquante ;
  - motif « pour OT-K3-0042 · Presse 200 t » ;
  - lien vers la pièce et l'intervention ;
  - **urgente** si la pièce est urgente (modifiable).
- La pièce passe « indisponible · achat demandé » : un seul geste, sans ressaisie.
- « **Ajouter à DA-…** » : proposé si une demande d'achat du même site est encore en brouillon ou soumise. La pièce
  devient une ligne de plus, ce qui évite trois demandes pour un même fournisseur.
- « **Délai seulement** » : l'indisponibilité actuelle (délai annoncé, sans achat), par exemple quand la pièce est déjà
  commandée ailleurs.
- Depuis la liste « À réapprovisionner », rien ne change.

## 3. Sur l'intervention : la pièce montre où elle en est

```
Pièces
 2 × Roulement 6205-2RS                          [Urgent]
   Demandée 07/11 08:10 par Karim B.
   ● Indisponible ─ ● Achat demandé DA-K3-0012 ─ ● Commandée 07/11 (Roulements SA)
   ─ ○ Livraison prévue 09/11 ─ ○ Reçue ─ ○ Remise
```

- Étapes affichées, calculées à partir des fiches existantes et sans nouvelle saisie : demandée → réservée / indisponible
  → achat demandé → validé → commandé (fournisseur, livraison prévue) → reçu et réservé → remis.
- Le technicien voit la **date de livraison prévue**. S'il est en attente « pièce », son accueil affiche « **Pièces
  arrivées** » dès la réception.
- Le responsable voit dans « En attente de pièce » la date prévue de chaque intervention bloquée.

## 4. Achat urgent (scénario 9)

- Une demande d'achat **urgente** (case cochée, motif obligatoire, par exemple « presse à l'arrêt ») peut être
  **commandée avant d'être validée** par la personne qui commande (§5).
- Le responsable la **valide après coup** : son accueil affiche « Achats urgents à valider (n) ». S'il la refuse après
  coup, la commande reste tracée, avec le refus et son motif au journal.
- Sans urgence, rien ne change : brouillon → soumise → validée → commandée.

## 5. Qui passe les commandes (Q2 bis)

```
Entreprise → Règles
  Qui passe les commandes aux fournisseurs ?
  (Achats)  (Responsable)  (Magasinier)
  Le responsable peut toujours commander lui-même.
```

- Réglage de l'entreprise `quiCommande`, **par défaut « Achats »**. Sans compte Achats actif, les demandes à commander
  arrivent sur l'accueil du responsable.
- « Magasinier » : le magasinier peut renseigner la commande (fournisseur, référence, prix, livraison prévue). Le
  serveur l'accepte seulement avec ce réglage.

## 6. Commande : fournisseur choisi, pas tapé (M7)

- Dans « Commande passée », le fournisseur se **choisit parmi les sociétés fournisseurs** (fiche R3), avec
  « + Nouveau fournisseur ». Le texte libre reste possible pour une commande ponctuelle.
- Le **délai habituel** du fournisseur pré-remplit la livraison prévue (date de commande + délai).

## 7. Réception : réservation proposée (scénarios 8 et 10)

```
┌─ Réception DA-K3-0012 ────────────────────────────┐
│ Roulement 6205-2RS — reçu [ 2 ]  dont isolé [ 0 ] │
│ ☑ Réserver 2 pour OT-K3-0042 · Presse 200 t       │
│   (en attente de cette pièce depuis 2 j)          │
│                       [ Enregistrer la réception ]│
└───────────────────────────────────────────────────┘
```

- Pour une ligne liée à une pièce : « **Réserver pour OT-…** » est proposé et **coché**. La quantité réservée ne
  dépasse jamais le reçu utilisable : une pièce isolée n'est pas réservée.
- **Pour toute entrée en stock** d'un article attendu (réception d'une commande, entrée sans commande, retour) :
  l'appli propose aussi de réserver pour les **pièces indisponibles** de cet article, les urgentes d'abord, puis les
  plus anciennes. Cela couvre l'achat au comptoir (scénario 10).
- Après la réservation, le technicien voit « Reçue, réservée — à retirer au magasin ». La **remise** physique reste un
  geste du magasin et lève l'attente de l'intervention, comme aujourd'hui (§9, R5-a).

## 8. Sans le module Achats (pack Pro)

- Le magasin n'a pas de demande d'achat. Sur une pièce indisponible, « **Commandée** » note le fournisseur (choisi ou
  texte), la date de commande et la livraison prévue. Le technicien voit la même frise, en plus courte.
- À l'entrée en stock de l'article, la réservation est proposée de la même façon (§7).

## 9. Données et serveur

- `besoins` : `achatId`, `ligneId` (demande d'achat liée) ; `commande` = { fournisseurId ou fournisseur, le,
  livraisonPrevue } (sans module Achats). Le statut `indisponible` est inchangé ; l'étape affichée est **calculée**
  (`Calculs.suiviBesoin`).
- `achats` : `urgent`, `motifUrgence`, `valideApresCoup` ; lignes `besoinId`, `otId` ; `fournisseurId` (texte
  `fournisseur` gardé pour l'historique).
- `parametres.quiCommande` : `achats` | `responsable` | `magasinier`.
- Règles serveur (`push_fiches`) :
  - commande renseignée par le rôle désigné (ou le responsable) ;
  - demande urgente commandable avant validation, motif obligatoire ;
  - validation après coup réservée au responsable ;
  - lien `besoinId` d'une ligne vérifié (même entreprise, même site) ;
  - réservation à la réception = droits du magasin, inchangés.
- Tests SQL et serveur factice alignés, avec un scénario « pièce indisponible → commandée → reçue → réservée →
  remise → attente levée ».

## 10. Hors périmètre (C bis et plus tard)

Inventaire, emplacements, conditionnement, achats non stockés (prestations), retour fournisseur tracé, comparaison
de devis, transfert entre sites, budget, notifications par e-mail ou SMS.

## 11. Mesures d'acceptation

- De la pièce indisponible à la demande d'achat liée : **1 geste** (plus la confirmation).
- À la réception, la réservation pour l'intervention en attente est proposée **sans recherche**.
- Le technicien voit l'étape et la date prévue de sa pièce sans rien demander à personne.
- Un achat urgent peut être commandé dans la minute, puis validé ensuite, avec une trace complète au journal.
- Téléphone (375 × 812) : la carte « À servir » et la ligne de pièce tiennent sans défilement horizontal.

## 12. Durée et ordre

2 – 3 jours : calcul `suiviBesoin` et tests → serveur (quiCommande, urgent, liens) et tests → magasin (Demander
l'achat, Ajouter à la DA) → frise sur l'intervention et accueils → commande (fournisseur choisi) → réception et entrée
avec réservation proposée → recette par rôle sur téléphone.

## 13. Points à valider par Hicham

| # | Question | Proposition |
|---|---|---|
| R5-a | L'attente « pièce » d'une intervention se lève à la **réception** ou à la **remise** ? | à la remise (pièce en main) ; à la réception, le technicien voit « arrivée, réservée » |
| R5-b | Achat **urgent** : commande avant validation, validation après coup par le responsable ? | oui ; motif obligatoire ; la case « Urgent » se coche d'office si la pièce est urgente |
| R5-c | **Qui commande** par défaut ? | Achats ; le responsable peut toujours ; magasinier sur réglage |
| R5-d | Sans module Achats (Pro) : suivi simple « commandée » sur la pièce + réservation proposée à l'entrée ? | oui |

## 14. Fait (7 nov. 2026, v40)

- **Calculs** (`js/calculs.js`, `tests/magasin_r5.test.js`, 8 tests) : `suiviBesoin` (étapes de la pièce, depuis la
  pièce, sa demande d'achat ou son résumé, et les mouvements), `achatDuBesoin`, `besoinsEnAttenteArticle` (urgentes
  puis plus anciennes, reste à réserver), `urgentsAValider`, `peutCommander`.
- **Serveur** `supabase/magasin_r5.sql` (généré par `scripts/generer_magasin_r5.py`, après `stabilite_s1.sql`) :
  motif obligatoire d'un achat urgent ; commande d'une demande urgente encore soumise ; commande par le magasinier
  seulement si `parametres.quiCommande = magasinier` (champs de la commande uniquement) ; **résumé sans prix recopié
  sur la pièce** (`besoins.suiviAchat` : référence, étape, urgence, fournisseur, dates) à chaque écriture d'une
  demande d'achat, car les techniciens ne lisent pas les achats (prix). Tests : `tests_magasin_r5.sql` 12/12 sur une
  base neuve, 18 fichiers SQL rejoués sans écart ; serveur factice aligné (`tests/magasin_r5_serveur_test.py` 10/10).
- **Appli** :
  - magasin : « Demander l'achat » (demande pré-remplie, liée, soumise d'office, urgente au choix avec motif) et
    « Ajouter à DA-… » seulement si la pièce manque (indisponible, stock insuffisant ou hors catalogue) ;
    « Commandée » sans module Achats ; frise sur la carte ; à toute entrée en stock, réservation proposée pour les
    pièces en attente ;
  - achats : badge « Urgent » et « À valider après coup », groupe « À commander » avec les urgentes,
    « Renseigner la commande (urgent, avant validation) », « Valider / Refuser après coup », fournisseur choisi parmi
    les sociétés (délai habituel → livraison prévue), lien vers l'intervention sur la ligne, réception avec
    « Réserver pour OT-… » coché ;
  - intervention : frise de chaque pièce ; accueil technicien « Pièces attendues » (avec la frise) ;
  - accueils : « Achats urgents à valider » (responsable), « Achats à commander » pour la personne désignée ;
    Entreprise → Règles « Qui passe les commandes ? ».
- Recette (démo locale, v40) : pièce indisponible → demande urgente → commandée avant validation → reçue et
  réservée d'office → validée après coup ; frise juste à chaque étape ; entrée « achat comptoir » → réservation
  proposée (urgente d'abord) ; téléphone 375 px sans défilement horizontal.
- Écart : l'attente « pièce » se lève toujours à la remise (R5-a), sans changement du code existant.
