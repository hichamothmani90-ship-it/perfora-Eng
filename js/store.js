/* Stockage local (IndexedDB) + journal d'audit append-only.
   Toutes les données sont chargées en mémoire au démarrage : l'interface lit
   la mémoire (instantané) et chaque écriture est persistée sur l'appareil. */
const Store = (() => {
  const DB_NAME = 'gmao-terrain';
  const DB_VER = 1;
  const TYPES = ['localisations', 'equipements', 'personnes', 'demandes', 'ots',
    'programmes', 'articles', 'mouvements', 'journal', 'meta'];
  const data = {};
  let db;

  const req = r => new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });

  async function open() {
    db = await new Promise((res, rej) => {
      const r = indexedDB.open(DB_NAME, DB_VER);
      r.onupgradeneeded = () => {
        for (const t of TYPES) if (!r.result.objectStoreNames.contains(t)) r.result.createObjectStore(t, { keyPath: 'id' });
      };
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
    });
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
    const j = entries.map(e => ({ id: uid(), le: ts, auteur: user, motif, ...e }));
    for (const e of j) data.journal.set(e.id, e);
    await Promise.all([persist(t, [obj]), persist('journal', j)]);
    return obj;
  }

  async function update(t, id, patch, opts) {
    const cur = data[t].get(id);
    return save(t, { ...cur, ...patch }, opts);
  }

  function exportAll() {
    const out = { format: 'gmao-terrain', version: 1, exporteLe: now(), appareil: device().code, data: {} };
    for (const t of TYPES) if (t !== 'meta') out.data[t] = [...data[t].values()];
    return out;
  }

  /** Fusion d'une sauvegarde : ajoute ce qui manque, garde la version la plus récente. */
  async function importAll(o) {
    if (!o || o.format !== 'gmao-terrain') throw new Error('Fichier non reconnu');
    let n = 0;
    for (const t of TYPES) {
      if (t === 'meta' || !Array.isArray(o.data?.[t])) continue;
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

  async function wipe() {
    for (const t of TYPES) {
      await new Promise((res, rej) => { const tx = db.transaction(t, 'readwrite'); tx.objectStore(t).clear(); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
      data[t] = new Map();
    }
    await persistMeta({ id: 'device', code: randomCode(), personneId: null });
  }

  return { open, data, save, update, uid, now, nextRef, device, persistMeta, currentUser, currentUserName, exportAll, importAll, wipe };
})();
