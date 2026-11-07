/* GMAO terrain — remontée des erreurs (étape 6, supervision) : erreurs JavaScript, refus du serveur, synchronisation
   en échec. Gardées sur l'appareil (20 au plus, regroupées par message), envoyées au serveur quand on est connecté
   (supabase/securite.sql, erreurs_signaler), lues dans l'onglet « Technique » du centre de contrôle.
   Aucune donnée métier n'est envoyée : message, page, version, navigateur. Chargé juste après sync.js. */
const Erreurs = (() => {
  const CLE = 'perfora-erreurs', MAX = 20;
  let file = [];
  try { file = JSON.parse(localStorage.getItem(CLE)) || []; } catch { file = []; }
  const garder = () => { try { localStorage.setItem(CLE, JSON.stringify(file)); } catch { /* stockage plein ou interdit */ } };
  // Bruits sans intérêt : erreurs d'extensions du navigateur, scripts d'autres sites, coupures réseau (déjà gérées).
  const IGNORER = /^Script error\.?$|ResizeObserver loop|chrome-extension:|moz-extension:|Serveur injoignable|Réseau trop lent|Failed to fetch|NetworkError|Load failed/i;

  function noter({ nature = 'erreur', message, detail = '' }) {
    message = String(message || '').trim().slice(0, 300);
    if (!message || IGNORER.test(message) || IGNORER.test(String(detail))) return;
    const page = (location.pathname.includes('/console') ? 'console ' : '') + (location.hash || '#/').slice(0, 110);
    const x = file.find(e => e.message === message && e.nature === nature);
    if (x) { x.nb++; x.page = page; }
    else {
      file.push({ nature, message, detail: String(detail).slice(0, 1500), page, version: Erreurs.version || '', appareil: navigator.userAgent.slice(0, 150), nb: 1 });
      if (file.length > MAX) file.shift();
    }
    garder();
  }

  let envoiEnCours = false;
  async function envoyer() {
    if (envoiEnCours || !file.length || !navigator.onLine || typeof Sync === 'undefined' || !Sync.etatCourant().connecte) return;
    envoiEnCours = true;
    const lot = file.slice(0, 20);
    try {
      await Sync.signalerErreurs(lot);
      file = file.filter(e => !lot.includes(e));
      garder();
    } catch { /* on réessaiera ; ne jamais créer d'erreur en signalant une erreur */ }
    finally { envoiEnCours = false; }
  }

  addEventListener('error', e => noter({ message: e.message || 'Erreur', detail: e.error?.stack || `${e.filename || ''}:${e.lineno || ''}` }));
  addEventListener('unhandledrejection', e => noter({ message: e.reason?.message || String(e.reason || 'Promesse rejetée'), detail: e.reason?.stack || '' }));
  addEventListener('online', () => setTimeout(envoyer, 3000));
  setInterval(envoyer, 120000);

  return { noter, envoyer, enAttente: () => file.length, version: '' };
})();
window.Erreurs = Erreurs;   // « const » au niveau du script ne crée pas window.Erreurs : sync.js et app.js passent par window
