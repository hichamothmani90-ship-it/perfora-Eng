// Volet B — magasin relié au terrain : scénarios V3 §37 et cas limites.
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../js/calculs.js');

const A = 'art-joint', S1 = 'site-1', S2 = 'site-2';
const mv = (o) => ({ id: Math.random().toString(36).slice(2), articleId: A, siteId: S1, ...o });
const entree = (q, site = S1) => mv({ type: 'entree', qte: q, siteId: site });

test('V3 §37 : deux pièces remises, une utilisée et une rendue', () => {
  const b = { id: 'b1', articleId: A, siteId: S1, qte: 2, qteReservee: 2, statut: 'reserve' };
  const m = [entree(5), mv({ type: 'remise', qte: -2, besoinId: 'b1' }), mv({ type: 'retour', qte: 1, besoinId: 'b1' })];
  const pieces = [{ besoinId: 'b1', qte: 1 }];
  assert.equal(C.stockPhysique(m, A, S1), 4, '5 − 2 remises + 1 retour');
  assert.equal(C.etatBesoin(b, m), 'remis');
  assert.deepEqual(C.rapprochementBesoin(b, m, pieces), { remis: 2, utilise: 1, retourne: 1, detenu: 0, ecart: false });
  assert.equal(C.qteReservee([b], m, A, S1), 0, 'réservation entièrement servie');
});

test('V3 §37 : réservation partiellement servie', () => {
  const b = { id: 'b2', articleId: A, siteId: S1, qte: 3, qteReservee: 3, statut: 'reserve' };
  const m = [entree(10), mv({ type: 'remise', qte: -1, besoinId: 'b2' })];
  assert.equal(C.etatBesoin(b, m), 'partiellement_remis');
  assert.equal(C.stockPhysique(m, A, S1), 9);
  assert.equal(C.qteReservee([b], m, A, S1), 2, 'reste réservé = 3 − 1 remis');
  assert.equal(C.stockDisponible([b], m, A, S1), 7, 'disponible = 9 − 2');
});

test('V3 §37 : retrait urgent régularisé sans doublon', () => {
  const b = { id: 'b3', articleId: A, siteId: S1, qte: 1, urgent: true, statut: 'demande' };
  const retrait = mv({ type: 'remise', qte: -1, besoinId: 'b3', urgent: true, aVerifier: true });
  let m = [entree(3), retrait];
  assert.equal(C.stockPhysique(m, A, S1), 2);
  assert.equal(C.retraitsAVerifier(m).length, 1);
  assert.equal(C.etatBesoin(b, m), 'remis', 'le retrait urgent vaut remise');
  // le magasinier vérifie : le mouvement est marqué, aucun nouveau mouvement n'est créé
  m = [m[0], { ...retrait, verifieLe: '2026-11-06T10:00', verifiePar: 'Magasinier' }];
  assert.equal(C.stockPhysique(m, A, S1), 2, 'pas de second débit');
  assert.equal(C.retraitsAVerifier(m).length, 0);
});

test('une demande ne consomme pas le stock ; un besoin annulé ne réserve rien', () => {
  const m = [entree(4)];
  const demande = { id: 'b4', articleId: A, siteId: S1, qte: 2, statut: 'demande' };
  const annule = { id: 'b5', articleId: A, siteId: S1, qte: 2, qteReservee: 2, statut: 'annule' };
  assert.equal(C.stockDisponible([demande, annule], m, A, S1), 4);
  assert.equal(C.etatBesoin(demande, m), 'demande');
  assert.equal(C.etatBesoin(annule, m), 'annule');
});

test('besoin hors catalogue : aucun effet sur le stock des articles', () => {
  const libre = { id: 'b6', articleId: null, description: 'Roulement 6204 ou équivalent', siteId: S1, qte: 1, statut: 'demande' };
  assert.equal(C.stockDisponible([libre], [entree(2)], A, S1), 2);
  assert.equal(C.etatBesoin(libre, []), 'demande');
});

test('stock par site : les mouvements d’un site ne touchent pas l’autre', () => {
  const m = [entree(5, S1), entree(3, S2), mv({ type: 'remise', qte: -1, siteId: S2, besoinId: 'x' })];
  assert.equal(C.stockPhysique(m, A, S1), 5);
  assert.equal(C.stockPhysique(m, A, S2), 2);
  assert.equal(C.stockPhysique(m, A), 7, 'tous sites');
});

test('rebut tracé sans retour en stock ; écart visible si plus d’utilisé que de remis', () => {
  const b = { id: 'b7', articleId: A, siteId: S1, qte: 1, statut: 'reserve', qteReservee: 1 };
  const m = [entree(2), mv({ type: 'remise', qte: -1, besoinId: 'b7' }), mv({ type: 'rebut', qte: 0, quantite: 1, besoinId: 'b7' })];
  assert.equal(C.stockPhysique(m, A, S1), 1);
  const r = C.rapprochementBesoin(b, m, [{ besoinId: 'b7', qte: 2 }]);
  assert.equal(r.detenu, -1);
  assert.equal(r.ecart, true);
});

test('pièces anciennes (sans besoin) : stock inchangé, compatibles', () => {
  const m = [entree(3), mv({ type: 'sortie', qte: -1, otId: 'ot-ancien' })];
  assert.equal(C.stockPhysique(m, A, S1), 2);
});

test('attente « pièce » levée à la date de la remise complète, pas avant', () => {
  const b = { id: 'b8', articleId: A, siteId: S1, qte: 2, statut: 'reserve', qteReservee: 2 };
  const ot = { attentes: [{ id: 'a1', motif: 'piece', besoinId: 'b8', depuis: '2026-11-06T08:00', fin: null }, { id: 'a2', motif: 'acces_exploitation', depuis: '2026-11-06T08:00', fin: null }] };
  let m = [entree(5), mv({ type: 'remise', qte: -1, besoinId: 'b8', le: '2026-11-06T09:00' })];
  assert.equal(C.attentesALever(ot, [b], m).length, 0, 'remise partielle : attente maintenue');
  m = [...m, mv({ type: 'remise', qte: -1, besoinId: 'b8', le: '2026-11-06T10:30' })];
  const l = C.attentesALever(ot, [b], m);
  assert.equal(l.length, 1, 'seule l’attente liée au besoin est levée');
  assert.equal(l[0].fin, '2026-11-06T10:30');
});

test('pièces détenues : remises ni utilisées ni rendues', () => {
  const b = { id: 'b9', articleId: A, siteId: S1, qte: 3, statut: 'reserve', qteReservee: 3 };
  const m = [entree(5), mv({ type: 'remise', qte: -3, besoinId: 'b9' }), mv({ type: 'retour', qte: 1, besoinId: 'b9' })];
  assert.equal(C.piecesDetenues([b], m, [{ besoinId: 'b9', qte: 1 }])[0].detenu, 1);
  assert.equal(C.piecesDetenues([b], m, [{ besoinId: 'b9', qte: 2 }]).length, 0);
});
