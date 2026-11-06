/* Synchronisation cloud (prototype lot 1) — Supabase via son API web, sans bibliothèque.
   Offline-first : l'appareil reste la source immédiate. Les modifications attendent dans la
   file « sortie » et partent dès qu'il y a du réseau ; les changements des autres appareils
   sont récupérés par numéro de séquence serveur (jamais par l'horloge du téléphone). */
const Sync = (() => {
  const { data } = Store;
  const LOT_ENVOI = 100, LOT_RECEPTION = 100, RECOUVREMENT = 200;
  let enCours = false, minuteur = null;
  let surEtat = () => {}, surReception = () => {};

  const DELAI_MAX = 20000; // réseau faible : on abandonne et on réessaiera plus tard
  /** Projet Supabase du site : adresse et clé publique, publiques par conception (accès protégé par RLS). */
  const PROJET = { url: 'https://oihaqzkqhvyjybijsonc.supabase.co', cle: 'sb_publishable_Qpm_99-lOQOOJ5R__oyIcA_4nd7t3un' };
  const cfg = () => data.meta.get('cloud');
  async function requete(url, opts) {
    const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), DELAI_MAX);
    try { return await fetch(url, { ...opts, signal: ctl.signal }); }
    catch (e) { throw new Error(e.name === 'AbortError' ? 'Réseau trop lent (délai dépassé)' : 'Serveur injoignable (réseau)'); }
    finally { clearTimeout(t); }
  }
  const majCfg = patch => Store.persistMeta({ ...(cfg() || { id: 'cloud' }), ...patch });

  // ---------- connexion (Supabase Auth) ----------
  async function auth(url, cle, grant, corps) {
    const r = await requete(`${url}/auth/v1/token?grant_type=${grant}`, {
      method: 'POST', headers: { apikey: cle, 'Content-Type': 'application/json' }, body: JSON.stringify(corps),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) {
      const m = j.error_description || j.msg || j.message || '';
      const fr = /invalid login/i.test(m) ? 'E-mail ou mot de passe incorrect' : /not confirmed/i.test(m) ? 'E-mail pas encore confirmé (voir Supabase → Authentication)'
        : /api key/i.test(m) ? 'Clé publique incorrecte' : m || `Connexion refusée (${r.status})`;
      throw new Error(fr);
    }
    return j;
  }
  const session = j => ({ access: j.access_token, refresh: j.refresh_token, expire: Date.now() + (j.expires_in || 3600) * 1000, userId: j.user?.id || null, email: j.user?.email || null });

  /** Connexion ; le mot de passe n'est jamais conservé. Retourne true si c'est la première fois sur cet appareil. */
  async function connecter({ url, cle, email, motDePasse }) {
    url = url.trim().replace(/\/+$/, '');
    const premiere = !cfg()?.url;
    const j = await auth(url, cle.trim(), 'password', { email: email.trim(), password: motDePasse });
    await majCfg({ url, cle: cle.trim(), ...session(j), curseur: cfg()?.url === url ? (cfg().curseur || 0) : 0, erreur: null });
    notifier();
    return premiere;
  }
  // ---------- liens reçus par e-mail (invitation, mot de passe oublié) ----------
  /** Lit un retour de lien Supabase dans l'adresse (#access_token=…&type=invite). null sinon. */
  function lireLienEmail(hash) {
    const h = (hash || '').replace(/^#\/?/, '');
    if (!/(^|&)(access_token|error)=/.test(h)) return null;
    const p = new URLSearchParams(h);
    if (p.get('error')) {
      const code = p.get('error_code') || '';
      return { erreur: /expired/.test(code) ? 'Lien expiré : demandez un nouvel e-mail au responsable.' : (p.get('error_description') || 'Lien invalide').replace(/\+/g, ' ') };
    }
    return { type: p.get('type'), access_token: p.get('access_token'), refresh_token: p.get('refresh_token'), expires_in: Number(p.get('expires_in')) || 3600 };
  }
  /** Ouvre la session à partir du lien (sans mot de passe) et récupère l'identité du compte. */
  async function sessionDepuisLien(l) {
    const c = cfg()?.url ? cfg() : PROJET;
    const r = await requete(`${c.url}/auth/v1/user`, { headers: { apikey: c.cle, Authorization: 'Bearer ' + l.access_token } });
    if (!r.ok) throw new Error('Lien invalide ou déjà utilisé');
    const u = await r.json();
    const premiere = !cfg()?.url;
    await majCfg({ url: c.url, cle: c.cle, ...session({ ...l, user: u }), curseur: cfg()?.curseur || 0, erreur: null });
    notifier();
    return { premiere, email: u.email };
  }
  /** Envoie par e-mail un lien pour choisir son mot de passe (première connexion ou oubli).
      Le lien ramène sur l'appli (adresseRetour), qui demande alors le nouveau mot de passe. */
  async function demanderLien(email, adresseRetour) {
    const c = cfg()?.url ? cfg() : PROJET;
    const r = await requete(`${c.url}/auth/v1/recover?redirect_to=${encodeURIComponent(adresseRetour)}`, {
      method: 'POST', headers: { apikey: c.cle, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: email.trim() }),
    });
    if (!r.ok) {
      const j = await r.json().catch(() => ({}));
      const m = j.msg || j.message || j.error_description || '';
      throw new Error(/rate limit|seconds|too many/i.test(m) ? 'Trop de demandes : réessayez dans quelques minutes' : m || `Refusé (${r.status})`);
    }
  }
  async function changerMotDePasse(mdp) {
    const c = cfg();
    const r = await requete(`${c.url}/auth/v1/user`, { method: 'PUT', headers: { apikey: c.cle, Authorization: 'Bearer ' + await jeton(), 'Content-Type': 'application/json' }, body: JSON.stringify({ password: mdp }) });
    if (!r.ok) {
      const j = await r.json().catch(() => ({}));
      const m = j.msg || j.message || j.error_description || '';
      throw new Error(/weak|at least|characters/i.test(m) ? 'Mot de passe trop faible (8 caractères minimum conseillés)' : /same/i.test(m) ? 'Choisissez un mot de passe différent de l’ancien' : m || `Refusé (${r.status})`);
    }
  }

  async function deconnecter() { await majCfg({ access: null, refresh: null, expire: 0 }); notifier(); }

  async function jeton() {
    const c = cfg();
    if (!c?.refresh) throw new Error('Connexion nécessaire');
    if (c.access && c.expire - Date.now() > 60000) return c.access;
    try { await majCfg(session(await auth(c.url, c.cle, 'refresh_token', { refresh_token: c.refresh }))); }
    catch (e) {
      if (/injoignable|trop lent/.test(e.message)) throw e;   // panne réseau : on garde la session
      await majCfg({ access: null, refresh: null }); throw new Error('Session expirée : reconnectez-vous');
    }
    return cfg().access;
  }

  async function api(chemin, opts = {}) {
    const c = cfg();
    const appel = tok => requete(c.url + chemin, { ...opts, headers: { apikey: c.cle, Authorization: 'Bearer ' + tok, 'Content-Type': 'application/json' } });
    let r = await appel(await jeton());
    if (r.status === 401) { await majCfg({ expire: 0 }); r = await appel(await jeton()); }
    if (!r.ok) throw new Error(`Serveur ${r.status} : ${(await r.text()).slice(0, 160)}`);
    const t = await r.text();
    return t ? JSON.parse(t) : null;
  }

  // ---------- envoi puis réception ----------
  async function envoyer() {
    let n = 0;
    for (;;) {
      const lot = Store.fileEnvoi().slice(0, LOT_ENVOI);
      if (!lot.length) return n;
      await api('/rest/v1/rpc/push_fiches', { method: 'POST', body: JSON.stringify({ lot: lot.map(s => ({ id: s.rid, type: s.type, patch: s.patch })) }) });
      await Store.retirerEnvoyes(lot.map(s => s.id));
      n += lot.length;
      notifier();
    }
  }

  async function recevoir() {
    const curseur = cfg().curseur || 0;
    // Léger recouvrement : une transaction plus ancienne peut être validée après une plus récente.
    let apres = Math.max(0, curseur - RECOUVREMENT), max = curseur, nouveaux = 0;
    for (;;) {
      const rows = await api(`/rest/v1/fiches?select=id,type,data,seq&seq=gt.${apres}&order=seq.asc&limit=${LOT_RECEPTION}`);
      if (!rows || !rows.length) break;
      await Store.appliquerDistant(rows);
      nouveaux += rows.filter(r => r.seq > curseur).length;
      apres = rows[rows.length - 1].seq;
      max = Math.max(max, apres);
      if (rows.length < LOT_RECEPTION) break;
    }
    await majCfg({ curseur: max });
    return nouveaux;
  }

  async function synchroniser() {
    const c = cfg();
    if (enCours || !c?.url || !c.refresh) { notifier(); return; }
    if (!navigator.onLine) { notifier(); return; }
    enCours = true; notifier();
    try {
      await envoyer();               // d'abord nos patchs (le serveur fusionne)…
      const recus = await recevoir(); // …puis tout ce qui a changé ailleurs
      await majCfg({ dernier: Store.now(), erreur: null });
      if (recus) surReception(recus);
    } catch (e) {
      await majCfg({ erreur: e.message || String(e) });
    } finally {
      enCours = false; notifier();
    }
  }

  function planifier(delai = 1500) { clearTimeout(minuteur); minuteur = setTimeout(synchroniser, delai); }

  function demarrer({ etat, reception } = {}) {
    if (etat) surEtat = etat;
    if (reception) surReception = reception;
    Store.surEcriture(() => { notifier(); planifier(); });
    addEventListener('online', () => planifier(300));
    addEventListener('offline', notifier);
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') planifier(300); });
    setInterval(() => { if (document.visibilityState === 'visible') synchroniser(); }, 60000);
    planifier(500);
    notifier();
  }

  function etatCourant() {
    const c = cfg();
    return { configure: !!c?.url, connecte: !!c?.refresh, attente: data.sortie.size, enCours, erreur: c?.erreur || null,
      dernier: c?.dernier || null, email: c?.email || null, url: c?.url || null, enLigne: navigator.onLine };
  }
  function notifier() { try { surEtat(etatCourant()); } catch { /* affichage */ } }

  return { PROJET, connecter, deconnecter, synchroniser, planifier, demarrer, etatCourant, lireLienEmail, sessionDepuisLien, changerMotDePasse, demanderLien };
})();
