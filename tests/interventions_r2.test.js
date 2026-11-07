// Lot R2 : qualification proposée / validée, arrêts planifiés / non planifiés, signalement allégé.
// Lancer : node --test tests/
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../js/calculs.js');

const ot = o => ({ id: 'o' + Math.random(), demandeIds: [], nature: 'a_qualifier', priorite: 'a_qualifier', statut: 'en_cours', creeLe: '2026-11-01T08:00', reserves: [], pieces: [], avecArret: 'inconnu', resultat: 'resolu', ...o });

test('qualification : intervention antérieure (sans le champ) = validée', () => {
  assert.deepEqual(C.qualification(ot({ nature: 'corrective', priorite: 'rapide' })), { nature: 'corrective', priorite: 'rapide', validee: true });
});

test('qualification : proposée par le technicien, utilisée tant que non validée', () => {
  const o = ot({ qualificationValidee: false, natureProposee: 'corrective', prioriteProposee: 'critique_service' });
  assert.deepEqual(C.qualification(o), { nature: 'corrective', priorite: 'critique_service', validee: false });
  assert.equal(C.aQualifier(o), true);
  assert.equal(C.aQualifier({ ...o, statut: 'annulee' }), false);
  const v = { ...o, qualificationValidee: true, nature: 'assistance_production', priorite: 'rapide' };
  assert.deepEqual(C.qualification(v), { nature: 'assistance_production', priorite: 'rapide', validee: true });
  assert.equal(C.aQualifier(v), false);
});

test('clôture : la nature proposée suffit (la validation ne bloque pas le terrain)', () => {
  assert.deepEqual(C.verifierCloture(ot({ qualificationValidee: false, natureProposee: 'corrective' })), []);
  assert.ok(C.verifierCloture(ot({ qualificationValidee: false })).some(e => /nature/.test(e)));
});

test('type d’arrêt : proposé selon la nature, choisi sinon', () => {
  assert.equal(C.typeArret(ot({ avecArret: 'non', nature: 'corrective' })), null);
  assert.equal(C.typeArret(ot({ avecArret: 'oui', nature: 'corrective' })), 'non_planifie');
  assert.equal(C.typeArret(ot({ avecArret: 'oui', nature: 'preventive' })), 'planifie');
  assert.equal(C.typeArret(ot({ avecArret: 'oui', nature: 'travaux_techniques' })), 'planifie');
  assert.equal(C.typeArret(ot({ avecArret: 'oui', nature: 'preventive', arretType: 'non_planifie' })), 'non_planifie');
  assert.equal(C.typeArret(ot({ avecArret: 'oui', qualificationValidee: false, natureProposee: 'preventive' })), 'planifie');
  assert.equal(C.typeArretPropose('assistance_production'), 'non_planifie');
});

test('clôture : arrêt non planifié → remise à disposition ou « heures inconnues »', () => {
  const base = { nature: 'corrective', avecArret: 'oui', arretDebut: '2026-11-01T08:00' };
  assert.ok(C.verifierCloture(ot(base)).some(e => /remise à disposition/.test(e)));
  assert.deepEqual(C.verifierCloture(ot({ ...base, arretFin: '2026-11-01T09:00' })), []);
  assert.deepEqual(C.verifierCloture(ot({ ...base, arretHeuresInconnues: true })), []);
  // arrêt planifié : la fin reste facultative
  assert.deepEqual(C.verifierCloture(ot({ ...base, arretType: 'planifie' })), []);
});

test('indicateurs : pannes (arrêts non planifiés), dont heures connues ; nature effective', () => {
  const ots = [
    ot({ nature: 'corrective', avecArret: 'oui', arretDebut: '2026-11-01T08:00', arretFin: '2026-11-01T10:00', equipementId: 'e1' }),
    ot({ nature: 'corrective', avecArret: 'oui', arretHeuresInconnues: true, equipementId: 'e1' }),
    ot({ nature: 'preventive', avecArret: 'oui', arretDebut: '2026-11-02T08:00', arretFin: '2026-11-02T09:00', equipementId: 'e2' }),
    ot({ qualificationValidee: false, natureProposee: 'corrective', equipementId: 'e3' }),
  ];
  const r = C.indicateurs({ demandes: [], ots, programmes: [] }, { from: '2026-10-01', today: '2026-11-06' });
  assert.equal(r.arrets.nonPlanifies, 2);
  assert.equal(r.arrets.nonPlanifiesBornes, 1);
  assert.equal(r.arrets.planifies, 1);
  assert.equal(r.parNature.corrective, 3);
  assert.equal(r.aQualifier, 1);
});

test('signaler allégé : l’état choisi remplit état, impact et besoin', () => {
  assert.deepEqual(C.ETAT_SIGNALE.arret, { etat: 'indisponible', impact: 'interrompu', besoin: 'corriger' });
  assert.deepEqual(C.ETAT_SIGNALE.mal, { etat: 'degrade', impact: 'reduit', besoin: 'corriger' });
  assert.deepEqual(C.ETAT_SIGNALE.verifier, { etat: 'anomalie', impact: 'aucun_constate', besoin: 'verifier' });
});
