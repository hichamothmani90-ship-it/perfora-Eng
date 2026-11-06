// Générateur de QR code : vecteurs de référence (ISO/IEC 18004, tutoriel Thonky)
// et relecture complète des matrices produites.
const test = require('node:test');
const assert = require('node:assert/strict');
const QR = require('../js/qr.js');
const { rsDiviseur, rsReste, bitsFormat, bitsVersion, codewords } = QR._interne;

test('Reed-Solomon : « HELLO WORLD » 1-M donne les 10 codewords de correction publiés', () => {
  const data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17];
  assert.deepEqual(rsReste(data, rsDiviseur(10)), [196, 35, 39, 119, 235, 215, 231, 226, 93, 23]);
});

test('bits de format, correction M, masques 0 à 7 (table de la norme)', () => {
  const attendus = ['101010000010010', '101000100100101', '101111001111100', '101101101001011',
    '100010111111001', '100000011001110', '100111110010111', '100101010100000'];
  attendus.forEach((b, k) => assert.equal(bitsFormat(k).toString(2).padStart(15, '0'), b, 'masque ' + k));
});

test('bits de version 7 et 10 (table de la norme)', () => {
  assert.equal(bitsVersion(7).toString(2).padStart(18, '0'), '000111110010010100');
  assert.equal(bitsVersion(10).toString(2).padStart(18, '0'), '001010010011010011');
});

// ---------- relecture : décodeur minimal indépendant du placement ----------
function lire(m) {
  const n = m.length, v = (n - 17) / 4;
  // format (copie autour du repère haut-gauche)
  let f = 0;
  const fb = [[8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8], [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8]];
  fb.forEach(([x, y], i) => { if (m[y][x]) f |= 1 << i; });
  let masque = -1;
  for (let k = 0; k < 8; k++) if (bitsFormat(k) === f) masque = k;
  assert.notEqual(masque, -1, 'bits de format illisibles');
  // seconde copie identique
  let f2 = 0;
  for (let i = 0; i < 8; i++) if (m[8][n - 1 - i]) f2 |= 1 << i;
  for (let i = 8; i < 15; i++) if (m[n - 15 + i][8]) f2 |= 1 << i;
  assert.equal(f2, f, 'les deux copies du format diffèrent');
  assert.equal(m[n - 8][8], true, 'module sombre absent');
  // zones de fonction recalculées indépendamment
  const fct = Array.from({ length: n }, () => new Array(n).fill(false));
  const mark = (x0, y0, w, h) => { for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) if (x >= 0 && y >= 0 && x < n && y < n) fct[y][x] = true; };
  mark(0, 0, 9, 9); mark(n - 8, 0, 8, 9); mark(0, n - 8, 9, 8); mark(6, 0, 1, n); mark(0, 6, n, 1);
  const AL = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]][v];
  const L = AL.length - 1;
  AL.forEach((a, i) => AL.forEach((b, j) => { if (!((i === 0 && j === 0) || (i === 0 && j === L) || (i === L && j === 0))) mark(a - 2, b - 2, 5, 5); }));
  if (v >= 7) { mark(n - 11, 0, 3, 6); mark(0, n - 11, 6, 3); }
  const F = [(x, y) => (x + y) % 2 === 0, (x, y) => y % 2 === 0, (x) => x % 3 === 0, (x, y) => (x + y) % 3 === 0,
    (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0, (x, y) => (x * y) % 2 + (x * y) % 3 === 0,
    (x, y) => ((x * y) % 2 + (x * y) % 3) % 2 === 0, (x, y) => ((x + y) % 2 + (x * y) % 3) % 2 === 0][masque];
  const bits = [];
  // parcours zigzag standard : colonnes doubles de droite à gauche, sens alterné
  let haut = true;
  for (let col = n - 1; col >= 1; col -= 2) {
    if (col === 6) col = 5;
    for (let k = 0; k < n; k++) {
      const y = haut ? n - 1 - k : k;
      for (const x of [col, col - 1]) if (!fct[y][x]) bits.push(m[y][x] !== F(x, y) ? 1 : 0);
    }
    haut = !haut;
  }
  const octets = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) octets.push(bits.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0));
  return { v, masque, octets };
}

function decoder(texte) {
  const { v, octets } = lire(QR.matrice(texte));
  const attendu = codewords(Array.from(new TextEncoder().encode(texte)), v);
  assert.deepEqual(octets.slice(0, attendu.length), attendu, 'codewords relus différents');
  return { v, attendu };
}

test('relecture : format, module sombre et codewords cohérents pour des liens réels', () => {
  for (const t of ['PRESSE-01',
    'https://hichamothmani90-ship-it.github.io/perfora-Eng/#/signaler?eq=PRESSE-01',
    'https://hichamothmani90-ship-it.github.io/perfora-Eng/#/signaler?eq=' + 'X'.repeat(120)]) {
    const { v } = decoder(t);
    assert.ok(v >= 1 && v <= 10);
  }
});

test('l’en-tête relu annonce le mode octet et la bonne longueur', () => {
  const t = 'https://exemple.test/#/signaler?eq=EMB-02';
  const { octets } = lire(QR.matrice(t));
  // version 3 = un seul bloc : les premiers codewords sont directement les données
  assert.equal(octets[0] >> 4, 0b0100);
  assert.equal(((octets[0] & 0xF) << 4) | (octets[1] >> 4), t.length);
  let s = '';
  for (let i = 0; i < t.length; i++) s += String.fromCharCode(((octets[1 + i] & 0xF) << 4) | (octets[2 + i] >> 4));
  assert.equal(s, t);
});

test('texte trop long refusé proprement', () => {
  assert.throws(() => QR.matrice('x'.repeat(400)), /trop long/);
});
