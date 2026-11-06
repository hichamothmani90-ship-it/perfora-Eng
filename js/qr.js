/* Générateur de QR code autonome (hors ligne) — mode octet, correction M, versions 1 à 10
   (jusqu'à 213 octets, largement assez pour un lien d'équipement).
   Implémentation conforme ISO/IEC 18004, structure inspirée de l'algorithme de référence
   de Project Nayuki. Utilisé par l'interface (window.QR) et par les tests (node). */
(function (root) {
  // Correction M : [codewords EC par bloc, [blocs, octets de données par bloc]...]
  const M = [null,
    [10, [1, 16]], [16, [1, 28]], [26, [1, 44]], [18, [2, 32]], [24, [2, 43]],
    [16, [4, 27]], [18, [4, 31]], [22, [2, 38], [2, 39]], [22, [3, 36], [2, 37]], [26, [4, 43], [1, 44]]];
  const ALIGN = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];
  const ECL_M_BITS = 0; // L=1, M=0, Q=3, H=2

  const capacite = v => M[v].slice(1).reduce((s, [n, k]) => s + n * k, 0);

  // ---------- Reed-Solomon sur GF(256), polynôme 0x11D ----------
  function gfMul(x, y) {
    let z = 0;
    for (let i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >>> 7) * 0x11D); z ^= ((y >>> i) & 1) * x; }
    return z;
  }
  function rsDiviseur(degre) {
    const r = new Array(degre).fill(0); r[degre - 1] = 1;
    let racine = 1;
    for (let i = 0; i < degre; i++) {
      for (let j = 0; j < r.length; j++) { r[j] = gfMul(r[j], racine); if (j + 1 < r.length) r[j] ^= r[j + 1]; }
      racine = gfMul(racine, 0x02);
    }
    return r;
  }
  function rsReste(donnees, diviseur) {
    const r = diviseur.map(() => 0);
    for (const b of donnees) {
      const f = b ^ r.shift(); r.push(0);
      diviseur.forEach((c, i) => { r[i] ^= gfMul(c, f); });
    }
    return r;
  }

  // ---------- codage des données ----------
  function utf8(s) { return Array.from(new TextEncoder().encode(s)); }

  function codewords(octets, v) {
    const cap = capacite(v);
    const bits = [];
    const put = (val, n) => { for (let i = n - 1; i >= 0; i--) bits.push((val >>> i) & 1); };
    put(0b0100, 4); put(octets.length, v < 10 ? 8 : 16);
    for (const b of octets) put(b, 8);
    put(0, Math.min(4, cap * 8 - bits.length));
    while (bits.length % 8) bits.push(0);
    const data = [];
    for (let i = 0; i < bits.length; i += 8) data.push(bits.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0));
    for (let p = 0xEC; data.length < cap; p ^= 0xEC ^ 0x11) data.push(p);
    // découpage en blocs + correction, puis entrelacement
    const [ec, ...groupes] = M[v];
    const div = rsDiviseur(ec);
    const blocs = [];
    let k = 0;
    for (const [n, taille] of groupes) for (let i = 0; i < n; i++) { const d = data.slice(k, k += taille); blocs.push([d, rsReste(d, div)]); }
    const out = [];
    const maxD = Math.max(...blocs.map(b => b[0].length));
    for (let i = 0; i < maxD; i++) for (const [d] of blocs) if (i < d.length) out.push(d[i]);
    for (let i = 0; i < ec; i++) for (const [, e] of blocs) out.push(e[i]);
    return out;
  }

  // ---------- matrice ----------
  function bitsFormat(masque) {
    const d = (ECL_M_BITS << 3) | masque;
    let r = d;
    for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537);
    return ((d << 10) | r) ^ 0x5412;
  }
  function bitsVersion(v) {
    let r = v;
    for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1F25);
    return (v << 12) | r;
  }

  function construire(v, cw, masque) {
    const n = v * 4 + 17;
    const mod = Array.from({ length: n }, () => new Array(n).fill(false));
    const fct = Array.from({ length: n }, () => new Array(n).fill(false));
    const set = (x, y, b) => { mod[y][x] = b; fct[y][x] = true; };

    for (let i = 0; i < n; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); } // synchronisation
    const finder = (cx, cy) => {
      for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx, y = cy + dy;
        if (x < 0 || y < 0 || x >= n || y >= n) continue;
        const d = Math.max(Math.abs(dx), Math.abs(dy));
        set(x, y, d !== 2 && d !== 4);
      }
    };
    finder(3, 3); finder(n - 4, 3); finder(3, n - 4);
    const al = ALIGN[v], last = al.length - 1;
    for (let i = 0; i < al.length; i++) for (let j = 0; j < al.length; j++) {
      if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) continue;
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(al[i] + dx, al[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }
    const format = b => {
      const bit = i => ((b >>> i) & 1) === 1;
      for (let i = 0; i <= 5; i++) set(8, i, bit(i));
      set(8, 7, bit(6)); set(8, 8, bit(7)); set(7, 8, bit(8));
      for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
      for (let i = 0; i < 8; i++) set(n - 1 - i, 8, bit(i));
      for (let i = 8; i < 15; i++) set(8, n - 15 + i, bit(i));
      set(8, n - 8, true); // module sombre
    };
    format(0); // réserve les zones avant placement
    if (v >= 7) {
      const b = bitsVersion(v);
      for (let i = 0; i < 18; i++) {
        const bit = ((b >>> i) & 1) === 1, a = n - 11 + (i % 3), c = Math.floor(i / 3);
        set(a, c, bit); set(c, a, bit);
      }
    }
    // placement en zigzag
    let i = 0;
    for (let droite = n - 1; droite >= 1; droite -= 2) {
      if (droite === 6) droite = 5;
      for (let vert = 0; vert < n; vert++) for (let j = 0; j < 2; j++) {
        const x = droite - j, monte = ((droite + 1) & 2) === 0, y = monte ? n - 1 - vert : vert;
        if (!fct[y][x] && i < cw.length * 8) { mod[y][x] = ((cw[i >>> 3] >>> (7 - (i & 7))) & 1) === 1; i++; }
      }
    }
    // masque
    const F = [(x, y) => (x + y) % 2 === 0, (x, y) => y % 2 === 0, (x) => x % 3 === 0, (x, y) => (x + y) % 3 === 0,
      (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0, (x, y) => (x * y) % 2 + (x * y) % 3 === 0,
      (x, y) => ((x * y) % 2 + (x * y) % 3) % 2 === 0, (x, y) => ((x + y) % 2 + (x * y) % 3) % 2 === 0][masque];
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (!fct[y][x] && F(x, y)) mod[y][x] = !mod[y][x];
    format(bitsFormat(masque));
    return mod;
  }

  // Pénalités (règles 1, 2 et 4 ; tout masque donne un code valide, ceci n'optimise que la lisibilité)
  function penalite(m) {
    const n = m.length; let p = 0, sombres = 0;
    for (let a = 0; a < 2; a++) for (let i = 0; i < n; i++) {
      let run = 1;
      for (let j = 1; j <= n; j++) {
        const cur = j < n ? (a ? m[j][i] : m[i][j]) : null, prev = a ? m[j - 1][i] : m[i][j - 1];
        if (cur === prev) run++; else { if (run >= 5) p += run - 2; run = 1; }
      }
    }
    for (let y = 0; y < n - 1; y++) for (let x = 0; x < n - 1; x++) { const c = m[y][x]; if (c === m[y][x + 1] && c === m[y + 1][x] && c === m[y + 1][x + 1]) p += 3; }
    for (const r of m) for (const c of r) if (c) sombres++;
    return p + 10 * Math.floor(Math.abs(sombres * 20 - n * n * 10) / (n * n));
  }

  /** Matrice booléenne (true = module sombre). */
  function matrice(texte) {
    const octets = utf8(texte);
    let v = 1;
    while (v <= 10 && capacite(v) * 8 < 4 + (v < 10 ? 8 : 16) + octets.length * 8) v++;
    if (v > 10) throw new Error('Texte trop long pour le QR code (max ~200 caractères)');
    const cw = codewords(octets, v);
    let meilleur = null, pMin = Infinity;
    for (let k = 0; k < 8; k++) { const m = construire(v, cw, k), p = penalite(m); if (p < pMin) { pMin = p; meilleur = m; } }
    return meilleur;
  }

  /** SVG net à l'impression (marge de 4 modules). */
  function svg(texte, taille = 160) {
    const m = matrice(texte), n = m.length, t = n + 8;
    let d = '';
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (m[y][x]) d += `M${x + 4} ${y + 4}h1v1h-1z`;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${t} ${t}" width="${taille}" height="${taille}" shape-rendering="crispEdges" role="img" aria-label="QR code"><rect width="${t}" height="${t}" fill="#fff"/><path d="${d}" fill="#000"/></svg>`;
  }

  const QR = { matrice, svg, _interne: { rsDiviseur, rsReste, bitsFormat, bitsVersion, codewords, capacite } };
  if (typeof module === 'object' && module.exports) module.exports = QR; else root.QR = QR;
})(this);
