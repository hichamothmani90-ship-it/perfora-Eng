---
name: gmao-perfora
description: Expertise GMAO Perfora / GMAO terrain — métier maintenance (procédure PR MAINT 01 V3), modèle de données, architecture offline-first, parcours terrain, interface mobile-first et conduite de projet. À utiliser pour toute évolution, revue, planification ou question fonctionnelle sur cette application (demandes, interventions/OT, préventif, magasin, indicateurs, journal, synchronisation, imports, rapports).
---

# GMAO Perfora — skill expert

Tu interviens comme **expert maintenance industrielle + chef de projet + architecte + designer terrain**.
Le référentiel métier est la procédure **PR MAINT 01 V3 (3 nov. 2026)** ; la décision d'arbitrage
est celle du **6 nov. 2026 : traçabilité légère, pas de chronomètre**.
Langue de l'interface, des messages et des commits : **français**.

## 1. Règles métier non négociables

Avant toute proposition, vérifie qu'elle respecte ces règles. Si une demande les contredit, dis-le
et propose l'alternative conforme.

1. **Pas de chronomètre, pas de suivi minute par minute.** On trace des faits et des dates-jalons
   (signalement, prise en charge, mise en attente/reprise, clôture). Les temps individuels sont
   facultatifs et ne servent jamais d'arrêt machine.
2. **Arrêt de production = Oui / Non / Inconnu.** Début et fin facultatifs. Une durée n'existe que si
   les deux bornes sont connues. Jamais de durée inventée, jamais « 24 h sur 24 » implicite.
3. **L'inconnu reste inconnu.** Heure du fait, cause, impact : « à confirmer » est une réponse valide.
   Une date de saisie ne remplace jamais la date du fait.
4. **Rien n'est supprimé.** Statuts (annulée, close sans travail, réformé, inactif), mouvements
   inverses, journal d'audit append-only. Corriger une intervention clôturée exige un motif.
5. **Distinctions obligatoires** :
   - demande créée ≠ affectation ≠ prise en charge effective ;
   - planifié (organisation) ≠ préventif (nature) : une réparation programmée reste corrective ;
   - état technique (normal, anomalie, dégradé, indisponible, à confirmer) ≠ impact exploitation
     (aucun, réduit, interrompu, à confirmer) ; machine arrêtée ≠ ligne arrêtée ;
   - travail terminé ≠ remise à disposition ≠ reprise réelle ≠ clôture administrative ;
   - demande de pièce ≠ réservation ≠ remise ≠ utilisation ≠ retour (un mouvement n'est saisi qu'une fois) ;
   - notification lue ≠ travail accepté.
6. **Un fait = un comptage.** Deux OT ou deux intervenants sur une même panne ne doublent ni
   l'arrêt ni le nombre de défaillances. Les plages qui se chevauchent sont fusionnées.
7. **Aucun classement individuel.** Indicateurs et objectifs portent sur les équipements.
   Prix masqués aux techniciens par défaut.
8. **La sécurité reste au site.** On stocke la référence d'un permis/consignation, on ne gère pas
   la consignation. Un arrêt de fonctionnement ne vaut pas mise en sécurité.
9. **Obligatoire au bon moment** : rien de bloquant au signalement ; la clôture exige nature
   qualifiée, résultat, suites attribuées si résultat partiel/non résolu, aucune réserve bloquante ouverte.

## 2. Conventions d'indicateurs

Chaque indicateur affiche périmètre, période, convention, couverture et effectif.

| Indicateur | Convention |
|---|---|
| Interventions par nature | OT non annulés créés sur la période |
| Délai de clôture | médiane (et moyenne) création OT → clôture, OT clôturés sur la période |
| Préventif à échéance | occurrences dues réalisées au plus tard à l'échéance initiale / occurrences dues (dont non lancées) |
| Pannes répétitives | faits (demandes anomalie/dégradé/indisponible, + correctifs sans demande) par équipement ; ≥ 2 listé, ≥ 3 « à analyser » |
| Arrêts | faits avec arrêt ; durée cumulée **uniquement** sur bornes connues, union par équipement ; afficher « k sur n renseignés » |
| MTTR (futur) | « délai moyen de rétablissement calendaire, attentes incluses », sur événements clos — jamais appelé « temps de réparation » |
| MTBF (futur) | seulement avec heures de marche fiables ; sinon « non calculable » ; 0 défaillance = « aucune observée », pas infini |
| Disponibilité (futur) | sur **temps requis** (calendrier) ; sans calendrier = couverture insuffisante, pas 100 % |

## 3. Architecture actuelle (à respecter)

- **PWA statique, sans build, sans dépendance** : `index.html`, `css/app.css`, `js/store.js` (stockage,
  journal), `js/calculs.js` (règles et indicateurs, fonctions pures), `js/qr.js` (QR hors ligne),
  `js/app.js` (écrans), `sw.js`.
- **Toute règle métier ou tout calcul d'indicateur va dans `js/calculs.js`** (testable sous Node),
  jamais directement dans une vue. Chaque nouvelle règle = un test dans `tests/`.
  Scripts classiques (pas de modules) pour rester ouvrable partout. Hébergée sur GitHub Pages
  (`hichamothmani90-ship-it/perfora-Eng`), servable en local par `serveur.py`.
- **Offline-first** : IndexedDB `gmao-terrain` ; tout est chargé en mémoire au démarrage
  (`Store.data[type]` = `Map`), chaque écriture est persistée. L'interface lit la mémoire → instantané.
- **Toute écriture passe par `Store.save` / `Store.update`** : calcul du diff champ par champ et
  écriture du journal (`auteur`, `le`, `motif`, `action`, `avant`, `apres`). Ne jamais écrire
  dans IndexedDB ni muter un objet de `Store.data` en place (le diff serait vide).
  Dans l'UI, utiliser `edit(t, id, patch, {motif, action})`.
- **Identifiants** : `id` aléatoire hex (pas `crypto.randomUUID`, absent hors HTTPS) ;
  référence lisible `PREFIX-<codeAppareil>-0007` via `Store.nextRef` (pas de collision entre appareils).
- **Dates** : chaînes locales du site `YYYY-MM-DDTHH:mm` (`Store.now()`), dates seules `YYYY-MM-DD`.
  Le fuseau est un paramètre de site (Africa/Casablanca), pas stocké par valeur.
- **Synchronisation cloud** (`js/sync.js`, Supabase via REST, sans bibliothèque) :
  `Store.save` place un **patch** (champs modifiés seulement) dans le store `sortie` ; `Sync` envoie
  par lots à la fonction SQL `push_fiches` (fusion `data || patch`, append-only pour journal, mouvements,
  photos), puis récupère par **numéro de séquence serveur** (`seq`, avec recouvrement), jamais par
  l'horloge des téléphones. À la réception : local < serveur < modifications locales non envoyées.
  Délai réseau max 20 s, session renouvelée automatiquement, erreurs en français, voyant ☁.
  Premier branchement = envoi complet automatique de l'appareil. Test local : `tests/serveur_factice.py`
  (mêmes appels et même fusion que `supabase/schema.sql`), deux « appareils » = `localhost:8080`
  et `127.0.0.1:8080` (IndexedDB séparées).
- **Rôles et droits** (`supabase/roles.sql`) : table `profils` (rôle, actif, personne liée), écriture
  **uniquement** via `push_fiches` (SECURITY DEFINER) qui applique `peut_ecrire(rôle, type)` + règles
  métier (OT clôturée = responsable ; sortie de stock sans OT = magasin ; journal d'une modification
  refusée = refusé). Réponse `{acceptes, refuses[]}` ; l'appli reprend alors la version serveur
  (`appliquerDistant(rows, {remplacer:true})`) et affiche le motif. `mon_profil()` crée la fiche
  « personne » du compte ; `definir_profil()` réservé au responsable. Côté appli, `autorise(act)` et
  `peutModifierOT()` dans `app.js` sont un **miroir** pour masquer les boutons : toute nouvelle action
  doit être classée dans `DROITS`, et toute nouvelle règle serveur reportée dans les deux + dans
  `tests/serveur_factice.py`. Sans compte cloud : aucune restriction (usage local).
  Tester une règle serveur : fonction plpgsql temporaire qui fixe `request.jwt.claims`, appelle
  `push_fiches`, puis nettoie ses données (le SQL Editor ne garde pas un `begin … rollback`).
- **Multi-entreprise** (`supabase/multitenant.sql`, volet A) : `entreprises`, `sites`, `packs` (modules :
  base, preventif, magasin, rapports, achats, energie, imports), `abonnements` (dérogations), `profil_sites`,
  `admins_plateforme`. `fiches.entreprise_id` (obligatoire, posé par le serveur) et `fiches.site_id` (nul pour
  personnes et articles). Lecture : `mon_entreprise()` + `mes_sites()`. `push_fiches` refuse dans l'ordre :
  type inconnu, abonnement non écrivable, fiche d'une autre entreprise, journal lié refusé, module hors pack
  (`module_de`), rôle (`peut_ecrire`), règles métier, puis site (envoyé › existant › hérité du parent pour
  journal / photos › site par défaut du compte) non autorisé ou changé par un non-responsable ; il recopie
  `siteId` dans `data`. `mon_profil()` renvoie entreprise, sites, siteDefaut, abonnement, adminPlateforme.
  Toute nouvelle table de données doit porter entreprise_id (+ site_id) et une politique RLS équivalente ;
  rejouer `supabase/tests_etancheite.sql` après chaque changement de règle.
- **Appli multi-site** (A2) : `list(t)` filtre les types de `Store.SITE_TYPES` sur le site actif
  (`siteActif()` : `device.siteActif`, « tous » possible si plusieurs sites ; fiche sans `siteId` = visible).
  Une nouvelle fiche de site reçoit son site dans `Store.save` via `Store.definirSite` : site du parent
  (équipement, lieu, demande, intervention, parent de photo) sinon `siteCreation()`. Pour chercher hors
  du site actif (QR, liens), lire `data[t]` directement. `Sync.chargerProfil` : changement d'entreprise =
  `Store.viderMetier()` (refusé si la file d'envoi n'est pas vide) ; premier passage multi-entreprise d'un
  appareil déjà synchronisé = resynchronisation complète. Modules : `aModule()`, `ACT_MODULE` ; abonnement
  non écrivable : `ecritureOK()` (bandeau, actions retirées). Faux serveur : 3 comptes / 2 entreprises,
  `POST /test/abonnement` pour suspendre.
- **Sans cloud** : export/import JSON ; par fiche, la plus récente (`modifieLe`) gagne ;
  rien n'est supprimé par absence.
- **Service worker** : cache d'abord, **une version = un cache complet installé d'un bloc** (jamais de
  mise à jour fichier par fichier : cela mélangerait les versions). **Incrémenter `VERSION` dans `sw.js`
  à chaque livraison** et ajouter toute nouvelle ressource à `FILES`. L'appli affiche alors
  « Nouvelle version disponible — Recharger » (pas de rechargement forcé en pleine saisie).
- **Évolution du schéma** : incrémenter `DB_VER` dans `store.js`, créer les nouveaux object stores dans
  `onupgradeneeded`, migrer les fiches existantes sans perte (valeurs par défaut lues avec `??`).

## 4. Modèle de données

Implémenté (object stores) :

| Store | Champs clés |
|---|---|
| `localisations` | code, nom, parentId (arbre site › zone › ligne) |
| `equipements` | code (= QR), designation, localisationId, famille, criticite 1-4, actif/reforme |
| `personnes` | nom, role (technicien, responsable, magasinier, prestataire, exploitation, pilote), societe, actif |
| `demandes` | ref, origine, tiers{nom,service}, equipementId, besoin, constat, etat, impact, heureFait, precisionHeure, statut, priseEnChargePar/Le, motifClassement |
| `ots` | ref, demandeIds[], programmeId, echeance, equipementId, nature, priorite, statut, creneau, intervenants[{personneId,role,depuis,fin}], activites[], travaux, resultat, cause, certitudeCause, familleDefaut, avecArret, arretDebut, arretFin, pieces[], reserves[], attentes[{motif,detail,depuis,fin,responsableId}], clotureLe/Par |
| `programmes` | equipementId, libelle, modele, periodiciteJours, prochaineEcheance, regle (fixe / apres_realisation), instruction, actif |
| `articles` | ref, designation, unite, stockMin, actif |
| `mouvements` | articleId, type (entree, sortie, retour, ajustement), qte signée, otId, motif, le — immuables |
| `journal` | entite, entiteId, action, champ, avant, apres, motif, auteur, le — append-only |
| `photos` | parentType (demandes / ots), parentId, dataUrl JPEG ≤ 1280 px, le — depuis DB v2 |
| `sortie` | file d'envoi cloud : {type, rid, patch} triés par id chronologique — propre à l'appareil |
| `meta` | `device` {code, personneId}, `compteurs`, `sauvegarde` {le}, `adresse` {url des QR}, `cloud` {url, cle, session, curseur, dernier, erreur} |

Version actuelle du stockage : **DB_VER = 3**. Côté serveur : table unique `fiches` (id, type, data jsonb,
seq, recu_le, auteur), RLS « authenticated », aucune règle DELETE.

Listes de choix : reprendre **exactement** les codes de la V3 (sections 32-33) déjà dans l'objet `L`
de `app.js`. Un nouveau choix = un code stable + libellé ; un ancien choix est désactivé, jamais effacé.

Cible V3 non encore implémentée (à ajouter par lots, voir §7) : événement technique multi-équipements
et période technique (ouverte / fin proposée / close), impact exploitation séparé, occurrence préventive
distincte de l'OT avec rapport (non requis / attendu / reçu / examiné) et verdict, calendrier de temps
requis, réservation et besoin matériel, réception partielle, CUMP, compteurs et relevés, objectifs,
lots d'import, notifications.

## 5. Parcours terrain (critères d'acceptation)

- **Signaler** : < 30 s, une seule page, 4 choix + 1 texte (équipement, état, besoin, constat ; impact
  préréglé « à confirmer »). Détails repliés. Alerte si une demande est déjà ouverte sur l'équipement.
  Case « Je prends en charge et j'interviens » = demande + OT en un geste.
- **Intervenir / clôturer** : < 2 min sur smartphone. Sauvegarde automatique à chaque champ, pas de
  bouton « Enregistrer ». Actions selon le statut : Démarrer, Mettre en attente (motif), Reprendre,
  Travail terminé, Clôturer, Rouvrir (motif).
- **Accès par QR** : `…/#/signaler?eq=CODE` ouvre le formulaire présélectionné.
- **Accueil = ce qui demande une action aujourd'hui**, le pilotage est ailleurs.

## 6. Règles d'interface

- Mobile-first (tester à 375-390 px), barre d'onglets en bas ; à partir de 900 px, menu latéral.
- Cibles tactiles ≥ 44 px, choix par **puces** plutôt que listes déroulantes, saisies en **feuille
  basse** (`askForm`) ; verbes terrain (« Signaler », « Je prends en charge », « Lever »).
- Couleurs d'alerte réservées aux états (rouge = indisponible, ambre = dégradé/attente, vert = traité).
- Toujours échapper le texte utilisateur avec `esc()` ; exports CSV protégés contre l'injection de formules.
- État vide qui explique quoi faire ; un chiffre indisponible dit quelle donnée manque.
- Retour visible après chaque action (`toast`) : « enregistré sur l'appareil ».
- Performance : rendu par chaîne HTML + délégation d'événements (`data-act`, `data-bind`), pas de framework.
  Si `app.js` dépasse ~1 500 lignes, découper par domaine (`js/vues/*.js`) en scripts classiques.

## 7. Conduite de projet

Méthode : **lots courts livrables** (1 à 2 semaines), chacun testé sur le terrain avant le suivant.

Pour chaque évolution :
1. **Cadrer** : quel acte terrain, quel acteur, quelle règle V3 (citer la section), quel indicateur alimenté.
2. **Proposer un plan court** et attendre validation si le modèle de données change.
3. **Réaliser** : modèle (migration IndexedDB) → règles → écran → indicateurs → démo mise à jour.
4. **Vérifier** (définition de « terminé ») :
   - `node --check js/*.js` sans erreur et `node --test "tests/*.test.js"` entièrement vert ;
   - scénarios de recette concernés passés dans le navigateur (voir ci-dessous) ;
   - affichage 390 px sans débordement horizontal ; fonctionnement hors ligne ;
   - aucune durée affichée sans ses deux bornes ; journal alimenté avec motif si correction ;
   - `VERSION` du service worker incrémentée ; README à jour.
5. **Livrer** : commit en français, push, vérifier l'URL GitHub Pages.

Scénarios de recette de référence (V3 §12-13) : S01 panne immédiate cause inconnue ; S02 défaut connu
sans arrêt ; S03 changement de série avec défaut découvert ; S04 préventif avec réserve ; S05 attente de
pièce + renfort (un seul arrêt) ; S06 relève de nuit et doublon ; S07 reprise différée / essai échoué ;
S08 compresseur secouru (composant indisponible, service disponible).

Priorisation : 1) ne pas perdre de données, 2) fluidité terrain, 3) traçabilité d'audit,
4) indicateurs, 5) confort de pilotage. Une fonction qui alourdit la saisie terrain doit être
facultative ou déplacée vers le responsable.

## 8. Pièges à éviter

- Ajouter un minuteur, un champ de durée obligatoire ou des « sessions de travail ».
- Déduire un arrêt de ligne de l'arrêt d'une machine, ou une panne d'un changement de série.
- Compter les OT au lieu des faits ; additionner des attentes simultanées.
- Écraser une valeur sans journal ; supprimer une fiche ; recalculer silencieusement une échéance initiale.
- Afficher un MTBF/disponibilité sans dénominateur fiable.
- Rendre un champ obligatoire au signalement « pour les statistiques ».
- Utiliser une API réservée à HTTPS sans repli (caméra, `crypto.randomUUID`, service worker).
- Oublier d'incrémenter `VERSION` : les téléphones garderaient l'ancienne version.
