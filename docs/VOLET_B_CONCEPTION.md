# Volet B — Magasin relié au terrain : proposition de conception

Statut : choix 1 à 5 **validés** le 6 nov. 2026. **B1 fait** : `calculs.js` (stockPhysique, qteReservee, stockDisponible, etatBesoin, rapprochementBesoin, retraitsAVerifier) + `tests/magasin.test.js` (8 tests, dont les 3 scénarios §37). B2 à B5 à venir.
Références V3 : §6 (demande de matériel, attente, une demande ne consomme pas le stock), §15 (demander,
remettre, utiliser, retourner ; retrait urgent), §16 (réceptionner, isoler, inventorier), §35 (besoin,
réservation, mouvement, rapprochement de remise), §37 (scénarios « deux pièces remises, une utilisée et une
rendue », « réservation partiellement servie », « retrait urgent régularisé sans doublon »).

## 1. Cinq faits distincts, jamais confondus

| Fait | Qui | Effet sur le stock physique |
|---|---|---|
| **Besoin** (demande de pièce depuis une intervention) | technicien, responsable | aucun |
| **Réservation** (le magasin bloque la quantité) | magasinier | aucun — diminue le **disponible** |
| **Remise** (la pièce sort du magasin vers le technicien) | magasinier ; ou **retrait urgent** par le technicien | − quantité |
| **Utilisation** (montée sur l'équipement) | technicien | aucun (déjà sortie) |
| **Retour** (pièce non utilisée rendue) / **rebut** | technicien → magasinier | + quantité / aucune remise en stock |

`stock physique` = somme des mouvements (réception, remise, retour, ajustement) — **par site**.
`réservé` = quantités réservées non encore remises. `disponible` = physique − réservé.
Rapprochement d'une remise : `remis = utilisé + retourné + encore détenu` (écart visible, jamais corrigé en silence).

## 2. Modèle (même synchronisation que l'existant : nouvelles fiches dans `fiches`)

- **`besoins`** (nouveau, par site) : intervention, article **ou** description libre, quantité, unité, urgent,
  statut `demande / reserve / partiellement_remis / remis / indisponible / annule`, quantités réservée et remise,
  délai annoncé par le magasin, demandeur, dates-jalons (demande, réservation, remise).
- **`mouvements`** (existant) : nouveaux types `remise`, `retour`, `rebut` ; lien `besoinId` ; `urgent` +
  `aVerifier` / `verifiePar` / `verifieLe` pour le retrait urgent ; quantités et dates jamais modifiées.
- **Pièces de l'intervention** (existant) : deviennent la déclaration d'**utilisation**, reliée à la remise.
- **Attente « pièce »** de l'intervention reliée au besoin : levée automatiquement quand le besoin est remis
  (date de fin = date de remise), avec un message au technicien.

## 3. Règles serveur (ajoutées à `push_fiches`, module « magasin » du pack requis)

- `besoins` : création par technicien / prestataire / responsable ; réservation, remise, statut « indisponible »
  par magasinier / responsable uniquement.
- Mouvements : réception, ajustement, réservation, remise normale = magasinier / responsable ; technicien :
  **retrait urgent** (marqué « à vérifier ») et **retour** seulement, toujours rattachés à une intervention.
- Un retrait urgent puis une remise du magasin sur le même besoin ne débitent pas deux fois (rapprochement).

## 4. Écrans

- **Intervention** : section « Pièces » → *Demander une pièce* (article ou texte, quantité, urgent) ; état de
  chaque besoin (badge) ; *Retrait urgent* ; *J'ai utilisé* / *Je rends*.
- **Magasin** : onglets **À servir** (besoins triés par urgence et ancienneté : Réserver, Remettre, Indisponible
  + délai), **À vérifier** (retraits urgents), **Stock** (physique / réservé / disponible par site, sous le mini).
- **Accueil du magasinier** : besoins à servir, retraits à vérifier, articles sous le mini.
- Indicateurs : besoins non couverts, délai demande → remise (date-jalon, pas de chronomètre).
- Prix : non affichés dans ce volet (valorisation = volet C).

## 5. Étapes

| Étape | Contenu | Vérification |
|---|---|---|
| B1 | Calculs (stock, réservé, disponible, rapprochement, état du besoin) dans `calculs.js` | Tests des 3 scénarios §37 + cas limites |
| B2 | Serveur : type `besoins`, droits, module, règles de mouvement (`supabase/magasin.sql`) | Tests SQL (`tests_magasin.sql`) |
| B3 | Intervention : demander, retrait urgent, utiliser, rendre ; levée d'attente | Navigateur, 2 appareils |
| B4 | Magasin : À servir, À vérifier, Stock par site ; accueil magasinier | Navigateur, rôle magasinier |
| B5 | Faux serveur, recette, docs, publication | — |

## 6. Choix proposés (à confirmer)

1. **Stock par site** (chaque site a son magasin) ; pas encore d'emplacements détaillés ni de transferts entre sites.
2. **Retrait urgent autorisé aux techniciens**, toujours « à vérifier » par le magasinier.
3. **Pas de prix** dans ce volet (valorisation, CUMP et réapprovisionnement = volet C).
4. **Besoin hors catalogue** (description libre) accepté ; le magasinier peut le rattacher ensuite à un article.
5. Les **pièces déjà saisies** dans les interventions existantes restent valables (lues comme « remises et utilisées »).
