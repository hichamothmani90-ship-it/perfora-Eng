/* Stockage local (IndexedDB) + journal d'audit append-only.
   Toutes les données sont chargées en mémoire au démarrage : l'interface lit
   la mémoire (instantané) et chaque écriture est persistée sur l'appareil. */
const Store = (() => {
  const DB_NAME = 'gmao-terrain';
  // v2 (lot 0) : store « photos ». v3 (lot 1) : store « sortie » = file d'envoi vers le cloud.
  // v4 (volet B) : store « besoins » (demandes de pièces depuis une intervention).
  // v5 (volet C) : stores « seuils », « achats », « valorisations ».
  // v6 (volet D) : stores « compteurs », « releves », « factures_energie », « parametres » (réglages de l'entreprise).
  // v7 (mise en service) : store « fournisseurs ».
  // v8 (fichiers joints) : store « blobs » = contenu des photos et PDF, lu à la demande (jamais chargé en mémoire).
  // v9 (lot R3) : store « equipes ».
  // Les stores existants sont conservés tels quels.
  const DB_VER = 9;
  const TYPES = ['localisations', 'equipements', 'personnes', 'demandes', 'ots',
    'programmes', 'articles', 'mouvements', 'journal', 'meta', 'photos', 'sortie', 'besoins', 'seuils', 'achats', 'valorisations',
    'compteurs', 'releves', 'factures_energie', 'parametres', 'fournisseurs', 'equipes'];
  /** Données métier (exportées, synchronisées). meta et sortie restent propres à l'appareil. */
  const METIER = TYPES.filter(t => t !== 'meta' && t !== 'sortie');
  const APPEND_ONLY = ['journal', 'mouvements', 'photos'];
  /** Fiches rattachées à un site (les autres — personnes, articles — sont communes à l'entreprise). */
  const SITE_TYPES = ['localisations', 'equipements', 'demandes', 'ots', 'programmes', 'mouvements', 'photos', 'journal', 'besoins', 'seuils', 'achats', 'valorisations', 'compteurs', 'releves', 'factures_energie'];
  let siteDe = null;
  const definirSite = fn => { siteDe = fn; };
  const data = {};
  let db;

  const req = r => new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });

  async function open() {
    db = await new Promise((res, rej) => {
      const r = indexedDB.open(DB_NAME, DB_VER);
      r.onupgradeneeded = () => {
        for (const t of TYPES) if (!r.result.objectStoreNames.contains(t)) r.result.createObjectStore(t, { keyPath: 'id' });
        if (!r.result.objectStoreNames.contains('blobs')) r.result.createObjectStore('blobs', { keyPath: 'id' });
      };
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
      // Un autre onglet (ancienne version) garde la base ouverte : l'évolution du stockage attend.
      // On le dit au lieu de rester sur « Chargement… » ; l'ouverture reprend dès qu'il se ferme.
      r.onblocked = () => {
        const v = document.querySelector('#view');
        if (v) v.innerHTML = '<div class="warn" style="margin-top:16px"><b>Mise à jour du stockage en attente.</b><br>L’appli est ouverte dans un autre onglet ou une autre fenêtre avec une ancienne version. Fermez ces autres onglets : cette page continuera toute seule. Vos données ne sont pas perdues.</div>';
      };
    });
    // Si une version plus récente s'ouvre ailleurs, on libère la base pour ne pas la bloquer.
    db.onversionchange = () => {
      db.close();
      const v = document.querySelector('#view');
      if (v) {
        v.innerHTML = '<div class="warn" style="margin-top:16px"><b>Une version plus récente de l’appli est ouverte dans un autre onglet.</b><br><button class="btn primary" type="button">Recharger cette page</button></div>';
        v.querySelector('button').addEventListener('click', () => location.reload()); // pas de script en ligne (politique de sécurité stricte)
      }
    };
    for (const t of TYPES) {
      const all = await req(db.transaction(t).objectStore(t).getAll());
      data[t] = new Map(all.map(o => [o.id, o]));
    }
    if (!data.meta.get('device')) {
      await persistMeta({ id: 'device', code: randomCode(), personneId: null });
    }
    if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
  }

  function persist(t, objs) {
    return new Promise((res, rej) => {
      const tx = db.transaction(t, 'readwrite');
      const s = tx.objectStore(t);
      for (const o of objs) s.put(o);
      tx.oncomplete = res;
      tx.onerror = () => rej(tx.error);
    });
  }

  async function persistMeta(o) { data.meta.set(o.id, o); await persist('meta', [o]); }

  function uid() {
    const b = crypto.getRandomValues(new Uint8Array(12));
    return Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
  }
  function randomCode() {
    const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const b = crypto.getRandomValues(new Uint8Array(2));
    return a[b[0] % a.length] + a[b[1] % a.length];
  }

  /** Heure locale du site, à la minute : "2026-11-06T08:15". */
  function now() {
    const d = new Date();
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
    return d.toISOString().slice(0, 16);
  }

  const device = () => data.meta.get('device');
  function currentUser() { const p = device().personneId; return p ? data.personnes.get(p) : null; }
  function currentUserName() { const u = currentUser(); return u ? u.nom : 'Appareil ' + device().code; }

  /** Référence lisible unique par appareil : DEM-K3-0007. */
  async function nextRef(prefix) {
    const c = { ...(data.meta.get('compteurs') || { id: 'compteurs' }) };
    c[prefix] = (c[prefix] || 0) + 1;
    await persistMeta(c);
    return `${prefix}-${device().code}-${String(c[prefix]).padStart(4, '0')}`;
  }

  /** Crée ou modifie un objet. Chaque champ modifié est tracé dans le journal
      (ancienne valeur, nouvelle valeur, auteur, date, motif). Rien n'est supprimé. */
  async function save(t, obj, { motif = null, action = null } = {}) {
    const prev = data[t].get(obj.id);
    const user = currentUserName();
    const ts = now();
    const entries = [];
    if (!prev) {
      obj.creeLe = obj.creeLe || ts;
      obj.creePar = obj.creePar || user;
      // Multi-site : une nouvelle fiche de site reçoit son site (parent, sinon site actif).
      if (SITE_TYPES.includes(t) && !obj.siteId && siteDe) { const s = siteDe(t, obj); if (s) obj.siteId = s; }
      entries.push({ entite: t, entiteId: obj.id, action: action || 'creation', champ: null, avant: null,
        apres: obj.ref || obj.code || obj.designation || obj.nom || obj.libelle || null });
    } else {
      const keys = new Set([...Object.keys(prev), ...Object.keys(obj)]);
      for (const k of keys) {
        if (k === 'modifieLe' || k === 'modifiePar') continue;
        const a = JSON.stringify(prev[k] ?? null), b = JSON.stringify(obj[k] ?? null);
        if (a !== b) entries.push({ entite: t, entiteId: obj.id, action: action || 'modification', champ: k, avant: prev[k] ?? null, apres: obj[k] ?? null });
      }
      if (!entries.length) return obj;
    }
    obj.modifieLe = ts;
    obj.modifiePar = user;
    data[t].set(obj.id, obj);
    const j = entries.map(e => ({ id: uid(), le: ts, auteur: user, motif, ...(obj.siteId ? { siteId: obj.siteId } : {}), ...e }));
    for (const e of j) data.journal.set(e.id, e);
    const envois = [];
    if (cloudActif() && METIER.includes(t)) {
      // Patch = seulement les champs modifiés (fusion champ par champ côté serveur).
      const p = prev ? Object.fromEntries(entries.map(e => [e.champ, obj[e.champ] ?? null]).concat([['modifieLe', ts], ['modifiePar', user]])) : obj;
      envois.push(sortie(t, obj.id, p));
      for (const e of j) envois.push(sortie('journal', e.id, e));
    }
    await Promise.all([persist(t, [obj]), persist('journal', j), envois.length ? persist('sortie', envois) : null]);
    if (envois.length) quandEcrit();
    return obj;
  }

  // ---------- file d'envoi (synchronisation cloud) ----------
  let seqSortie = 0;
  const cloudActif = () => !!data.meta.get('cloud')?.url;
  function sortie(type, rid, patch) {
    const o = { id: String(Date.now()).padStart(15, '0') + '-' + String(++seqSortie).padStart(6, '0') + '-' + uid().slice(0, 6), type, rid, patch: JSON.parse(JSON.stringify(patch)) };
    data.sortie.set(o.id, o);
    return o;
  }
  let ecouteur = null;
  const quandEcrit = () => { if (ecouteur) ecouteur(); };
  const surEcriture = fn => { ecouteur = fn; };
  const fileEnvoi = () => [...data.sortie.values()].sort((a, b) => a.id.localeCompare(b.id));
  async function retirerEnvoyes(ids) {
    await new Promise((res, rej) => {
      const tx = db.transaction('sortie', 'readwrite');
      for (const id of ids) { tx.objectStore('sortie').delete(id); data.sortie.delete(id); }
      tx.oncomplete = res; tx.onerror = () => rej(tx.error);
    });
  }
  /** Met toutes les données de l'appareil dans la file (premier envoi, reprise d'une sauvegarde). */
  async function toutEnvoyer() {
    const envois = [];
    for (const t of METIER) for (const o of data[t].values()) envois.push(sortie(t, o.id, o));
    for (let i = 0; i < envois.length; i += 500) await persist('sortie', envois.slice(i, i + 500));
    quandEcrit();
    return envois.length;
  }
  /** Applique des fiches reçues du serveur, sans journal ni renvoi.
      Les modifications locales pas encore envoyées restent prioritaires sur ce qui arrive. */
  async function appliquerDistant(rows, { remplacer = false } = {}) {
    const enAttente = new Map();
    for (const s of data.sortie.values()) enAttente.set(s.rid, { ...(enAttente.get(s.rid) || {}), ...s.patch });
    const parType = new Map();
    for (const r of rows) {
      if (!METIER.includes(r.type) || !r.data || typeof r.data.id !== 'string') continue;
      // Fusion : local < serveur < modifications locales non envoyées. Un champ absent côté
      // serveur ne fait jamais disparaître la valeur locale.
      // remplacer : version serveur telle quelle (annule une modification locale refusée).
      const obj = APPEND_ONLY.includes(r.type) || remplacer ? r.data : { ...(data[r.type].get(r.id) || {}), ...r.data, ...(enAttente.get(r.id) || {}) };
      data[r.type].set(obj.id, obj);
      if (!parType.has(r.type)) parType.set(r.type, []);
      parType.get(r.type).push(obj);
    }
    for (const [t, objs] of parType) await persist(t, objs);
    return rows.length;
  }

  async function update(t, id, patch, opts) {
    const cur = data[t].get(id);
    return save(t, { ...cur, ...patch }, opts);
  }

  function exportAll() {
    const out = { format: 'gmao-terrain', version: 1, exporteLe: now(), appareil: device().code, data: {} };
    for (const t of METIER) out.data[t] = [...data[t].values()];
    return out;
  }

  /** Fusion d'une sauvegarde : ajoute ce qui manque, garde la version la plus récente. */
  async function importAll(o) {
    if (!o || o.format !== 'gmao-terrain') throw new Error('Fichier non reconnu');
    let n = 0;
    for (const t of METIER) {
      if (!Array.isArray(o.data?.[t])) continue;
      const changed = [];
      for (const r of o.data[t]) {
        if (!r || typeof r.id !== 'string') continue;
        const cur = data[t].get(r.id);
        if (!cur || (r.modifieLe || '') > (cur.modifieLe || '')) { data[t].set(r.id, r); changed.push(r); }
      }
      if (changed.length) { await persist(t, changed); n += changed.length; }
    }
    return n;
  }

  /** Vide les données métier et la file d'envoi (changement d'entreprise), sans toucher aux réglages. */
  async function viderMetier() {
    await blobsVider();
    for (const t of [...METIER, 'sortie']) {
      await new Promise((res, rej) => { const tx = db.transaction(t, 'readwrite'); tx.objectStore(t).clear(); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
      data[t] = new Map();
    }
    // Les compteurs de références sont conservés : pas de doublon de référence sur cet appareil.
  }

  // ---------- contenu des fichiers joints : { id (= id de la fiche photos), blob, envoye } ----------
  const blobLire = id => req(db.transaction('blobs').objectStore('blobs').get(id));
  const blobEcrire = rec => new Promise((res, rej) => { const tx = db.transaction('blobs', 'readwrite'); tx.objectStore('blobs').put(rec); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
  const blobsVider = () => new Promise((res, rej) => { const tx = db.transaction('blobs', 'readwrite'); tx.objectStore('blobs').clear(); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });

  async function wipe() {
    await blobsVider();
    for (const t of TYPES) {
      await new Promise((res, rej) => { const tx = db.transaction(t, 'readwrite'); tx.objectStore(t).clear(); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
      data[t] = new Map();
    }
    await persistMeta({ id: 'device', code: randomCode(), personneId: null });
  }

  return { open, data, save, update, uid, now, nextRef, device, persistMeta, currentUser, currentUserName, exportAll, importAll, wipe, blobLire, blobEcrire,
    cloudActif, surEcriture, fileEnvoi, retirerEnvoyes, toutEnvoyer, appliquerDistant, viderMetier, definirSite, SITE_TYPES };
})();
