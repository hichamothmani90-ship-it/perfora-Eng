// Scénarios de recette PR MAINT 01 V3 (§12-13) et conventions de calcul.
// Lancer : node --test tests/
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../js/calculs.js');

const TODAY = '2026-11-06';
const FROM = '2026-08-08';
let n = 0;
const id = () => 'x' + (++n);
const dem = o => ({ id: id(), statut: 'a_examiner', etat: 'inconnu', impact: 'a_confirmer', creeLe: '2026-11-01T08:00', ...o });
const ot = o => ({ id: id(), demandeIds: [], nature: 'a_qualifier', statut: 'a_planifier', creeLe: '2026-11-01T08:00', reserves: [], pieces: [], avecArret: 'inconnu', ...o });
const ind = (D) => C.indicateurs({ demandes: [], ots: [], programmes: [], ...D }, { from: FROM, today: TODAY });

// ---------- conventions ----------
test('union d’intervalles : les chevauchements ne comptent qu’une fois', () => {
  assert.equal(C.dureeUnion([['2026-11-03T08:00', '2026-11-03T10:30'], ['2026-11-03T09:00', '2026-11-03T10:00']]), 150);
  assert.equal(C.dureeUnion([['2026-11-03T08:00', '2026-11-03T09:00'], ['2026-11-03T10:00', '2026-11-03T11:00']]), 120);
  assert.equal(C.dureeUnion([['2026-11-03T08:00', null]]), 0);
});

test('médiane paire et impaire, vide = null', () => {
  assert.equal(C.mediane([3, 1, 2]), 2);
  assert.equal(C.mediane([1, 2, 3, 10]), 2.5);
  assert.equal(C.mediane([]), null);
});

test('le besoin oriente la nature : changement de série = assistance, jamais panne', () => {
  assert.equal(C.NATURE_DU_BESOIN.serie, 'assistance_production');
  assert.equal(C.NATURE_DU_BESOIN.corriger, 'corrective');
  assert.equal(C.NATURE_DU_BESOIN.verifier, 'a_qualifier');
});

// ---------- S01 panne immédiate, cause inconnue ----------
test('S01 : la cause inconnue n’empêche pas la clôture ; l’équipement redevient normal', () => {
  const d = dem({ equipementId: 'P', etat: 'indisponible', impact: 'interrompu', statut: 'traitement_organise', heureFait: '2026-11-03T08:00', precisionHeure: 'exacte' });
  const o = ot({ demandeIds: [d.id], equipementId: 'P', nature: 'corrective', statut: 'en_cours', resultat: 'resolu', cause: null, certitudeCause: 'non_determinee' });
  assert.equal(C.etatEquipement('P', [d], [o]), 'indisponible');
  assert.deepEqual(C.verifierCloture(o), []);
  const clos = { ...o, statut: 'cloturee', clotureLe: '2026-11-03T11:00' };
  assert.equal(C.etatEquipement('P', [d], [clos]), 'normal');
  assert.equal(C.demandeOuverte(d, [clos]), false);
});

test('S01 : clôture refusée sans résultat ni nature qualifiée', () => {
  const err = C.verifierCloture(ot({ nature: 'a_qualifier', resultat: null }));
  assert.equal(err.length, 2);
});

// ---------- S02 défaut connu sans arrêt ----------
test('S02 : réparation programmée = corrective, aucun arrêt compté', () => {
  const d = dem({ equipementId: 'E', etat: 'anomalie', impact: 'aucun_constate', statut: 'traitement_organise' });
  const o = ot({ demandeIds: [d.id], equipementId: 'E', nature: 'corrective', creneau: '2026-11-07T07:00', avecArret: 'non' });
  const I = ind({ demandes: [d], ots: [o] });
  assert.equal(I.parNature.corrective, 1);
  assert.equal(I.parNature.preventive, undefined);
  assert.equal(I.arrets.faits, 0);
  assert.equal(I.arrets.dureeConnue, null);
});

// ---------- S03 changement de série ----------
test('S03 : l’assistance au changement de série n’est pas un fait de panne ; le défaut découvert compte une fois', () => {
  const serie = dem({ equipementId: 'M', besoin: 'serie', etat: 'normal', statut: 'traitement_organise' });
  const capteur = dem({ equipementId: 'M', besoin: 'corriger', etat: 'degrade', statut: 'traitement_organise' });
  const I = ind({ demandes: [serie, capteur], ots: [ot({ demandeIds: [serie.id], equipementId: 'M', nature: 'assistance_production' })] });
  assert.equal(I.repetitives.length, 0);
  assert.equal(I.parNature.assistance_production, 1);
});

// ---------- S04 préventif et réserve ----------
test('S04 : résultat partiel sans suite refusé ; suite non bloquante acceptée ; bloquante refusée', () => {
  const base = ot({ nature: 'preventive', resultat: 'partiel' });
  assert.equal(C.verifierCloture(base).length, 1);
  assert.deepEqual(C.verifierCloture({ ...base, reserves: [{ statut: 'ouverte', bloquante: false }] }), []);
  assert.equal(C.verifierCloture({ ...base, reserves: [{ statut: 'ouverte', bloquante: true }] }).length, 1);
  assert.equal(C.verifierCloture({ ...base, reserves: [{ statut: 'levee', bloquante: true }] }).length, 1, 'une réserve levée n’est plus une suite ouverte');
});

test('S04 : échéance fixe conservée malgré un retard ; « après réalisation » repart de la clôture', () => {
  assert.equal(C.echeanceSuivante({ regle: 'fixe', periodiciteJours: 90 }, '2026-11-04', '2026-11-10T09:00'), '2027-02-02');
  assert.equal(C.echeanceSuivante({ regle: 'apres_realisation', periodiciteJours: 30 }, '2026-11-04', '2026-11-10T09:00'), '2026-12-10');
});

test('S04 : réalisé en retard = non compté « à échéance » ; programme non lancé = dû non réalisé', () => {
  const p1 = { id: 'p1', prochaineEcheance: '2027-02-02', actif: true };
  const p2 = { id: 'p2', prochaineEcheance: '2026-11-01', actif: true };
  const tard = ot({ programmeId: 'p1', echeance: '2026-11-04', nature: 'preventive', statut: 'cloturee', clotureLe: '2026-11-05T09:00' });
  const ok = ot({ programmeId: 'p1', echeance: '2026-10-01', nature: 'preventive', statut: 'cloturee', clotureLe: '2026-10-01T15:00' });
  const I = ind({ ots: [tard, ok], programmes: [p1, p2] });
  assert.deepEqual(I.preventif, { dus: 3, aTemps: 1, nonLances: 1 });
});

// ---------- S05 attente de pièce et renfort ----------
test('S05 : deux OT et un renfort sur la même panne = un seul arrêt, durée non additionnée', () => {
  const d = dem({ equipementId: 'P', etat: 'indisponible', statut: 'traitement_organise' });
  const o1 = ot({ demandeIds: [d.id], equipementId: 'P', nature: 'corrective', avecArret: 'oui', arretDebut: '2026-11-03T08:00', arretFin: '2026-11-03T10:30' });
  const o2 = ot({ demandeIds: [d.id], equipementId: 'P', nature: 'corrective', avecArret: 'oui', arretDebut: '2026-11-03T08:00', arretFin: '2026-11-03T10:30' });
  const I = ind({ demandes: [d], ots: [o1, o2] });
  assert.equal(I.arrets.faits, 1);
  assert.equal(I.arrets.dureeConnue, 150);
  assert.deepEqual(I.repetitives, [], 'une panne = un fait, pas deux');
});

// ---------- S06 relève de nuit et doublon ----------
test('S06 : un arrêt qui traverse minuit reste continu', () => {
  assert.equal(C.dureeUnion([['2026-11-03T22:00', '2026-11-04T02:00']]), 240);
});

test('S06 : un doublon classé n’est pas compté comme un second fait', () => {
  const a = dem({ equipementId: 'C', etat: 'indisponible', statut: 'traitement_organise' });
  const b = dem({ equipementId: 'C', etat: 'indisponible', statut: 'close_sans_travail', motifClassement: 'doublon de a' });
  assert.equal(ind({ demandes: [a, b] }).repetitives.length, 0);
  const c = dem({ equipementId: 'C', etat: 'degrade', statut: 'traitement_organise' });
  assert.deepEqual(ind({ demandes: [a, b, c] }).repetitives, [['C', 2]]);
});

// ---------- S07 reprise différée, essai échoué ----------
test('S07 : essai échoué (non résolu) sans suite = clôture refusée', () => {
  assert.equal(C.verifierCloture(ot({ nature: 'corrective', resultat: 'non_resolu' })).length, 1);
});

test('S07 : fin d’arrêt inconnue = aucune durée inventée', () => {
  const o = ot({ equipementId: 'P', nature: 'corrective', avecArret: 'oui', arretDebut: '2026-11-03T08:00', arretFin: null });
  const I = ind({ ots: [o] });
  assert.deepEqual(I.arrets, { faits: 1, faitsBornes: 0, dureeConnue: null });
});

test('S07 : fin d’arrêt avant le début refusée', () => {
  assert.equal(C.verifierCloture(ot({ nature: 'corrective', resultat: 'resolu', arretDebut: '2026-11-03T10:00', arretFin: '2026-11-03T09:00' })).length, 1);
});

// ---------- S08 secours ----------
test('S08 : compresseur indisponible mais secouru = équipement indisponible, aucun arrêt de production', () => {
  const d = dem({ equipementId: 'COMP', etat: 'indisponible', impact: 'aucun_constate', statut: 'traitement_organise' });
  const o = ot({ demandeIds: [d.id], equipementId: 'COMP', nature: 'corrective', avecArret: 'non', statut: 'en_cours' });
  assert.equal(C.etatEquipement('COMP', [d], [o]), 'indisponible');
  assert.equal(ind({ demandes: [d], ots: [o] }).arrets.faits, 0);
});

// ---------- divers ----------
test('les OT annulés et hors période sont exclus', () => {
  const I = ind({ ots: [ot({ nature: 'corrective', statut: 'annulee' }), ot({ nature: 'corrective', creeLe: '2026-01-01T08:00' })] });
  assert.equal(I.interventions, 0);
});

test('délai de clôture : médiane création → clôture', () => {
  const I = ind({ ots: [
    ot({ nature: 'corrective', statut: 'cloturee', creeLe: '2026-11-03T08:05', clotureLe: '2026-11-03T11:20' }),
    ot({ nature: 'corrective', statut: 'cloturee', creeLe: '2026-11-03T09:25', clotureLe: '2026-11-03T11:40' })] });
  assert.equal(I.delaiCloture.n, 2);
  assert.equal(I.delaiCloture.mediane, 165);
});
