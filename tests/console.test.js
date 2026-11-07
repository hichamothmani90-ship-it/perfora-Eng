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

test('WhatsApp : numéros marocains et internationaux ; texte encodé', () => {
  assert.equal(K.numeroWhatsApp('06 61 23 45 67'), '212661234567');
  assert.equal(K.numeroWhatsApp('+212 6 61 23 45 67'), '212661234567');
  assert.equal(K.numeroWhatsApp('00212661234567'), '212661234567');
  assert.equal(K.numeroWhatsApp('+33 6 12 34 56 78'), '33612345678');
  assert.equal(K.numeroWhatsApp('123'), null);
  assert.equal(K.lienWhatsApp('0661234567', 'Bonjour & merci'), 'https://wa.me/212661234567?text=Bonjour%20%26%20merci');
});

test('modèles : variables remplies ; variable sans valeur visible et signalée', () => {
  const r = K.remplir('Bonjour {contact}, échéance le {fin} ({montant}).', { contact: 'M. Bennani', fin: '30/11/2026' });
  assert.equal(r.texte, 'Bonjour M. Bennani, échéance le 30/11/2026 ({montant}).');
  assert.deepEqual(r.manquantes, ['montant']);
});

test('prospects à relancer : action due ou absente ; gagnés et perdus exclus ; pipeline', () => {
  const P = [
    { id: 'a', etape: 'contacte', prochaineAction: { date: '2026-11-08', texte: 'Rappeler' } },
    { id: 'b', etape: 'demo_prevue', prochaineAction: { date: '2026-11-20' } },
    { id: 'c', etape: 'nouveau' },
    { id: 'd', etape: 'essai', prochaineAction: { date: '2026-11-01' } },
    { id: 'e', etape: 'gagne', prochaineAction: { date: '2026-11-01' } },
    { id: 'f', etape: 'perdu', motifPerte: 'Prix' },
  ];
  assert.deepEqual(K.aRelancer(P, T).map(x => x.p.id), ['d', 'a', 'c']);
  assert.equal(K.aRelancer(P, T)[0].retard, 9);
  assert.deepEqual(K.pipeline(P), { nouveau: 1, contacte: 1, demo_prevue: 1, demo_faite: 0, essai: 1, gagne: 1, perdu: 1 });
});

test('support : en retard d’abord, puis priorité, puis ancienneté ; résolues exclues', () => {
  const S = [
    { id: '1', statut: 'ouverte', priorite: 'normale', creeLe: '2026-11-01T08:00:00Z' },
    { id: '2', statut: 'en_cours', priorite: 'urgente', creeLe: '2026-11-09T08:00:00Z' },
    { id: '3', statut: 'ouverte', priorite: 'basse', creeLe: '2026-11-02T08:00:00Z', echeance: '2026-11-05' },
    { id: '4', statut: 'resolue', priorite: 'urgente', creeLe: '2026-10-01T08:00:00Z' },
  ];
  assert.deepEqual(K.supportOuvert(S, T).map(x => x.t.id), ['3', '2', '1']);
});
