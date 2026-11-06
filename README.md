# GMAO terrain

Application de maintenance locale, mobile d'abord, hors ligne d'abord.
Aucune installation : Python (déjà présent) sert seulement les fichiers ; les données
restent dans le navigateur de chaque appareil (IndexedDB).

## Lancer
Double-cliquer sur `Lancer GMAO.bat` (ou `python serveur.py`), puis http://localhost:8080
→ « Charger la démo » pour voir un exemple.

Sur PC : menu du navigateur → « Installer l'application » pour l'avoir comme un logiciel de bureau.

## Principe « traçabilité légère » (CLAUDE.md, décision du 6 nov. 2026)
- Pas de chronomètre, pas de sessions de travail : on trace des faits et des dates-jalons.
- Arrêt de production = Oui / Non / Inconnu ; début et fin facultatifs ;
  durée affichée seulement si les deux bornes existent (jamais inventée).
- Une info inconnue reste inconnue (heure du fait, cause).
- Rien n'est supprimé : statuts, mouvements inverses, journal d'audit append-only.
  Corriger une intervention clôturée exige un motif.

## Parcours
1. **Signaler** (< 30 s) : équipement (recherche ou QR), état, besoin, constat, impact.
   Case « Je prends en charge et j'interviens » → crée demande + intervention en une fois.
2. **Intervention** : intervenants, arrêt oui/non, activités, travaux réalisés, résultat,
   cause + certitude, pièces (sortie de stock), réserves/suites, mise en attente (motif).
3. **Clôture** : bloquée si nature non qualifiée, résultat absent, réserve bloquante ouverte,
   ou résultat partiel sans suite. Pour le préventif, l'échéance suivante est calculée.

## Indicateurs (par équipement, sans classement individuel)
Interventions par nature, délai médian de clôture, préventif réalisé à échéance,
pièces consommées par équipement, pannes répétitives (1 demande = 1 fait),
arrêts : durée cumulée uniquement sur bornes connues, chevauchements fusionnés.

## QR codes et photos
- Parc → « Planche de QR codes » : un QR par équipement, à imprimer **depuis l'adresse en ligne**
  (sinon les QR pointent vers le PC local). Scanné avec l'appareil photo, il ouvre « Signaler ».
- Photos au signalement et sur les demandes / interventions : réduites à 1280 px (~150 Ko) sur l'appareil.
- L'accueil rappelle d'exporter une sauvegarde après 7 jours ou 100 modifications.

## Tests
    node --test "tests/*.test.js"
Règles de calcul et scénarios de recette S01–S08 (`tests/recette.test.js`),
générateur de QR contre les vecteurs de la norme (`tests/qr.test.js`).

## Plusieurs appareils
Chaque appareil a son code (dans les références : `DEM-K3-0007`).
Réglages → Exporter (JSON) puis Importer sur l'autre appareil : fusion, la version la plus récente gagne.

## Limite connue : hors ligne sur téléphone
Le mode hors ligne (service worker) et la caméra QR exigent `localhost` ou HTTPS.
Via `http://IP-du-PC:8080` le téléphone fonctionne et enregistre localement, mais l'appli
ne s'ouvrira pas sans le PC. Solutions : héberger ces fichiers statiques en HTTPS
(GitHub Pages, Netlify… — les données restent sur l'appareil), ou certificat local.

## Fichiers
`index.html`, `css/app.css`, `js/store.js` (stockage + journal), `js/calculs.js` (règles et
indicateurs, testés), `js/qr.js` (QR codes hors ligne), `js/app.js` (écrans),
`sw.js` (cache hors ligne — changer `VERSION` à chaque livraison), `serveur.py`.
