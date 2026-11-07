# Lot R3 — membres, équipes, sociétés prestataires, administrateur du client : maquettes et spécification

Source : audit (docs/AUDIT_UX_MODELE_DONNEES.md §4, M3) ; décisions Q1 (administrateur du client ; Perfora n'invite que
le premier) et Q3 (le prestataire ne voit que ses interventions). Droit administrateur posé au R1 (v36). Maquette
interactive présentée dans la conversation du 7 nov. **Validé le 7 nov. 2026 (propositions R3-a à R3-d retenues) ; fait en v38 (voir §14).**

Constat de départ (Entreprise, v37) : deux listes pour les mêmes personnes (« Membres et droits » = comptes ;
« Personnes sans compte » = fiches), un compte et sa fiche peuvent porter deux noms ou deux rôles différents ; pas
d'équipes ; la société d'un prestataire est un texte libre ; pas de téléphone ; inviter = remplir l'e-mail sans savoir
si la personne existe déjà comme fiche (doublons).

## 1. Principe : une seule notion « Membre »

Un **membre** est une personne de l'entreprise ou d'un prestataire, **avec ou sans accès à l'appli** (un intervenant
sans téléphone reste possible : on l'affecte, il ne se connecte pas).

| Champ | Contenu | Note |
|---|---|---|
| Nom | affiché partout (affectation, journal, signature) | une seule source : la fiche |
| Rôle | responsable, technicien, prestataire, magasinier, achats, exploitation, direction | même liste qu'aujourd'hui |
| Équipe(s) | 0, 1 ou plusieurs (§3) | nouveau |
| Société | **Interne** ou une société prestataire (§4) | remplace le texte libre |
| Téléphone | facultatif, bouton « Appeler » sur la fiche | nouveau |
| Habilitations | liste courte : libellé + échéance facultative (ex. « B1V — 03/2027 ») | nouveau, simple (§5) |
| Accès à l'appli | **Sans accès** · **Invité** (en attente) · **Actif** · **Désactivé** ; e-mail, sites, ★ administrateur | l'invitation devient une action du membre |
| Actif / inactif | inactif = n'apparaît plus dans les choix, historique conservé | inchangé |

- Données : on garde la fiche `personnes` (renommée « Membre » à l'écran, pas de migration des interventions qui la
  citent) ; le compte (`profils`) reste relié par `personne_id`, qui existe déjà.
- **Le rôle et le nom d'un membre avec accès sont écrits une seule fois** : la fonction serveur qui change un rôle met à
  jour le compte **et** la fiche ; l'appli n'écrit plus le rôle d'un membre avec accès par la fiche.
- Les places du pack ne comptent que les **accès actifs** (inchangé) : un membre sans accès ne coûte rien.

## 2. Écran « Membres » (Entreprise → Membres)

```
┌─ Membres ───────────────────────────── 8 / 15 accès ┐
│ [🔍 Chercher un nom, un téléphone…               ]  │
│ (Tous 14) (Avec accès 8) (Sans accès 4) (Prestataires 3) (Inactifs 2) │
│                                                     │
│ MÉCANIQUE ─────────────────────────────────────     │
│  Karim B.      Technicien · chef     ● Actif        │
│  Youssef A.    Technicien            ○ Sans accès   │
│ ÉLECTRIQUE ────────────────────────────────────     │
│  Said M.       Technicien  B1V ⚠      ● Actif        │
│ SANS ÉQUIPE ───────────────────────────────────     │
│  Nadia R.      Magasinier            ◌ Invitée      │
│  Hicham O.     Responsable ★         ● Actif        │
│ PRESTATAIRES ──────────────────────────────────     │
│  Froid Service · Ali T.   Prestataire ● Actif       │
│                                                     │
│ [ + Ajouter un membre ]   [ Équipes ] [ Sociétés ]  │
└─────────────────────────────────────────────────────┘
```

- Groupé par équipe, puis « Sans équipe », puis les prestataires par société. Recherche sur nom et téléphone.
- Chaque ligne : nom, rôle, ★ si administrateur, « chef » si chef d'équipe, ⚠ si une habilitation est échue, puce
  d'accès. Une ligne ouvre la fiche du membre.
- En tête : accès utilisés / places du pack (et par site si plusieurs sites, dans la fiche « Abonnement »).

## 3. Ajouter un membre / fiche membre

**Ajouter** (un seul écran, 3 champs obligatoires au plus) :

```
┌─ Ajouter un membre ─────────────────────────┐
│ Nom *            [ Youssef Amrani        ]  │
│ Rôle *           (Technicien) (Magasinier) …│
│ Société          (Interne) (Froid Service) (+ Nouvelle) │
│ Équipe           (Mécanique) (Électrique) (Aucune) │
│ Téléphone        [ 06 …                  ]  │
│ ☐ Lui donner un accès à l'appli             │
│     E-mail *     [                       ]  │
│     Sites *      (Usine Nord) (Usine Sud)   │
│              [ Annuler ]   [ Ajouter ]      │
└─────────────────────────────────────────────┘
```

- Avant d'enregistrer, l'appli cherche un **membre de même nom** (sans accents, sans casse) et propose « C'est la même
  personne ? Ouvrir sa fiche » pour éviter les doublons.
- « Lui donner un accès » coché : envoie l'invitation **en reliant le compte à cette fiche** (pas de nouvelle fiche).

**Fiche membre** :

```
┌─ Youssef Amrani ────────────────────────────┐
│ Technicien · Interne · Mécanique   [Modifier]│
│ 📞 06 12 34 56 78               [ Appeler ] │
│                                             │
│ Accès à l'appli                             │
│   ○ Sans accès         [ Donner un accès ]  │
│   — ou —                                    │
│   ● Actif · y.amrani@… · Usine Nord         │
│   [Sites] [☆ Admin] [Renvoyer l'invitation] │
│   [Retirer l'accès]                         │
│                                             │
│ Habilitations                               │
│   B1V — échue le 03/10/2026 ⚠    [Modifier] │
│   [ + Habilitation ]                        │
│                                             │
│ Travaux : 2 en cours · 14 ce mois  [Voir]   │
│                                             │
│ [ Rendre inactif ] (historique conservé)    │
└─────────────────────────────────────────────┘
```

- **Donner un accès** : e-mail + sites (le rôle est déjà celui du membre). « Retirer l'accès » désactive le compte, le
  membre reste (affectations et historique intacts) et libère sa place.
- « Renvoyer l'invitation » tant que la personne ne s'est jamais connectée (statut « Invité »).
- ★ Admin, sites, rôle d'un membre avec accès : **réservés à l'administrateur** (comme au R1). Le dernier administrateur
  ne peut pas perdre son droit (inchangé).
- « Travaux » ouvre la liste filtrée sur ce membre.

## 4. Équipes

```
┌─ Équipes ───────────────────────────────────┐
│ Mécanique        chef Karim B.   4 membres  │
│ Électrique       chef Said M.    3 membres  │
│ Équipe de nuit   —               2 membres  │
│ [ + Nouvelle équipe ]                       │
└─────────────────────────────────────────────┘
```

- Une équipe : **nom, chef d'équipe (facultatif), membres**, site (facultatif ; vide = tous les sites).
- Usage dès R3 :
  - filtre **« Mon équipe »** dans Travaux (pour un membre qui a une équipe) ;
  - une intervention peut être **confiée à une équipe** (`equipeId`) avant d'avoir un intervenant : elle apparaît dans
    « Mon équipe » de chacun ; le premier qui démarre devient intervenant (comme aujourd'hui) ;
  - filtre « Équipe » dans la liste des travaux du responsable.
- Le chef d'équipe **n'a pas de droit en plus** en R3 (pas de nouveau rôle) ; la planification par équipe est le lot R9.
- Nouveau type de fiche `equipes` : `{ nom, chefId, membreIds, siteId, actif }`. Les équipes d'un membre se lisent
  depuis l'équipe (une seule source).

## 5. Sociétés prestataires

- **Une seule fiche « Société »** pour les fournisseurs et les prestataires (fiche `fournisseurs` existante, avec un
  indicateur `prestataire: true` et/ou `fournisseur: true`) : nom, contact, téléphone, e-mail, **référence et fin de
  contrat** (prestataire), remarques. Une société qui fournit des pièces **et** intervient n'est saisie qu'une fois.
- Écran « Sociétés » (Entreprise) : liste filtrée « Prestataires » / « Fournisseurs », fiche avec ses membres (pour un
  prestataire) et un repère **« contrat échu »**.
- Une intervention confiée à un prestataire porte `societeId` (en plus des intervenants).
- **Ce que voit un compte prestataire** (Q3, élargi) : les interventions où il est intervenant **et** celles confiées à
  sa société (le chef d'équipe du prestataire peut alors répartir chez lui). Rien d'autre ne change par rapport au R1
  (pas de magasin, d'achats, de prix, d'indicateurs ni de journal) ; il lit la fiche de **sa** société seulement.

## 6. Habilitations (version simple)

- Liste sur le membre : libellé libre (choix rapides : B1V, B2V, BR, H0, CACES, travail en hauteur, ATEX) + échéance
  facultative.
- Repère ⚠ « échue » sur la fiche et dans la liste des membres ; **avertissement** (pas de blocage) quand on affecte un
  intervenant dont une habilitation est échue.
- Pas de rappel par e-mail ni de lien habilitation ↔ type de travaux en R3 (plus tard, si le pilote le demande).

## 7. Qui fait quoi

| Action | Administrateur du client | Responsable (non admin) | Autres rôles |
|---|---|---|---|
| Ajouter / modifier un membre **sans accès** (nom, rôle, équipe, société, téléphone, habilitations) | ✅ | ✅ | — |
| Donner / retirer un accès, renvoyer l'invitation, changer les sites, le rôle d'un membre avec accès, ★ Admin | ✅ | — | — |
| Créer / modifier une équipe | ✅ | ✅ | — |
| Créer / modifier une société | ✅ | ✅ | Achats : sociétés fournisseurs |
| Voir la liste des membres et des équipes | ✅ | ✅ | tous (lecture, pour affecter et appeler) ; prestataire : sa société |
| Modifier son propre nom et téléphone | ✅ | ✅ | ✅ (Mon compte) |

- **Perfora (console)** n'invite que le **premier administrateur** d'une entreprise : « Inviter un responsable »
  devient « Inviter l'administrateur » (rôle au choix, ★ Admin donné d'office). Ensuite c'est l'administrateur du
  client qui invite.
- L'administrateur peut avoir n'importe quel rôle métier (ex. Direction + ★ Admin, sans gérer la maintenance).

## 8. Serveur

- `definir_profil` / `inviter` : acceptent `personne_id` (relier à une fiche existante) et mettent à jour **le nom et le
  rôle de la fiche** avec ceux du compte ; un compte sans fiche reçoit la sienne (rattrapage des comptes existants).
- `push_fiches` :
  - `personnes` : écriture réservée au responsable et à l'administrateur (sauf son propre nom / téléphone) ; **refus**
    de changer le rôle d'une fiche reliée à un compte autrement que par `definir_profil` ;
  - nouveau type `equipes` (responsable, administrateur) ;
  - `fournisseurs` avec `prestataire` : responsable, administrateur ; achats pour les fournisseurs ;
  - `ots.equipeId`, `ots.societeId` : posés par le responsable.
- `prestataire_voit` : + interventions dont `societeId` = sa société (lue sur sa fiche membre) ; + la fiche de sa
  société.
- Tests SQL `tests_membres_r3.sql` (base neuve et Supabase recette) ; serveur factice aligné.

## 9. Reprise de l'existant

- Chaque compte est relié à sa fiche (déjà le cas pour les comptes créés par l'appli) ; nom et rôle de la fiche alignés
  sur le compte, une seule fois, à l'installation du SQL R3.
- Le texte libre « Société » des fiches existantes devient une société prestataire (créée si absente, même nom sans
  accents ni casse).
- **Doublons existants** (une fiche sans accès + un compte au même nom) : signalés dans la liste (« doublon possible ») ;
  l'administrateur rend inactive l'une des deux (historique conservé). Pas de fusion automatique des interventions
  (trop risqué pour le gain).

## 10. Hors périmètre

Planification par équipe (R9) · quotas et packs (R8) · plusieurs administrateurs Perfora par client · rappels
d'habilitations · photos des membres · compétences par type d'équipement.

## 11. Mesures d'acceptation

- Une seule liste de membres ; plus de section « Personnes sans compte ».
- Ajouter un membre sans accès : **≤ 3 champs**, un écran ; donner un accès à un membre existant : **≤ 2 étapes**
  (bouton, e-mail + sites), sans créer de fiche en double.
- Un changement de rôle se voit pareil sur le compte et dans les listes d'affectation.
- Un compte prestataire voit les interventions de sa société et aucune autre ; tests d'étanchéité verts.
- Téléphone (375 × 812) : liste des membres lisible sans défilement horizontal ; fiche membre ≤ 1,5 écran.

## 12. Durée et ordre

3 – 4 jours : serveur (fiche ↔ compte, `equipes`, sociétés, périmètre prestataire) et tests → écran Membres et fiche
membre → équipes et filtre « Mon équipe » → sociétés → reprise de l'existant → recette par rôle sur téléphone.

## 13. Points à valider par Hicham

| # | Question | Proposition |
|---|---|---|
| R3-a | Société prestataire et fournisseur : **une seule fiche** « Société » ? | oui (une société qui fournit et intervient n'est saisie qu'une fois) |
| R3-b | Un compte prestataire voit-il aussi les interventions **confiées à sa société** (pas seulement les siennes) ? | oui (le chef du prestataire répartit chez lui) |
| R3-c | Le **responsable non administrateur** peut-il ajouter des membres **sans accès** et gérer les équipes ? | oui ; donner un accès reste réservé à l'administrateur |
| R3-d | Habilitations **dès R3** (liste + échéance + avertissement) ou plus tard ? | dès R3, version simple |

## 14. Fait (7 nov. 2026, v38)

- **Calculs** (`js/calculs.js`, `tests/membres_r3.test.js`) : `nomComparable` / `doublonsNom` (sans accents ni casse),
  `habilitationEchue(s)`, `equipesDe` (l'équipe est la seule source), `otConfiee` (intervenant ou société du
  prestataire), `otDeMesEquipes`. 101 tests node.
- **Serveur** `supabase/membres_r3.sql` (généré par `scripts/generer_membres_r3.py`, après `interventions_r2.sql`) :
  type `equipes` ; `ma_societe`, `ot_a_moi` élargi à la société ; `prestataire_voit` (+ sa société, + équipes) ;
  `journal_visible` aligné ; `definir_profil` ne rend plus le membre inactif quand on retire l'accès ; `relier_membre` ;
  `push_fiches` : membres et équipes réservés au responsable et à l'administrateur (chacun : son nom et son téléphone),
  rôle / désactivation d'un membre avec accès refusés par la fiche, nom d'un membre avec accès recopié sur son compte,
  société prestataire = module de base (réservée au responsable et à l'administrateur ; le magasin garde ses
  fournisseurs), `equipeId` / `societeId` d'une intervention refusés au terrain ; reprise `r3_reprise()` (fiches des
  comptes alignées, texte « societe » → société prestataire). Tests : `tests_membres_r3.sql` 21/21 sur une base neuve,
  16 fichiers de tests SQL rejoués sans écart ; serveur factice aligné (`tests/membres_r3_serveur_test.py` 19/19 ; R1,
  R2, sécurité, fichiers, énergie inchangés).
- **Appli** (`js/vues/membres.js`, nouveau) : Membres (groupés par équipe puis prestataires par société, filtres,
  recherche, places du pack), fiche membre (accès, habilitations, travaux), Ajouter un membre (doublon signalé avant
  création, accès en option), Donner un accès (envoie la fiche au serveur d'abord, invite puis relie ; un compte déjà
  présent est proposé au rattachement), Rôle / Sites / ★ Admin / Retirer et Rétablir l'accès, Équipes, Sociétés.
  `app.js` : écran Entreprise allégé (lien vers Membres, Équipes, Sociétés ; ancienne liste « Personnes sans compte »
  retirée), travaux « Mon équipe » et filtres membre / équipe / société, étape Préparer « Confiée à l'équipe / à la
  société », avertissement d'habilitation échue à l'affectation, Mon compte « Mon nom et mon téléphone », console
  « Inviter l'administrateur » (rôle au choix). Menu : « Membres et équipes » (responsable, administrateur),
  « Annuaire » en lecture pour les autres rôles. Démo locale : une équipe et une société prestataire.
- Mesures au téléphone (375 × 812) : fiche membre 1,18 écran, liste sans défilement horizontal.
- **Écarts avec la maquette** : pas de statut « Invité » (le serveur ne dit pas si la personne s'est déjà connectée) :
  le compte est « Actif » dès l'invitation, et « Renvoyer l'invitation » devient « Renvoyer un lien de connexion »
  (e-mail « première connexion ou mot de passe oublié »). Le prestataire lit toujours la liste des membres (noms des
  intervenants), comme avant R3.
