// Centre de contrôle (CC1) : revenu mensuel, état commercial, alertes, prolongation.
const test = require('node:test');
const assert = require('node:assert/strict');
const K = require('../console/calculs_console.js');

const T = '2026-11-10';
const cl = (nom, abo, o = {}) => ({ id: nom, nom, statut: 'actif', abonnement: { statut: 'actif', ...abo }, ...o });

test('revenu mensuel : remise déduite, annuel ramené au mois, prix inconnu = inconnu (pas 0)', () => {
  assert.equal(K.mensuel({ prix: 1000, periodicite: 'mensuel', remisePct: 10 }), 900);
  assert.equal(K.mensuel({ prix: 12000, periodicite: 'annuel' }), 1000);
  assert.equal(K.mensuel({ prix: null }), null);
  assert.equal(K.mensuel({ prix: 0, periodicite: 'mensuel' }), 0, 'gratuit convenu ≠ inconnu');
});

test('état commercial : démo, essai, actif, échu, suspendu', () => {
  assert.equal(K.etat(cl('a', {}, { demo: true }), T), 'demo');
  assert.equal(K.etat(cl('b', { statut: 'essai', fin: '2026-11-20' }), T), 'essai');
  assert.equal(K.etat(cl('c', { fin: '2026-11-09' }), T), 'echu');
  assert.equal(K.etat(cl('d', { fin: '2026-11-10' }), T), 'actif', 'le jour de fin est encore payé');
  assert.equal(K.etat(cl('e', { statut: 'suspendu' }), T), 'suspendu');
});

test('alertes : échu et fin d’essai d’abord, puis échéances, inactivité, prix manquant, démarrage', () => {
  const clients = [
    cl('Zeta', { fin: '2026-11-05', prix: 500 }, { derniereActivite: '2026-11-09T10:00:00Z' }),
    cl('Alpha', { statut: 'essai', fin: '2026-11-13' }, { derniereActivite: '2026-11-09T10:00:00Z' }),
    cl('Beta', { fin: '2026-12-01', prix: 800 }, { derniereActivite: '2026-10-30T08:00:00Z' }),
    cl('Gamma', { prix: null }, { derniereActivite: '2026-11-10T08:00:00Z' }),
    cl('Delta', { statut: 'essai', fin: '2026-12-31' }, { miseEnService: { kit_envoye: 'x', import: 'y' } }),
    cl('Demo', {}, { demo: true }),
  ];
  const a = K.alertes(clients, T).map(x => `${x.client.nom}:${x.type}`);
  assert.deepEqual(a, ['Alpha:fin_essai', 'Zeta:echu', 'Beta:echeance', 'Beta:inactif', 'Delta:demarrage', 'Gamma:sans_prix']);
  assert.match(K.alertes(clients, T).find(x => x.type === 'demarrage').texte, /2\/7/);
});

test('synthèse : revenu des seuls clients actifs à prix connu ; la démo ne compte pas', () => {
  const s = K.synthese([
    cl('A', { prix: 1000, periodicite: 'mensuel' }), cl('B', { prix: 12000, periodicite: 'annuel', fin: '2026-12-01' }),
    cl('C', { prix: null }), cl('D', { statut: 'essai', fin: '2026-11-20' }), cl('E', { prix: 500, fin: '2026-11-01' }), cl('F', {}, { demo: true }),
  ], T);
  assert.deepEqual([s.mrr, s.arr, s.sansPrix, s.clients, s.parEtat.demo, s.parEtat.echu, s.echeances30], [2000, 24000, 1, 5, 1, 1, 2]);
});

test('prolonger : depuis la fin, ou depuis aujourd’hui si dépassée ; fin de mois respectée', () => {
  assert.equal(K.prolonger('2026-12-15', T, 'mensuel'), '2027-01-15');
  assert.equal(K.prolonger('2026-11-01', T, 'mensuel'), '2026-12-10', 'échéance dépassée : on repart d’aujourd’hui');
  assert.equal(K.prolonger('2027-01-31', T, 'mensuel'), '2027-02-28');
  assert.equal(K.prolonger(null, T, 'annuel'), '2027-11-10');
});

test('ICE : 15 chiffres', () => {
  assert.ok(K.iceValide('001234567000089'));
  assert.ok(K.iceValide(''));
  assert.ok(!K.iceValide('12345'));
});
