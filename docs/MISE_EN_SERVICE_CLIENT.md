# Mise en service d'un client : procédure

Page : console plateforme → bouton **« Mise en service »** sur la carte de l'entreprise (administrateur plateforme seul).

1. **Créer l'entreprise et ses sites** dans la console (pack, statut essai). Les codes de site (ex. `TNG`) servent dans le kit.
2. **Envoyer le kit** : bouton « Télécharger le kit vide » (ou `kit/Kit_demarrage_Perfora.xlsx`), par e-mail ou WhatsApp,
   avec un appel de 30 min. Cocher « Kit de démarrage envoyé ». Ne jamais déposer un kit rempli dans le dépôt GitHub.
3. **Kit reçu** : cocher l'étape, puis « Importer un kit rempli » → choisir le fichier.
   - L'appli lit le fichier sur le poste (rien n'est envoyé tant que tout n'est pas correct), le relie aux codes déjà
     présents chez le client et **vérifie à blanc sur le serveur**.
   - Erreurs : tableau onglet / ligne / colonne / problème → corriger l'Excel, rechoisir le fichier.
   - Points d'attention (stock inconnu, criticité à fixer, données hors pack…) : n'empêchent pas l'import.
4. **Importer** : tout ou rien, en un **lot**. Le stock devient une entrée « inventaire initial » datée du jour, avec son
   prix s'il est connu (point de départ du coût moyen). L'étape « Données importées » se coche seule.
5. **Annuler un lot** (erreur de fichier) : possible **seulement si rien n'a été reçu depuis** pour ce client (ni saisie,
   ni modification d'une fiche importée). À faire avant d'inviter l'équipe : les téléphones déjà synchronisés garderaient
   leur copie. Sinon : corriger fiche par fiche.
6. **Inviter** : après l'import, la page liste les personnes du kit ayant un e-mail ; un clic = une invitation (rôle et
   sites du kit). Commencer par le responsable.
7. Le responsable confirme les criticités, imprime la planche de QR ; cocher les dernières étapes le jour J.

Compléter plus tard (nouveaux équipements, autre site) : même page, nouveau kit ne contenant que les ajouts ; les codes
existants peuvent être cités comme parents ou lieux.

Technique : `js/xlsx.js` (lecture .xlsx sans bibliothèque), `js/kit.js` (conversion et contrôles, `tests/kit.test.js`),
`js/vues/mise_en_service.js` (page), `supabase/mise_en_service.sql` (pf_referentiel, pf_importer, pf_annuler_lot,
pf_mes_lire, pf_mes_etape ; tests `tests_mise_en_service.sql`). Kit d'essai : `python tests/fabriquer_kit_exemple.py CODE_SITE`.
