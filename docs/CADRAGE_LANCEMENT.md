# Perfora — cadrage du lancement (domaine, hébergement, conformité, paiement, offre, parcours)

Version du 6 nov. 2026. Document de travail : les lignes « Décision » attendent ton arbitrage ; le reste est
une proposition. Les prix et conditions des fournisseurs sont à revérifier au moment de souscrire.

## 0. Décisions prises

- 6 nov. 2026 : **Cloudflare Pages** pour l'appli et le site ; **zone DNS de perfora.ma chez Cloudflare** (domaine
  toujours enregistré chez Nindohost). Ancien hébergement inconnu : sans effet une fois les DNS chez Cloudflare.
  Mise en œuvre : [`MISE_EN_LIGNE_PERFORA_MA.md`](MISE_EN_LIGNE_PERFORA_MA.md). Site de présentation v1 : dépôt séparé `perfora-site`.
- 6 nov. 2026 : **pas de société pour l'instant, statut d'auto-entrepreneur** (identifiants fiscaux disponibles) ;
  Payzone accepte ce statut (vérifié par Hicham). Contact public : WhatsApp +212 680 03 28 88 (bouton « Demander une
  démo » du site). À confirmer avec un comptable : plafond annuel de chiffre d'affaires du statut pour des prestations
  de services, retenue à la source au-delà d'un certain montant facturé à un même client, mentions obligatoires sur les
  factures, et seuil à partir duquel créer une société (SARL / SARL AU) ; le contrat client et la déclaration CNDP se
  font au nom de l'éditeur personne physique.

## 1. Recommandations en bref

1. **perfora.ma** = site de présentation ; **app.perfora.ma** = l'application. Domaine et DNS restent chez Nindohost.
2. **Garder Supabase** pour le serveur (connexion, invitations, règles d'accès, ~60 tests déjà validés). Neon n'apporte
   que la base : il faudrait reconstruire connexion, API, invitations et règles (3 à 4 semaines, nouveaux risques).
3. **Hébergement des pages : Cloudflare Pages** (gratuit, usage commercial annoncé comme autorisé, bande passante
   illimitée). **Vercel Hobby est réservé à l'usage non commercial** : Vercel n'est envisageable qu'en offre Pro (payante).
4. **Gratuit au début, payant au premier client** : Supabase gratuit tant qu'il n'y a que de la démo ; **Supabase Pro**
   (sauvegardes quotidiennes, pas de mise en pause) dès le premier site pilote avec de vraies données.
5. **CNDP avant toute donnée réelle** : déclaration des traitements + transfert vers l'Union européenne (Frankfurt),
   contrat de sous-traitance avec chaque client. À faire valider par un juriste ou un consultant 09-08.
6. **Paiement en 2 temps** : facture + virement au départ (usage B2B au Maroc), puis **Payzone** (lien de paiement,
   puis prélèvement récurrent si la tokenisation est confirmée par Payzone).
7. **Invitations par WhatsApp** (lien à usage unique) en plus de l'e-mail : plus naturel pour les équipes et règle le
   problème des e-mails en indésirables.
8. **Préréglages par secteur** + import Excel pour installer un client en une demi-journée.

## 2. Grille de cadrage

| # | Chantier | Objectif | Options et recommandation | Décision attendue (toi) | Actions | Qui | Phase |
|---|---|---|---|---|---|---|---|
| A | **Domaine perfora.ma** (Nindohost) | Adresse pro, QR codes durables | DNS chez Nindohost : `perfora.ma` + `www` → site ; `app.perfora.ma` → appli ; e-mails `contact@`, `no-reply@` | Quel ancien dépôt / hébergement utilise le domaine aujourd'hui | Détacher le domaine de l'ancien dépôt ; enregistrements DNS ; HTTPS ; adresse publique de l'appli et « Site URL » Supabase sur app.perfora.ma ; SPF / DKIM / DMARC | toi (accès Nindohost) + moi | 1 |
| B | **Hébergement des pages** (appli + site) | Gratuit au départ, autorisé en commercial | Cloudflare Pages (recommandé) · Vercel Pro (~20 $/mois/membre) · GitHub Pages (démo seulement) | Cloudflare ou Vercel Pro | Compte Cloudflare, liaison au dépôt, domaine, déploiement automatique à chaque version | toi (compte) + moi | 1 |
| C | **Serveur de production** | Données clients séparées des essais, sauvegardées | Supabase Pro (recommandé, ~25 $/mois) · Supabase gratuit (pause après 7 jours d'inactivité, pas de sauvegarde : démo seulement) · Neon (reconstruction lourde, déconseillé) | Date de passage en Pro (au plus tard au 1er pilote) | Nouveau projet « production » (région UE), scripts SQL numérotés rejoués, l'actuel devient « recette » ; photos dans Storage ; export quotidien de secours | toi (paiement) + moi | 2 |
| D | **CNDP (loi 09-08)** | Conformité avant données réelles | Hébergement UE = transfert à l'étranger à notifier / autoriser ; alternative hébergement au Maroc (sans Supabase géré, beaucoup plus lourd) | Juriste ou consultant 09-08 ; hébergement UE confirmé | Inventaire des données (noms, e-mails, rôles, signatures, photos — pas de RH), déclaration des traitements de Perfora, demande de transfert, contrat de sous-traitance client, politique de confidentialité, mentions, durées de conservation, procédure d'incident | toi (dépôt, juriste) + moi (inventaire, textes techniques) | 3 |
| E | **Paiement Payzone** | Encaisser les abonnements | Étape 1 : facture + virement, activation dans la console (existe) · Étape 2 : lien de paiement Payzone · Étape 3 : récurrent (tokenisation annoncée, à confirmer) | Structure juridique (RC, ICE, IF), compte bancaire pro, contrat Payzone | Grille tarifaire, CGV, factures ; webhook Payzone → fonction serveur → abonnement actif / échéance ; jamais de numéro de carte chez nous | toi (contrat) + moi (intégration) | 3 → 5 |
| F | **Packs et prix** | Offre lisible, montée en gamme naturelle | Voir §4 (hypothèse de départ à discuter) | Prix, unité de facturation (site / mois), essai gratuit, options | Tableau final, page tarifs, limites dans la base (packs existent déjà) | toi + moi | 0 |
| G | **Site de présentation (branding)** | Convaincre un directeur en 2 minutes | Une page : promesse, 3 promesses terrain, modules, packs, vidéo, preuve (pilote), FAQ (CNDP, hors ligne), contact WhatsApp | Logo, couleurs, ton, photos réelles d'usine ? | Maquette, textes, mentions légales, formulaire « demander une démo » + bouton WhatsApp | toi (contenu, logo) + moi | 1 |
| H | **Préréglages et installation client** | Client opérationnel en une demi-journée | Questionnaire d'installation + préréglages par secteur + import Excel (volet F) | Secteurs prioritaires (agroalimentaire, plasturgie, carrières, textile, utilités…) | Assistant « nouveau client » dans la console (entreprise, pack, sites, préréglage, invitation) ; classeur modèle ; check-list J1 / J7 / J30 | moi + toi (connaissance secteur) | 3 |
| I | **Bouche-à-oreille WhatsApp** | Recommandation entre directeurs | Lien de partage pré-rempli + code de parrainage ; récompense (ex. 1 mois offert) ; pas d'envoi en masse | Récompense de parrainage | « Recommander Perfora » dans l'appli (lien wa.me), suivi de la source des demandes, page démo | moi + toi | 4 |
| J | **Rôles** | Chacun voit et fait ce qui le concerne | 7 rôles existants + administrateur plateforme ; à ajouter : responsable de site (délégation), direction multi-sites (élargir « pilote »), prestataire limité à ses interventions, auditeur en lecture | Rôles manquants pour tes clients cibles | Matrice rôle × action publiée (déjà dans `DROITS` et `push_fiches`) | moi + toi | 2 |
| K | **Vues et tableaux de bord** | Une page d'accueil par métier | Technicien (mes travaux), responsable (aujourd'hui + indicateurs site), magasinier, achats (existent) ; **direction** multi-sites et **plateforme** (clients, usage, revenus) à créer | Les 5 à 7 chiffres que veut voir un directeur | Volet E allégé : disponibilité, arrêts, préventif à l'échéance, pannes répétitives, valeur du stock, coût des pièces ; rapport mensuel PDF | moi | 4 |
| L | **Sécurité** | Prêt pour un audit client | Déjà fait : règles d'accès par entreprise / site / rôle, prix masqués, tests d'étanchéité, clé secrète côté serveur | Niveau d'exigence (MFA obligatoire pour qui ?) | MFA pour administrateur et responsables, sessions limitées, sauvegardes + test de restauration, séparation recette / production, revue des droits avant chaque client, petit test d'intrusion avant le 1er contrat | moi | 2 |
| M | **Authentification** | Connexion simple et sûre | Actuel : e-mail + mot de passe, lien magique, invitation. À ajouter : invitation par lien WhatsApp, e-mails via service dédié (Brevo / Resend) depuis no-reply@perfora.ma, MFA, plus tard Google / Microsoft pour le pack Entreprise | SSO utile pour tes cibles ? | Service d'e-mails, invitations par lien, MFA | toi (compte e-mail) + moi | 2 |
| N | **Parcours** | Aucune étape floue, du prospect au départ | Prospect → démo → essai ; installation client ; usage par rôle (V3) ; facturation (essai → facture → paiement → renouvellement → lecture seule) ; support ; départ (export des données) | Durée d'essai, délai avant lecture seule | Schéma des parcours, messages et e-mails associés, export de réversibilité | moi + toi | 3 |

## 3. Planning proposé (en semaines, à partir de ta validation)

| Phase | Semaines | Contenu | Livrable | Condition |
|---|---|---|---|---|
| 0 · Décisions | S1 | Packs et prix, hébergement, juriste CNDP, structure juridique, accès Nindohost | Tableau des décisions rempli | — |
| 1 · Présence | S1 – S2 | Domaine (A), hébergement Cloudflare (B), site de présentation v1 (G), e-mails pro + service d'envoi (M) | perfora.ma et app.perfora.ma en ligne | Accès Nindohost |
| 2 · Production | S2 – S4 | Projet Supabase production (C), photos en Storage, MFA, sauvegardes, invitations WhatsApp, rôles complétés (J, L, M) | Environnement prêt pour un pilote | Supabase Pro souscrit |
| 3 · Conformité et offre | S3 – S6 | Dossier CNDP déposé (D), CGU / CGV / confidentialité / contrat de sous-traitance, assistant « nouveau client » + préréglages (H), parcours (N), facturation manuelle (E1) | Dossier déposé, contrat type, installation en ½ journée | Juriste |
| 4 · Pilote | S5 – S10 | Pilote 4 à 6 semaines sur un site, tableau de bord direction (K), parrainage WhatsApp (I) | Indicateurs avant / après, premier témoignage | CNDP déposé, production prête |
| 5 · Croissance | après S10 | Payzone (E2-E3), volet D énergie et eau, imports Excel complets, SSO | Paiement en ligne, offre complète | Contrat Payzone |

## 4. Packs : hypothèse de départ à discuter

Unité proposée : **par site et par mois, HT**, engagement annuel avec remise ; essai gratuit 30 jours ; pilote gratuit
encadré. Les montants ci-dessous sont des **points de départ** à confronter au marché et à tes premiers échanges.

| | Essentiel | Pro | Entreprise |
|---|---|---|---|
| Pour qui | Petit atelier, 1 site | PME industrielle | Groupe, multi-sites |
| Modules | Demandes, interventions, préventif, QR, photos, indicateurs | + Magasin relié au terrain, seuils, rapports | + Achats, valeur du stock, énergie, imports, SSO |
| Sites / utilisateurs | 1 site · 5 utilisateurs | 3 sites · 15 par site | illimité |
| Hypothèse de prix | à fixer | à fixer | sur devis |
| Options possibles | — | Achats en option | Accompagnement, formation |

Questions : prix d'appel visé ? facturation par site ou par utilisateur ? achats en option du Pro ?
réduction annuelle ? tarif pilote converti ?

## 5. Décisions à prendre (liste courte)

1. Ancien dépôt / hébergement lié à perfora.ma, et accès au compte Nindohost.
2. Cloudflare Pages (recommandé) ou Vercel Pro.
3. Supabase Pro à partir de quand (au plus tard au premier pilote).
4. Juriste ou consultant pour la CNDP.
5. Structure juridique et compte bancaire (préalable à Payzone).
6. Packs : prix, unité, essai, options.
7. Secteurs prioritaires pour les préréglages.
8. Récompense de parrainage.
9. Rôles supplémentaires (responsable de site, direction multi-sites, auditeur).
10. MFA obligatoire pour qui.

## 6. Sources consultées (6 nov. 2026)

- Vercel, offre Hobby réservée à l'usage personnel non commercial : https://vercel.com/docs/plans/hobby et https://vercel.com/docs/limits/fair-use-guidelines
- Cloudflare Pages, limites de l'offre gratuite : https://developers.cloudflare.com/pages/platform/limits ; comparatif : https://hostfleet.pages.dev/cf-pages-vs-vercel-vs-netlify-2026/
- Supabase et Neon, offres gratuites : https://makerkit.dev/blog/saas/supabase-pricing ; https://neon.com/guides/neon-vs-supabase-free-plan
- CNDP, transferts internationaux (articles 43-44 de la loi 09-08) : https://upsilon-consulting.com/transfert-international-donnees-personnelles-maroc/ ; procédure accélérée CNDP / Microsoft : https://www.cndp.ma/wp-content/uploads/2023/11/CNDP-MICROSOFT-Communiqu_de_presse-20020406.pdf
- Payzone : https://developers.payzone.ma/gateway ; https://payzone.ma/faqs/ ; https://payzone.ma/saas/
