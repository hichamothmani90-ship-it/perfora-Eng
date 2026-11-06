/* Lecture d'un classeur Excel (.xlsx) dans le navigateur, sans bibliothèque : un .xlsx est une archive zip de XML.
   Décompression par DecompressionStream('deflate-raw') (navigateurs récents), XML par DOMParser.
   Rend { 'Nom de feuille': [{ n: numéro de ligne, cellules: [valeurs] }] } : texte, nombre ou booléen ; les dates
   restent des numéros de série Excel (convertis par Kit.dateISO selon la colonne). Lecture seule, valeurs uniquement. */
const Xlsx = (() => {
  const u16 = (b, o) => b[o] | (b[o + 1] << 8);
  const u32 = (b, o) => (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
  const dec = new TextDecoder('utf-8');

  /** Entrées de l'archive : nom → { methode, taille compressée, position des données }. */
  function sommaire(b) {
    let fin = -1;
    for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) if (u32(b, i) === 0x06054b50) { fin = i; break; }
    if (fin < 0) throw new Error('Fichier illisible : ce n’est pas un classeur .xlsx');
    const n = u16(b, fin + 10);
    let o = u32(b, fin + 16);
    const entrees = new Map();
    for (let k = 0; k < n; k++) {
      if (u32(b, o) !== 0x02014b50) throw new Error('Archive .xlsx endommagée');
      const methode = u16(b, o + 10), taille = u32(b, o + 20), lnom = u16(b, o + 28), lext = u16(b, o + 30), lcom = u16(b, o + 32), local = u32(b, o + 42);
      const nom = dec.decode(b.subarray(o + 46, o + 46 + lnom));
      const debut = local + 30 + u16(b, local + 26) + u16(b, local + 28);
      entrees.set(nom, { methode, taille, debut });
      o += 46 + lnom + lext + lcom;
    }
    return entrees;
  }

  async function lireEntree(b, e) {
    const brut = b.subarray(e.debut, e.debut + e.taille);
    if (e.methode === 0) return dec.decode(brut);
    if (e.methode !== 8) throw new Error('Compression non prise en charge');
    if (typeof DecompressionStream === 'undefined') throw new Error('Navigateur trop ancien pour lire un .xlsx (utilisez Chrome, Edge, Firefox ou Safari récents)');
    const flux = new Blob([brut]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    return dec.decode(await new Response(flux).arrayBuffer());
  }

  const xml = s => new DOMParser().parseFromString(s, 'application/xml');
  const enfants = (n, nom) => [...n.getElementsByTagNameNS('*', nom)];
  const colonne = ref => { let c = 0; for (const ch of ref.replace(/\d+$/, '')) c = c * 26 + ch.charCodeAt(0) - 64; return c - 1; };
  const texteSi = si => enfants(si, 't').map(t => t.textContent).join('');

  async function lire(fichierOuTampon) {
    const b = new Uint8Array(fichierOuTampon instanceof ArrayBuffer ? fichierOuTampon : await fichierOuTampon.arrayBuffer());
    const z = sommaire(b);
    const lireXml = async nom => (z.has(nom) ? xml(await lireEntree(b, z.get(nom))) : null);
    const wb = await lireXml('xl/workbook.xml');
    const rels = await lireXml('xl/_rels/workbook.xml.rels');
    if (!wb || !rels) throw new Error('Classeur .xlsx incomplet');
    const cible = new Map(enfants(rels, 'Relationship').map(r => [r.getAttribute('Id'), r.getAttribute('Target')]));
    const ss = await lireXml('xl/sharedStrings.xml');
    const chaines = ss ? enfants(ss, 'si').map(texteSi) : [];
    const sortie = {};
    for (const s of enfants(wb, 'sheet')) {
      const rid = s.getAttribute('r:id') || s.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships', 'id');
      let chemin = cible.get(rid) || '';
      chemin = chemin.startsWith('/') ? chemin.slice(1) : 'xl/' + chemin.replace(/^\.\//, '');
      const f = await lireXml(chemin);
      if (!f) continue;
      const lignes = [];
      for (const row of enfants(f, 'row')) {
        const cellules = [];
        for (const c of enfants(row, 'c')) {
          const t = c.getAttribute('t'), v = enfants(c, 'v')[0]?.textContent;
          let val = null;
          if (t === 's') val = v != null ? chaines[Number(v)] ?? null : null;
          else if (t === 'inlineStr') val = enfants(c, 'is').map(texteSi).join('');
          else if (t === 'str') val = v ?? null;
          else if (t === 'b') val = v === '1';
          else if (t === 'e') val = null;
          else if (v != null && v !== '') val = Number(v);
          if (val !== null && val !== '') cellules[colonne(c.getAttribute('r'))] = val;
        }
        if (cellules.length) lignes.push({ n: Number(row.getAttribute('r')), cellules: Array.from(cellules, x => (x === undefined ? null : x)) });
      }
      sortie[s.getAttribute('name')] = lignes;
    }
    return sortie;
  }
  return { lire };
})();
