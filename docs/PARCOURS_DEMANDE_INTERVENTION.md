# Parcours demande → intervention : état actuel et simplifications proposées

Statut : **validé et fait le 6 nov. 2026 (v23)**, sauf l'option « clôture validée par le responsable », qui demande un
réglage par entreprise côté serveur : elle sera faite avec D2.

## 1. À quoi sert chaque fiche

- **Demande** : un **fait constaté** (« le vérin ne tient plus »). N'importe qui la crée avec « Signaler ». Elle répond à
  « que s'est-il passé, sur quel équipement, quel impact ? ». Elle peut finir sans travail (doublon, rien constaté).
- **Intervention (OT)** : le **travail** fait pour y répondre : qui, quoi, pièces, arrêt, cause, résultat. Une demande peut
  donner plusieurs interventions, et une intervention peut exister sans demande (préventif, travaux).

Les séparer reste utile (V3) : on compte les faits d'un côté, le travail de l'autre, et une demande classée sans travail
ne pollue pas les indicateurs de travaux.

## 2. Parcours actuel

| Étape | Qui | Clics |
|---|---|---|
| Signaler (équipement, état, besoin, constat) | tous | formulaire |
| Demande « À examiner » → **Je prends en charge** | technicien, responsable | 1 |
| **Créer l'intervention** → fenêtre « Je démarre maintenant » à cocher → Créer | technicien, responsable | 3 |
| Intervention : **Démarrer** (si pas coché) | technicien | 1 |
| Remplir la fiche (longue page : arrêt, travaux, résultat, cause, pièces…) | technicien | défilement |
| **Travail terminé** puis **Clôturer** | technicien | 2 |

Raccourci déjà présent : dans « Signaler », la case « Je prends en charge et j'interviens maintenant » crée la demande et
l'intervention démarrée en une fois. Mais il est peu visible, et la page de la demande n'en a pas l'équivalent.

Points faibles constatés :
1. **4 clics** entre la demande et l'intervention démarrée (prendre en charge, créer, cocher, valider).
2. **« Planifier »** enregistre un créneau mais l'intervention reste « À planifier » : statut trompeur. Le statut
   « À préparer » n'est jamais atteint (« Prête » sert : l'attente de pièces est levée, on peut reprendre).
3. **Fin de travail en 2 boutons** (« Travail terminé » puis « Clôturer ») et les champs exigés à la clôture (résultat,
   travaux…) sont dispersés dans une longue page : le technicien découvre ce qui manque au moment de clôturer.
4. **Bouton « Signaler » partout** (sauf sur le formulaire lui-même et pour le pilote) : il couvre le bas des pages de
   détail, des réglages, du magasin, et fait doublon avec « Signaler sur cet équipement » sur la fiche équipement.

## 3. Simplifications proposées

**A. Page de la demande : deux boutons directs au lieu de quatre clics**
- **« J'interviens maintenant »** (1 clic) : prise en charge + intervention démarrée à mon nom, ouverte directement.
- **« Planifier une intervention »** : petite fenêtre (créneau et intervenant, facultatifs) → intervention « Planifiée ».
- « Je m'en occupe » (prise en charge sans intervention) et « Classer sans travail » restent en boutons secondaires.

**B. Statuts d'intervention plus clairs**
À planifier → **Planifiée** (créneau connu) → En cours ⇄ En attente → Prête (attente levée) → En cours → Clôturée
(ou Annulée). « Planifier » fait passer à « Planifiée ». « À préparer », jamais utilisé, est retiré (une fiche ancienne
dans cet état est lue comme « À planifier »).

**C. Fin de travail en une fenêtre**
Un seul bouton **« Terminer »** ouvre une fenêtre courte avec ce qu'il faut pour clôturer : ce qui a été fait, résultat,
cause si connue, fin d'arrêt si arrêt, pièces encore en main. Si tout est rempli → clôturée en un clic. Option par
entreprise : « clôture validée par le responsable » → le technicien termine, le responsable voit « À valider » et clôture.

**D. Bouton « Signaler » seulement là où il sert**
Visible sur : Accueil, Demandes, Travaux (liste), Parc (liste). Masqué sur : les pages de détail (demande, intervention,
équipement, qui a déjà « Signaler sur cet équipement »), magasin, achats, indicateurs, journal, réglages, QR, plateforme,
et pour le pilote. Les autres rôles (magasinier, achats, exploitation) le gardent sur leur accueil.

## 4. Effet attendu

| Cas | Avant | Après |
|---|---|---|
| Panne vue par le technicien qui intervient | Signaler + case à cocher (peu visible) | Signaler + « J'interviens maintenant » bien visible |
| Demande d'un opérateur, prise par un technicien | 4 clics | 1 clic |
| Fin d'intervention | défilement + 2 boutons, oublis découverts à la clôture | 1 fenêtre, 1 bouton |

Travail estimé : une étape courte (appli seulement, aucune modification du serveur), testée sur la recette existante et
sur deux appareils. À placer avant D3, pour que les écrans d'énergie suivent les mêmes règles.
