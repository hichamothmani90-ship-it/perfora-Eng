// Lot R3 : membres (doublons), habilitations, équipes, interventions confiées à une équipe ou une société.
// Lancer : node --test tests/
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../js/calculs.js');

test('doublons : même nom sans accents ni casse, hors inactifs et hors soi-même', () => {
  const membres = [{ id: 'a', nom: 'Youssef  Amrani' }, { id: 'b', nom: 'youssef amrani', actif: false }, { id: 'c', nom: 'Saïd M.' }];
  assert.deepEqual(C.doublonsNom('YOUSSEF Amrani ', membres).map(m => m.id), ['a']);
  assert.deepEqual(C.doublonsNom('Youssef Amrani', membres, 'a'), []);
  assert.deepEqual(C.doublonsNom('said m.', membres).map(m => m.id), ['c']);
  assert.deepEqual(C.doublonsNom('  ', membres), []);
});

test('habilitations : échue si l’échéance est passée, sans échéance jamais échue', () => {
  const m = { habilitations: [{ libelle: 'B1V', echeance: '2026-10-03' }, { libelle: 'H0', echeance: '2027-03-01' }, { libelle: 'CACES' }] };
  assert.deepEqual(C.habilitationsEchues(m, '2026-11-07T10:00').map(h => h.libelle), ['B1V']);
  assert.equal(C.habilitationEchue({ echeance: '2026-11-07' }, '2026-11-07'), false);
  assert.deepEqual(C.habilitationsEchues({}, '2026-11-07'), []);
});

test('équipes d’un membre : membre ou chef, équipes actives seulement', () => {
  const eq = [{ id: 'e1', membreIds: ['a', 'b'] }, { id: 'e2', chefId: 'a', membreIds: [] }, { id: 'e3', membreIds: ['a'], actif: false }];
  assert.deepEqual(C.equipesDe('a', eq).map(e => e.id), ['e1', 'e2']);
  assert.deepEqual(C.equipesDe(null, eq), []);
});

test('intervention confiée : intervenant actif, ou société du prestataire', () => {
  const o = { intervenants: [{ personneId: 'a' }, { personneId: 'b', fin: '2026-11-07T09:00' }], societeId: 's1', equipeId: 'e1' };
  assert.equal(C.otConfiee(o, { personneId: 'a' }), true);
  assert.equal(C.otConfiee(o, { personneId: 'b' }), false);
  assert.equal(C.otConfiee(o, { personneId: 'x', societeId: 's1' }), true);
  assert.equal(C.otConfiee(o, { personneId: 'x', societeId: 's2' }), false);
  assert.equal(C.otConfiee({}, {}), false);
  assert.equal(C.otDeMesEquipes(o, ['e1']), true);
  assert.equal(C.otDeMesEquipes(o, ['e2']), false);
  assert.equal(C.otDeMesEquipes({}, ['e1']), false);
});
