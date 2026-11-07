# Audit de stabilité du modèle de données — risques et actions (7 nov. 2026, v38)

Demande de Hicham : stabiliser avant de reprendre les lots restants (R5, R4, R9, R8). Périmètre : la façon dont les
données sont rangées, envoyées, fusionnées et relues, sur le serveur (Supabase) et sur les téléphones (hors ligne).
Les écrans et le métier sont hors périmètre (voir docs/AUDIT_UX_MODELE_DONNEES.md).

## 1. En bref

Le socle est sain : rien n'est jamais supprimé, chaque changement est tracé, le serveur contrôle chaque envoi (droits,
entreprise, site, règles métier) et plusieurs centaines de vérifications automatiques (SQL, serveur factice, calculs) le contrôlent. **Mais quatre risques élevés sont à traiter
avant le pilote**, dont un **démontré aujourd'hui** :

1. **Deux personnes qui modifient la même liste en même temps (intervenants, pièces, réserves…) : la deuxième efface
   la première, sans message.** Essai fait : deux intervenants ajoutés hors ligne → un seul reste.
2. **Des fiches peuvent ne jamais arriver sur un téléphone** après une évolution (nouveau type de fiche, droits de
   lecture élargis) : c'est le cas **dès maintenant** pour les équipes et les interventions confiées à une société (R3).
3. **Pas encore de sauvegarde hors de Supabase** (préparatif A1 en attente) et le projet est sur l'offre gratuite
   (pas de sauvegarde téléchargeable, mise en pause après une semaine sans activité).
4. **Aucune version minimale de l'appli** : un téléphone resté sur une vieille version peut écrire des données à
   l'ancienne forme sans limite de durée.

Proposition : un **lot de stabilisation S1 (≈ 1,5 jour)** tout de suite, puis **S2 (≈ 3 jours)** avant le pilote ;
S3 se fait avec la mise en production. Détail §5.

## 2. Le modèle en 6 lignes

- Une seule table `fiches` : `id` (texte, unique pour toute la base), `type` (20 types), `data` (JSON libre),
  `entreprise_id`, `site_id`, `seq` (numéro de changement), `auteur`, `recu_le`.
- Le téléphone garde **tout** en local (IndexedDB) et l'affiche depuis la mémoire ; il envoie des **patchs** (seulement
  les champs modifiés) par lots de 100 à `push_fiches`, qui contrôle puis fusionne : `data = data || patch`.
- Il relit ce qui a changé depuis son dernier `seq` (avec 200 numéros de recouvrement) ; ses modifications pas encore
  envoyées restent prioritaires sur ce qui arrive.
- Chaque champ modifié produit une ligne de **journal** (ancienne et nouvelle valeur, auteur, date, motif).
- Pas de suppression : on annule, on clôture, on rend inactif. Mouvements de stock, relevés et journal ne se modifient
  jamais (on corrige par une nouvelle fiche).
- Références lisibles par appareil : `OT-K3-0007` (code appareil de 2 caractères + compteur local).

## 3. Ce qui est solide (à garder)

- **Traçabilité complète** et pas de suppression : on peut toujours reconstituer qui a fait quoi.
- **Le serveur est l'autorité** : écriture uniquement par `push_fiches`, refus fiche par fiche avec un motif clair,
  version serveur rétablie sur le téléphone en cas de refus, texte saisi montré à l'utilisateur.
- **Étanchéité entre entreprises et sites** : règles de lecture et d'écriture testées (tests d'étanchéité, R1, R3).
- **Construction reproductible** de la base (séquence unique, empreinte comparée à la recette) et tests SQL rejoués
  sur une base neuve à chaque lot.
- **Hors ligne éprouvé** (coupures, réponses perdues, renvois identiques acceptés sans doublon).
- Évolutions jusqu'ici **sans migration lourde** grâce au JSON (R2 a même converti les anciennes saisies).

## 4. Risques

Gravité = probabilité × impact, notée pour un pilote de 10 à 30 utilisateurs.

| # | Risque | Gravité | Preuve |
|---|---|---|---|
| A | Liste écrasée en modification simultanée | 🔴 élevée | **démontré** (serveur factice) |
| B | Fiches jamais reçues après une évolution | 🔴 élevée | lecture du code ; cas réel pour R3 |
| C | Pas de sauvegarde hors Supabase ; offre gratuite | 🔴 élevée | préparatif A1 non fait |
| D | Vieilles versions de l'appli sans limite | 🔴 élevée | aucun contrôle de version au serveur |
| E | Fiches manquées pendant un gros envoi (import) | 🟠 moyenne | théorique, à prouver |
| F | Références lisibles en double (`OT-K3-0007`) | 🟠 moyenne | calcul : 35 % de risque à 30 appareils |
| G | Contenu des fiches non vérifié par le serveur | 🟠 moyenne | un écran a déjà planté sur une fiche incomplète (R1) |
| H | Règles recopiées à la main en ~10 endroits | 🟠 moyenne | 6 générations de `push_fiches`, serveur factice manuel |
| I | Croissance des données sur le téléphone | 🟠 moyenne (12 – 24 mois) | estimation |
| J | Heures sans fuseau, horloge du téléphone | 🟡 faible à moyenne | lecture du code |
| K | Liens entre fiches peu vérifiés | 🟡 faible | seul l'équipement est vérifié |
| L | Données personnelles non effaçables | 🟡 faible (contrats) | choix « rien n'est supprimé » |

### A. Liste écrasée en modification simultanée — 🔴 démontré

- **Cause** : la fusion du serveur est faite **champ par champ** ; une liste (`intervenants`, `pieces`, `reserves`,
  `activites`, `suites`, `demandeIds`, `habilitations`, `membreIds`) est un seul champ : la dernière version reçue
  remplace l'autre en entier.
- **Essai** (7 nov.) : intervention sans intervenant ; le technicien ajoute « tech3 » hors ligne, le responsable ajoute
  « test » ; les deux envois sont acceptés ; résultat : `[test]`. Le technicien disparaît de sa propre intervention, sur
  le serveur puis sur son téléphone à la synchronisation suivante. Personne n'est prévenu.
- **Situations réelles** : technicien et responsable sur la même intervention (pièces, réserves) ; deux techniciens en
  binôme ; préparation au bureau pendant que le terrain travaille hors ligne.
- **Action** : fusion **élément par élément** sur le serveur pour les listes d'objets qui ont un `id` (intervenants,
  pièces, réserves, suites, habilitations) : on garde les éléments des deux côtés, et pour un même élément le dernier
  arrivé gagne. L'appli ne retire déjà jamais un élément (elle pose `fin` ou `annulee`), donc rien n'est perdu. Pour les
  listes simples (`activites`, `demandeIds`, `membreIds`) : envoi « ajouté / retiré » au lieu de la liste complète.
  Même règle dans le serveur factice ; tests de concurrence ajoutés. **≈ 0,5 – 1 jour.**

### B. Fiches jamais reçues après une évolution — 🔴 élevée

- **Cause 1, type inconnu** : un téléphone encore sur une ancienne version ignore les fiches d'un type qu'il ne connaît
  pas (`equipes` pour une v37) **mais avance quand même son curseur** : après la mise à jour, ces fiches ne sont jamais
  redemandées.
- **Cause 2, droits élargis** : quand une règle de lecture s'élargit, des fiches **anciennes** deviennent visibles,
  mais avec un `seq` déjà dépassé. R3 en crée deux cas : un prestataire qui voit désormais les interventions confiées à
  sa société, et un prestataire rattaché à une société après coup.
- Le mécanisme existe déjà pour R1 (« périmètre », une relecture complète si rien n'est en attente), mais n'a pas été
  relevé pour R3.
- **Actions** : (1) passer le périmètre à `r3` dans la v39 (une relecture complète, une fois) ; (2) garder sur le
  téléphone les fiches de type inconnu au lieu de les ignorer, et les appliquer après la mise à jour ; (3) règle
  d'équipe : **tout nouveau type ou toute lecture élargie = nouveau périmètre**, vérifié par une case dans la liste de
  contrôle de chaque lot. **≈ 0,5 jour.**

### C. Sauvegarde hors Supabase et offre gratuite — 🔴 élevée

- La sauvegarde de nuit chiffrée vers un dépôt GitHub privé est prête et testée en local, mais **pas encore activée**
  (A1 : dépôt privé et 4 secrets, côté Hicham).
- Offre gratuite Supabase : pas de sauvegarde téléchargeable ni de retour à un instant passé ; **projet mis en pause
  après 7 jours sans activité** ; limites de taille. Acceptable pour la recette, pas pour un client payant.
- **Actions** : A1 dès que possible (20 min, Hicham), puis test de restauration réelle ; **décision** : projet de
  production en offre Pro (≈ 25 $ / mois : sauvegardes quotidiennes, pas de pause) au plus tard au premier client
  payant. Sans Pro, la sauvegarde de nuit A1 devient la seule protection.

### D. Vieilles versions de l'appli sans limite — 🔴 élevée

- L'appli se met à jour à l'ouverture, mais un téléphone peut rester des semaines sur une version en cache (appli jamais
  rechargée, onglet resté ouvert). Le serveur ne sait pas quelle version lui écrit.
- R2 a contourné le problème pour la qualification (conversion côté serveur). Chaque lot futur (R5 stock ↔ achats, R4
  arrêts) en aura besoin.
- **Action** : l'appli envoie sa version avec chaque lot ; le serveur refuse en dessous d'une **version minimale**
  (réglable sans redéployer), avec le message « Mettez à jour l'appli : rechargez la page » ; l'appli recharge d'elle-même
  si rien n'est en saisie. Les saisies restent en attente sur le téléphone, rien n'est perdu. **≈ 0,5 jour.**

### E. Fiches manquées pendant un gros envoi — 🟠 à prouver

- Le `seq` est attribué au moment de l'écriture mais devient visible à la **fin** de la transaction. Pendant un import
  de plusieurs milliers de lignes (reprise d'un client), d'autres envois plus récents peuvent être lus avant ; si
  l'écart dépasse 200 numéros, les lignes de l'import sont sautées par les téléphones déjà passés.
- **Action** : reproduire sur la base locale (import long + envois en parallèle) ; si confirmé, le serveur renvoie un
  « curseur sûr » (le plus petit `seq` d'une transaction encore en cours). **≈ 0,5 jour avec l'essai.**

### F. Références lisibles en double — 🟠 moyenne

- Le code appareil fait 2 caractères (1 024 combinaisons) et est tiré au hasard : avec 30 appareils dans une
  entreprise, **≈ 35 %** de chances que deux appareils partagent un code (≈ 60 % à 45). Après « Effacer cet appareil »,
  un nouveau code est tiré et son compteur repart à 1.
- Pas de perte de données (l'identifiant interne reste unique), mais deux `OT-K3-0007` différents sur le terrain, dans
  un rapport ou au téléphone = confusion.
- **Action** : code appareil attribué par le serveur, unique dans l'entreprise, conservé à l'effacement (lié au
  compte et à l'appareil). Les références existantes ne changent pas. **≈ 0,5 jour.**

### G. Contenu des fiches non vérifié — 🟠 moyenne

- Le serveur vérifie les droits et des règles métier, pas la forme : un statut inconnu, une quantité en texte ou une
  date mal formée passent. Une erreur d'une version de l'appli (ou d'un import) peut donc s'installer durablement, et un
  écran peut planter dessus (c'est arrivé au R1 avec une fiche sans date de création ; corrigé côté appli).
- **Actions** : contrôle léger au serveur des champs clés (statut, nature, priorité, quantités, dates au bon format,
  références obligatoires) ; **rapport nocturne « fiches anormales »** dans la console ; l'appli continue de lire de
  façon tolérante. **≈ 1 jour.**

### H. Règles recopiées à la main — 🟠 moyenne (maintenance)

- La liste des types est écrite dans ~10 endroits (contrainte SQL, `push_fiches`, module, droits d'écriture, fiches
  communes / par site, stockage du téléphone, serveur factice, import Excel…).
- `push_fiches` a été réécrite par 6 générations successives de scripts qui reprennent le texte de la précédente :
  modifier un ancien fichier n'a aucun effet, et chaque lot allonge la fonction (≈ 250 lignes).
- Le serveur factice est une copie manuelle des règles : un écart ne se voit que si un test le couvre.
- **Actions** : (1) un fichier unique `modele.json` (types, module, commun / par site, qui écrit) d'où sont générés le
  SQL, le stockage du téléphone et le serveur factice ; (2) `push_fiches` regroupée dans **un seul fichier** source
  maintenu à la main, avec ses règles par type ; (3) des **scénarios de test communs** (JSON) joués à la fois sur
  Postgres et sur le serveur factice. **≈ 1,5 – 2 jours.**

### I. Croissance des données sur le téléphone — 🟠 dans 12 à 24 mois (estimation)

- Tout est chargé en mémoire au démarrage, journal compris ; chaque champ modifié = une ligne de journal.
- Ordre de grandeur pour un site de 10 techniciens (≈ 300 interventions par mois, ≈ 40 changements chacune) : ≈ 12 000
  lignes de journal par mois, **≈ 150 000 par an**, soit plusieurs dizaines de Mo sur un téléphone et ~1 500 requêtes
  pour une relecture complète. La recette actuelle (257 fiches, 552 ko) ne permet pas de mesurer.
- **Actions** : jeu d'essai de 100 000 fiches et mesure sur un Android d'entrée de gamme (démarrage, mémoire,
  relecture complète, règles de lecture du serveur) ; ensuite, ne plus charger le journal au démarrage (lu par fiche, à
  la demande) et archiver ce qui est clôturé depuis plus de 12 mois. **≈ 1 jour pour la mesure ; le reste selon le
  résultat.**

### J. Heures sans fuseau, horloge du téléphone — 🟡

- Les dates sont l'heure locale du téléphone, sans fuseau (`2026-11-07T08:15`). Le Maroc change d'heure pendant le
  Ramadan (GMT+1 → GMT) : un arrêt à cheval sur le changement est faux d'une heure ; un téléphone mal réglé date mal ses
  saisies (MTBF / MTTR du lot R4 concernés).
- **Actions** : à chaque synchronisation, comparer l'horloge du téléphone à celle du serveur et avertir au-delà de
  5 minutes ; enregistrer le décalage horaire avec les heures d'arrêt (utile pour R4). **≈ 0,5 jour.**

### K. Liens entre fiches peu vérifiés — 🟡

- Seul l'équipement d'une demande / intervention / programme est vérifié à la création. Intervention d'un besoin,
  article d'un mouvement, intervenant, équipe, société : non vérifiés. Comme rien n'est supprimé, un lien cassé vient
  surtout d'une fiche refusée ou créée hors ligne sur un autre site.
- **Action** : étendre la vérification aux liens principaux et ajouter les liens cassés au rapport nocturne (G).
  **≈ 0,5 jour.**

### L. Données personnelles non effaçables — 🟡

- Nom, téléphone et habilitations des membres ne peuvent pas être effacés (choix « rien n'est supprimé »). La loi
  09-08 (CNDP) et les contrats clients demanderont de pouvoir le faire pour une personne partie.
- **Action** : fonction d'**anonymisation** d'un membre (nom remplacé par « Ancien membre n », téléphone et
  habilitations retirés, historique conservé). **≈ 0,5 jour, avant le premier contrat.**

## 5. Plan d'actions proposé

| Lot | Contenu | Durée | Quand |
|---|---|---|---|
| ✅ **S1 — urgent** (v39) | A fusion des listes · B périmètre `r3` + fiches de type inconnu gardées · D version minimale | ≈ 1,5 jour (v39) | **maintenant**, avant de reprendre R5 |
| **S2 — avant le pilote** | E essai et curseur sûr · F code appareil unique · G contrôle du contenu + rapport nocturne · K liens · H source unique des types, `push_fiches` en un fichier, scénarios communs | ≈ 3 – 4 jours | après S1, avant ou entre R5 et R4 |
| **S3 — avec la production** | C sauvegarde activée et restauration testée, offre Pro · I mesure à 100 000 fiches · J horloge et fuseau · L anonymisation | ≈ 2 jours (+ A1 côté Hicham) | étape B (production) et avant le premier contrat |

Côté Hicham, sans attendre : **A1** (dépôt privé des sauvegardes et ses 4 secrets) et la décision sur l'offre de la
production.

Ordre conseillé ensuite : S1 → R5 → S2 → R4 → R9 → R8. S2 avant R4, car R4 (MTBF, MTTR) dépend de données d'arrêt
justes, et donc de A, E et J.

## 6. À chaque lot, désormais (liste de contrôle)

- Nouveau type ou lecture élargie ? → nouveau périmètre (relecture complète une fois).
- Forme d'un champ changée ? → version minimale relevée, ou conversion côté serveur.
- Nouvelle liste dans une fiche ? → éléments avec `id`, jamais retirés (fin / annulée), fusion élément par élément.
- Nouvelle règle serveur ? → même scénario joué sur Postgres et sur le serveur factice.

## 7. Fait — lot S1 (7 nov. 2026, v39)

- **A, listes** : l'appareil décrit ses changements de liste (`$listes` : clés ajoutées ou modifiées, clés retirées ;
  `Calculs.decrireListe`) ; le serveur (`s1_fusion_listes`, `supabase/stabilite_s1.sql`), le serveur factice et
  l'affichage local (`Calculs.fusionPatch` dans `Store.appliquerDistant`) appliquent la même fusion. Toute liste dont
  les éléments ont un `id` ou sont de simples valeurs est concernée (intervenants, pièces, réserves, suites, lignes
  d'achat, habilitations, activités, demandes liées, membres d'équipe…) ; les autres restent remplacées. Une ancienne
  appli (liste complète sans description) n'ajoute que ses éléments et ne retire rien.
- **B, fiches jamais reçues** : périmètre `r3` (une relecture complète, une fois, si rien n'est en attente) ; les
  fiches d'un type inconnu sont gardées sur l'appareil (`meta.inconnus`) et appliquées après la mise à jour.
- **D, version minimale** : `push_fiches(lot, version)` ; réglage `pf_reglages.version_minimale` (« v0 » = pas de
  contrôle) ; refus de tout le lot pour une version plus ancienne, appel par l'API seulement ; l'appli se recharge une
  fois (jamais en pleine saisie) puis affiche « Mise à jour obligatoire » ; les saisies restent en attente.
- **Essais** : `tests_stabilite_s1.sql` 13/13 sur une base neuve, 17 fichiers de tests SQL rejoués avec les mêmes
  résultats qu'avant S1 ; serveur factice `tests/stabilite_s1_serveur_test.py` 10/10 (R3 19, R2 11, R1 15, sécurité 14,
  fichiers 13, énergie 36 inchangés) ; 107 tests node. Navigateur (deux comptes, appli v39) : deux intervenants ajoutés
  en même temps → les deux restent ; réserve retirée d'un côté pendant un ajout de l'autre → retrait et ajout gardés ;
  version minimale v40 → rechargement puis bandeau, saisie gardée puis envoyée au retour à v0.
- **Mise en service** (ordre obligatoire) : 1) `stabilite_s1.sql` sur Supabase (version minimale « v0 ») ; 2) appli
  v39 en ligne ; 3) `update public.pf_reglages set valeur = 'v39' where cle = 'version_minimale';` pour fermer la porte
  aux v38 et plus anciennes (elles ne décrivent pas leurs retraits).
- Rejouer seul un ancien fichier SQL (avant `stabilite_s1.sql`) recréerait `push_fiches(jsonb)` à côté de la nouvelle :
  toujours rejouer la séquence complète, ou `stabilite_s1.sql` à la suite.
