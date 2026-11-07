# Centre de contrôle Perfora (administration de la plateforme) : proposition

Statut : **validé le 6 nov. 2026** (5 choix acceptés). **CC1 fait (v26, 7 nov. 2026)** : `app.perfora.ma/console/`
(`console/index.html`, `console.js`, `calculs_console.js` testé par `tests/console.test.js`), `supabase/centre_controle.sql`
(fiches clients dans `pf_objets`, prix convenu / périodicité / remise / conditions sur `abonnements`, `pf_tarifs`) et
`tests_centre_controle.sql` (9 tests conformes). Suite : CC2 (prospects, support, communication). Prolonge la console plateforme actuelle (clients,
abonnements, démo, mise en service) et le cadrage du lancement (`CADRAGE_LANCEMENT.md` : E paiement, I parrainage,
H installation, N parcours).

## 1. Où : une page séparée, réservée à l'administrateur

**`app.perfora.ma/console/`** : page distincte de l'appli terrain, même connexion (même compte Supabase), même règles de
sécurité.
- L'appli des techniciens reste légère : le code d'administration n'est plus livré sur leurs téléphones.
- Mise en page pour **ordinateur** (tableaux larges, plusieurs colonnes), pas de mode hors ligne (données vivantes).
- Chaque action reste vérifiée par le serveur (fonctions `pf_*` réservées à l'administrateur) ; MFA conseillé sur ce
  compte (prévu au cadrage, ligne L).
- La console actuelle de l'appli renvoie vers cette page.

## 2. Les onglets

| Onglet | Contenu | Données |
|---|---|---|
| **Tableau de bord** | Clients actifs / en essai, essais qui finissent sous 7 jours, échéances sous 30 jours, factures impayées, revenu mensuel récurrent, demandes ouvertes, clients **inactifs** depuis 7 jours (risque de départ) | calculé |
| **Clients** | Liste et fiche client : identité (raison sociale, ICE, adresse de facturation, contacts), pack, sites, utilisateurs, usage (fiches, photos, dernière activité), mise en service (page existante), notes internes, historique des échanges | existe en partie |
| **Prospects** | Demandes de démo et pistes : nom, société, secteur, ville, WhatsApp, **source** (site, WhatsApp, parrainage, salon…), étape (nouveau → contacté → démo prévue → démo faite → essai → gagné / perdu + motif), **prochaine action et sa date**. Bouton « Convertir en client » (crée l'entreprise et passe à la mise en service) | nouveau |
| **Support** | Demandes des clients existants : question, anomalie, évolution, facturation ; priorité, statut (ouverte → en cours → résolue), échéance, réponse. Plus tard : bouton « Contacter le support » dans l'appli qui crée la demande | nouveau |
| **Abonnements** | Pack, statut, **prix convenu**, période (mensuel / annuel), début, prochaine échéance, remise ; actions : prolonger, changer de pack, suspendre (existe) ; **grille tarifaire** des packs ; alertes (essai fini, échéance dépassée) | complète l'existant |
| **Facturation** | **Devis**, **factures** (numérotation continue F-2026-0001, jamais modifiées une fois émises : on corrige par un **avoir**), **paiements** (virement, espèces, chèque ; Payzone plus tard), relances, impression PDF, **export pour le comptable** (CSV), **dépenses** (Supabase, Cloudflare, Resend, domaine…) pour suivre la marge | nouveau |
| **Communication** | **Modèles de messages** (bienvenue, relance d'essai, rappel d'échéance, relance de facture, parrainage) ; envoi par **lien WhatsApp pré-rempli** (tu envoies toi-même depuis ton téléphone) ou e-mail ; **journal des échanges** par client et prospect ; **annonces dans l'appli** (bandeau pour tous les utilisateurs ou un client : maintenance, nouveauté) | nouveau |

Plus tard (pas dans ce lot) : onglet « Technique » (santé des synchronisations, refus serveur par client, stockage
photos, sauvegardes, journal des actions de l'administrateur).

## 3. Règles importantes

- **Factures** : numéro unique et continu attribué par le serveur à l'émission ; une facture émise n'est jamais
  modifiée ni supprimée ; annulation par avoir. Montants en MAD. **Les mentions légales, la TVA et le modèle de facture
  sont à valider avec ton comptable** avant la première facture réelle (le statut d'auto-entrepreneur n'est pas affiché
  aux clients, comme convenu).
- **Paiement** : un abonnement passe « actif » jusqu'à la date payée ; à échéance dépassée, alerte puis lecture seule
  (règle existante) après un délai de grâce à fixer.
- **Données personnelles des prospects** (noms, téléphones) : traitement de prospection à inclure dans la déclaration
  CNDP ; pas d'envoi en masse ; suppression à la demande.
- **Communication** : pas d'API WhatsApp Business au départ (coût, validation Meta) : liens `wa.me` pré-remplis, envoyés
  par toi. E-mails automatiques (relances) plus tard via Resend, avec une fonction serveur (la clé reste côté serveur).
- **Séparation** : rien de ces données n'est visible des clients, sauf les annonces qui leur sont destinées.

## 4. Serveur

Tables de plateforme (règles d'accès actives, aucune lecture directe ; accès par fonctions `pf_*` réservées à
l'administrateur) :
- `pf_objets` (prospects, demandes de support, échanges, modèles de messages, dépenses, notes) : `type`, `entreprise_id`
  facultatif, `data` jsonb, dates — souple, comme les fiches de l'appli ;
- `pf_factures` (devis, factures, avoirs) : numéro unique attribué par le serveur, lignes, totaux, statut, immuable une
  fois émise ; `pf_paiements` ;
- colonnes ajoutées aux abonnements : prix convenu, périodicité, prochaine échéance ; `pf_tarifs` (prix par pack) ;
- `pf_annonces` : lisibles par les utilisateurs concernés via une fonction dédiée (bandeau dans l'appli).

## 5. Étapes

| Étape | Contenu | Vérification |
|---|---|---|
| CC1 | Page `console/` à onglets ; **Tableau de bord**, **Clients** (reprise de la console + fiche client), **Abonnements** (prix, échéances, alertes, grille) | Tests SQL + navigateur |
| CC2 | **Prospects** (avec conversion en client), **Support**, **Communication** (modèles, liens WhatsApp, journal, annonces dans l'appli) | Tests SQL + navigateur |
| CC3 | **Facturation** (devis, factures, avoirs, paiements, relances, PDF, export comptable, dépenses) — après validation du modèle par ton comptable | Tests SQL (numérotation, immuabilité) |
| CC4 | Payzone : lien de paiement → confirmation → paiement enregistré → abonnement prolongé (après contrat Payzone) | Mode test Payzone |

## 6. Questions à valider

1. **Page séparée `app.perfora.ma/console/`** (recommandé) plutôt que des onglets dans l'appli terrain ?
2. « Demandes clients » = **prospects** (demandes de démo) **et support** (clients existants) : les deux ?
3. Facturation : **par entreprise**, prix **par mois ou par an** selon le contrat, en MAD — et modèle de facture validé
   avec ton comptable avant CC3 ?
4. Communication : **liens WhatsApp envoyés par toi** au départ (pas d'envoi automatique) ?
5. Ordre CC1 → CC2 → CC3, ou la facturation plus tôt si un premier client signe bientôt ?
