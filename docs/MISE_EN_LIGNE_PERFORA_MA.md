# Mise en ligne sur perfora.ma (phase 1)

Choix validés le 6 nov. 2026 : **Cloudflare Pages** pour les pages, **zone DNS chez Cloudflare** (le domaine reste
enregistré chez Nindohost). Résultat visé : `perfora.ma` (site de présentation), `www.perfora.ma` (redirigé vers
perfora.ma), `app.perfora.ma` (l'application). L'adresse GitHub Pages reste en service pendant la transition.

État constaté le 6 nov. 2026 : serveurs de noms `ns1-4.nindohost.net`, **zone vide** (aucune adresse, aucun e-mail,
dernière modification le 3 nov.). Rien ne casse donc en changeant de serveurs de noms. Le dépôt public `perfora-Eng`
ne déclare pas perfora.ma ; l'ancien dépôt n'a plus d'effet une fois les DNS chez Cloudflare.

## A. Ce que tu fais (comptes et accès : 20 minutes)

1. **Créer un compte Cloudflare gratuit** : https://dash.cloudflare.com/sign-up (adresse : la tienne).
2. **Ajouter le domaine** : « Add a domain » → `perfora.ma` → offre **Free**. Cloudflare affiche **deux serveurs de
   noms** (du type `xxx.ns.cloudflare.com`). Les noter.
3. **Chez Nindohost** (espace client) : Domaines → perfora.ma → **Serveurs DNS / Nameservers** → remplacer
   `ns1…ns4.nindohost.net` par les deux serveurs Cloudflare → enregistrer. Délai : quelques heures, jusqu'à 48 h pour le .ma.
4. **Relier GitHub à Cloudflare Pages** : Workers & Pages → Create → Pages → « Connect to Git » → autoriser GitHub
   **uniquement pour le dépôt `perfora-Eng`**.
5. Me prévenir : je fais la suite (ou je la fais avec toi dans le navigateur, une fois connecté, réglage par réglage).

## B. Ce que je fais ensuite

| Étape | Réglage |
|---|---|
| Projet `perfora-app` | branche `main` · build : `sh scripts/build_pages.sh app` · sortie : `dist` · domaine `app.perfora.ma` |
| Projet `perfora-site` | **dépôt séparé `perfora-site`** (Cloudflare refuse deux projets sur un même dépôt) · branche `main` · pas de build · sortie : `/` · domaines `perfora.ma` et `www.perfora.ma` (www → perfora.ma) |
| Vérification avant bascule | sur les adresses `*.pages.dev` : connexion, synchro, caméra QR, hors ligne, en-têtes de sécurité (`deploy/app/_headers`) |
| Supabase | Authentication → URL Configuration : Site URL `https://app.perfora.ma`, URL de redirection autorisées : app.perfora.ma + github.io (transition) |
| Appli | adresse publique par défaut des QR codes → `https://app.perfora.ma/` ; sur l'ancienne adresse, bandeau « Perfora déménage » une fois tout envoyé |
| E-mails | Cloudflare Email Routing : `contact@perfora.ma` → ta boîte Gmail (réception gratuite). Envoi des invitations : service dédié (Brevo ou Resend) depuis `no-reply@perfora.ma`, enregistrements SPF / DKIM / DMARC, réglage SMTP dans Supabase |

## B bis. Fait le 6 nov. 2026

- perfora.ma ajouté à Cloudflare (offre Free) ; serveurs de noms Nindohost remplacés par `kay.ns.cloudflare.com` et
  `ram.ns.cloudflare.com` (domaine enregistré le 3 nov. 2026 : aucun ancien hébergement à détacher). DNSSEC : inactif.
- Application Cloudflare installée sur GitHub ; projet Pages `perfora-app` (dépôt perfora-Eng, build
  `sh scripts/build_pages.sh app`, sortie `dist`) → https://perfora-app.pages.dev ; projet `perfora-site` (dépôt perfora-site).

- **En ligne le 6 nov. 2026** : https://app.perfora.ma (projet perfora-app) et https://perfora.ma +
  https://www.perfora.ma (projet perfora-site), certificats HTTPS actifs ; vérifié : v21, en-têtes de sécurité,
  connexion Supabase, service worker (13 fichiers en cache). Enregistrements DNS : `app` CNAME perfora-app.pages.dev
  (ajouté à la main), `perfora.ma` et `www` CNAME perfora-site.pages.dev (créés par Cloudflare), tous « proxied ».
- Supabase → Authentication → URL Configuration : Site URL `https://app.perfora.ma/` ; URL de redirection autorisées :
  `https://app.perfora.ma/**` et `https://hichamothmani90-ship-it.github.io/perfora-Eng/**` (transition).
- v22 : adresse par défaut des QR codes = app.perfora.ma ; bandeau « Perfora déménage » sur l'ancienne adresse github.io.
- Chaque `git push` sur main publie automatiquement : GitHub Pages (ancienne adresse) et app.perfora.ma (Cloudflare).
- **E-mails (6 nov. 2026)** :
  - Réception : Cloudflare Email Routing actif sur perfora.ma ; règle `contact@perfora.ma` → hicham.othmani90@gmail.com
    (adresse déjà vérifiée) ; enregistrements MX route1-3.mx.cloudflare.net, SPF `include:_spf.mx.cloudflare.net`, DKIM cf2024-1.
  - Envoi : Resend (compte existant, qui contient aussi auth.audixa.ma), domaine perfora.ma **vérifié**, région Irlande
    (eu-west-1), suivi des ouvertures et des clics désactivé. DNS ajoutés à la main (pas d'accès donné à Resend sur
    Cloudflare) : `resend._domainkey` TXT, `rsend` et `send` CNAME (DNS only), `_dmarc` TXT `v=DMARC1; p=none;`.
  - Supabase → Authentication → Emails → SMTP : smtp.resend.com, port 465, utilisateur `resend`, mot de passe = clé
    d'API Resend « Supabase Perfora » (droit d'envoi seulement, saisie par Hicham), expéditeur `no-reply@perfora.ma`,
    nom « Perfora ». Limite Supabase : 30 e-mails d'authentification par heure (réglable).
  - Restes facultatifs : redirection www → perfora.ma ; supprimer l'ancien `default._domainkey` (hérité de Nindohost) ;
    durcir DMARC (`p=quarantine`) après quelques semaines d'envois sans problème.

## C. Transition des téléphones (important)

Les données hors ligne d'un téléphone sont liées à l'adresse de l'appli. Passer de github.io à app.perfora.ma :
1. sur l'ancienne adresse, vérifier « ☁ À jour » (rien en attente d'envoi) ;
2. ouvrir app.perfora.ma, se connecter : les données reviennent du serveur ;
3. « Ajouter à l'écran d'accueil » depuis la nouvelle adresse, supprimer l'ancien raccourci.
Les QR codes déjà imprimés (adresse github.io) continuent de fonctionner pendant la transition ; réimprimer la planche
depuis app.perfora.ma pour des QR durables.

## D. Fichiers concernés

- Dépôt `perfora-site` (https://github.com/hichamothmani90-ship-it/perfora-site, copie locale `Claude Perfora/perfora-site`) :
  site de présentation (index, mentions légales à compléter, styles, script, en-têtes).
- `scripts/build_pages.sh` : prépare `dist/` (rien d'autre que le nécessaire n'est publié).
- `deploy/app/_headers` : en-têtes de sécurité de l'appli (politique de contenu stricte, caméra autorisée).
- Numéro WhatsApp du bouton « Demander une démo » : constante `WHATSAPP` dans `site.js` du dépôt perfora-site.
