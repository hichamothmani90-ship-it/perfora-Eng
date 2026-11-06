// Volet D — énergie et eau : scénarios V3 §37 (index remplacé, période chevauchante, mesure instantanée, relevé suspect,
// facture du 15 au 15, bilan combustible, sous-comptages) et cas limites.
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../js/calculs.js');

const ELEC = { id: 'c-elec', unite: 'kWh', mode: 'cumulatif', coefficient: 1, frequenceJours: 7 };
let n = 0;
const rel = (compteurId, le, valeur, o = {}) => ({ id: 'r' + (++n), compteurId, le, valeur, ...o });
const e = (le, v, o) => rel(ELEC.id, le, v, o);
const statuts = a => a.lignes.map(l => l.statut);

test('cumulatif : consommation = (index fin − index début) × coefficient', () => {
  const c = { ...ELEC, coefficient: 40 };
  const r = [e('2026-11-01T08:00', 1000), e('2026-11-08T08:00', 1025)];
  assert.deepEqual(C.analyserReleves(c, r).segments, [{ debut: '2026-11-01T08:00', fin: '2026-11-08T08:00', quantite: 1000, estime: false }]);
});

test('V3 §37 : index remplacé → les tronçons s’additionnent, aucune fausse « baisse d’index »', () => {
  const r = [e('2026-11-01T08:00', 12000), rel(ELEC.id, '2026-11-05T10:00', null, { nature: 'rupture', indexFinal: 12500, indexInitial: 0, motif: 'Compteur remplacé' }),
    e('2026-11-08T08:00', 300)];
  const a = C.analyserReleves(ELEC, r);
  assert.deepEqual(statuts(a), ['retenu', 'rupture', 'retenu']);
  assert.equal(a.segments.reduce((t, s) => t + s.quantite, 0), 800, '500 sur l’ancien compteur + 300 sur le nouveau');
  const sansRupture = C.analyserReleves(ELEC, [e('2026-11-01T08:00', 12000), e('2026-11-08T08:00', 300)]);
  assert.deepEqual(sansRupture.lignes[1].anomalies, ['baisse_index'], 'sans rupture déclarée, la baisse est signalée');
  assert.equal(sansRupture.lignes[1].confirmable, false, 'une baisse d’index ne se « confirme » pas : on déclare une rupture');
  assert.equal(sansRupture.segments.length, 0);
});

test('rupture sans index connu : la série repart au relevé suivant, le trou reste visible', () => {
  const r = [e('2026-11-01T00:00', 100), rel(ELEC.id, '2026-11-04T00:00', null, { nature: 'rupture' }), e('2026-11-06T00:00', 50), e('2026-11-11T00:00', 80)];
  const p = C.consommationPeriode(ELEC, r, '2026-11-01', '2026-11-10');
  assert.equal(p.quantite, 30, 'seul le tronçon connu 50 → 80 est compté');
  assert.equal(p.complet, false);
});

test('changement de coefficient : chaque tronçon garde son coefficient', () => {
  const r = [e('2026-11-01T08:00', 100), rel(ELEC.id, '2026-11-03T08:00', null, { nature: 'rupture', indexFinal: 110, indexInitial: 110, coefficient: 2 }), e('2026-11-05T08:00', 120)];
  assert.deepEqual(C.analyserReleves(ELEC, r).segments.map(s => s.quantite), [10, 20]);
});

test('V3 §37 : période chevauchante → relevé signalé et exclu', () => {
  const eau = { id: 'c-eau', unite: 'm³', mode: 'periode' };
  const r = [rel('c-eau', '2026-11-10T00:00', 30, { debut: '2026-11-01' }), rel('c-eau', '2026-11-20T00:00', 25, { debut: '2026-11-08' }),
    rel('c-eau', '2026-11-30T00:00', 28)];
  const a = C.analyserReleves(eau, r);
  assert.deepEqual(statuts(a), ['retenu', 'suspect', 'retenu']);
  assert.deepEqual(a.lignes[1].anomalies, ['chevauchement']);
  assert.deepEqual(a.segments.map(s => [s.debut, s.quantite]), [['2026-11-01T00:00', 30], ['2026-11-10T00:00', 28]], 'sans début, la période part du relevé précédent retenu');
});

test('V3 §37 : mesure instantanée → jamais additionnée', () => {
  const t = { id: 'c-temp', unite: '°C', mode: 'instantane' };
  const r = [rel('c-temp', '2026-11-02T08:00', 4), rel('c-temp', '2026-11-03T08:00', 6), rel('c-temp', '2026-11-04T08:00', 5)];
  const p = C.consommationPeriode(t, r, '2026-11-01', '2026-11-30');
  assert.equal(p.quantite, null);
  assert.deepEqual([p.nb, p.min, p.max, p.derniere], [3, 4, 6, 5]);
});

test('V3 §37 : relevé suspect (variation inhabituelle) → gardé, exclu, puis confirmé par le responsable', () => {
  const base = [e('2026-11-01T08:00', 0), e('2026-11-02T08:00', 100), e('2026-11-03T08:00', 200), e('2026-11-04T08:00', 300)];
  const pic = e('2026-11-05T08:00', 1300);
  let a = C.analyserReleves(ELEC, [...base, pic]);
  assert.equal(a.lignes[4].statut, 'suspect');
  assert.deepEqual(a.lignes[4].anomalies, ['variation']);
  assert.equal(a.lignes[4].confirmable, true);
  assert.equal(a.segments.length, 3, 'le suspect n’entre pas dans les calculs');
  assert.equal(C.consommationPeriode(ELEC, [...base, pic], '2026-11-01', '2026-11-30').suspects, 1);
  a = C.analyserReleves(ELEC, [...base, { ...pic, decision: 'confirme' }]);
  assert.equal(a.lignes[4].statut, 'retenu');
  assert.equal(a.segments.at(-1).quantite, 1000);
  a = C.analyserReleves(ELEC, [...base, { ...pic, decision: 'invalide' }, e('2026-11-06T08:00', 400)]);
  assert.deepEqual(statuts(a).slice(4), ['invalide', 'retenu']);
  assert.equal(a.segments.at(-1).quantite, 100, 'après invalidation, la série reprend depuis le dernier retenu');
});

test('correction : le nouveau relevé remplace l’ancien, l’historique reste', () => {
  const faux = e('2026-11-08T08:00', 10250);
  const r = [e('2026-11-01T08:00', 10000), faux, e('2026-11-08T08:05', 10025, { remplaceId: faux.id })];
  const a = C.analyserReleves(ELEC, r);
  assert.deepEqual(statuts(a), ['retenu', 'remplace', 'retenu']);
  assert.equal(a.segments[0].quantite, 25);
});

test('contrôles : doublon, unité, valeur illisible, date future', () => {
  const r = [e('2026-11-01T08:00', 10), e('2026-11-01T08:00', 10), e('2026-11-02T08:00', 12, { unite: 'm³' }), e('2026-11-03T08:00', 'abc'), e('2026-12-01T08:00', 20)];
  const a = C.analyserReleves(ELEC, r, { maintenant: '2026-11-06T12:00' });
  assert.deepEqual(a.lignes.map(l => l.anomalies), [[], ['doublon'], ['unite'], ['valeur_invalide'], ['date_future']]);
});

test('couverture : aucune interpolation silencieuse ; le prorata n’existe que demandé et reste « estimé »', () => {
  const r = [e('2026-10-28T00:00', 0), e('2026-11-04T00:00', 70), e('2026-11-25T00:00', 280), e('2026-12-02T00:00', 350)];
  const p = C.consommationPeriode(ELEC, r, '2026-11-01', '2026-11-30');
  assert.deepEqual([p.quantite, p.couvertureJours, p.periodeJours, p.complet, p.segmentsPartiels, p.estime], [210, 21, 30, false, 2, false]);
  const pr = C.consommationPeriode(ELEC, r, '2026-11-01', '2026-11-30', { prorata: true });
  assert.deepEqual([pr.quantite, pr.couvertureJours, pr.complet, pr.estime], [300, 30, true, true]);
  assert.equal(C.consommationPeriode(ELEC, [], '2026-11-01', '2026-11-30').quantite, null, 'aucun relevé : non mesuré, pas zéro');
});

test('V3 §37 : facture du 15 au 15 → rapprochement sur l’intervalle exact, pas sur le mois civil', () => {
  const r = [e('2026-10-15T09:00', 1000), e('2026-11-01T09:00', 1500), e('2026-11-15T10:00', 2000), e('2026-11-30T09:00', 2600)];
  const f = { du: '2026-10-15', au: '2026-11-15', quantite: 1010, unite: 'kWh', compteurIds: [ELEC.id] };
  const ok = C.rapprochementFacture(f, [ELEC], r);
  assert.deepEqual([ok.statut, ok.mesure, ok.ecart, ok.ecartPct], ['concordant', 1000, 10, 1]);
  assert.equal(C.rapprochementFacture({ ...f, quantite: 1200 }, [ELEC], r).statut, 'ecart');
  const novembre = C.consommationPeriode(ELEC, r, '2026-11-01', '2026-11-30');
  assert.equal(novembre.quantite, 1100, 'le mois civil donne un autre chiffre, à ne pas comparer à la facture');
  const trou = C.rapprochementFacture(f, [ELEC], r.filter(x => x.le !== '2026-11-15T10:00'));
  assert.deepEqual([trou.statut, trou.ecart, trou.details[0].manque], ['incomplet', null, 'fin'], 'borne sans relevé : incomplet, jamais un écart certain');
  assert.equal(C.rapprochementFacture({ ...f, unite: 'm³' }, [ELEC], r).statut, 'unites_differentes');
});

test('V3 §37 : bilan combustible 1 000 + 2 000 − 800 = 2 200 L sortis', () => {
  const b = C.bilanCombustible({ unite: 'L', stockInitial: 1000, livraisons: [{ quantite: 2000, unite: 'L' }], stockFinal: 800, usageMesure: 2100 });
  assert.deepEqual([b.sorti, b.incoherent, b.ecartUsage], [2200, false, 100]);
  assert.deepEqual(C.bilanCombustible({ unite: 'L', stockInitial: 1000, stockFinal: null }).manque, ['stock_final']);
  assert.equal(C.bilanCombustible({ unite: 'L', stockInitial: 1, stockFinal: 0, livraisons: [{ quantite: 5, unite: 'kg' }] }).erreur, 'unites');
  const t = C.bilanCombustible({ unite: 'L', stockInitial: 500, stockFinal: 300, transfertsEntrants: [{ quantite: 100 }], transfertsSortants: [{ quantite: 50 }] });
  assert.equal(t.sorti, 250);
});

test('V3 §37 : sous-comptages → résidu « à expliquer », jamais additionné au principal', () => {
  const P = { id: 'p', unite: 'm³', mode: 'cumulatif' }, S1 = { id: 's1', unite: 'm³', mode: 'cumulatif' }, S2 = { id: 's2', unite: 'm³', mode: 'cumulatif' };
  const j = (id, a, b) => [rel(id, '2026-11-01T08:00', a), rel(id, '2026-11-29T08:00', b)];
  const r = [...j('p', 0, 1000), ...j('s1', 0, 600), ...j('s2', 0, 300)];
  const x = C.residuSousComptage(P, [S1, S2], r, '2026-11-01', '2026-11-30');
  assert.deepEqual([x.statut, x.residu, x.residuPct], ['a_expliquer', 100, 10]);
  const y = C.residuSousComptage(P, [S1, S2], [...j('p', 0, 1000), ...j('s1', 0, 700), ...j('s2', 0, 400)], '2026-11-01', '2026-11-30');
  assert.equal(y.statut, 'incoherent', 'sous-compteurs > principal : vérifier les compteurs');
  const z = C.residuSousComptage(P, [S1, S2], [...j('p', 0, 1000), ...j('s1', 0, 600)], '2026-11-01', '2026-11-30');
  assert.equal(z.statut, 'non_comparable', 'un sous-compteur sans relevé : pas de résidu');
  assert.deepEqual(C.residuSousComptage(P, [{ ...S2, unite: 'kWh' }], r, '2026-11-01', '2026-11-30').horsUnite, ['s2']);
});

test('totaux par unité : jamais d’addition entre unités ; non mesuré ≠ zéro', () => {
  const t = C.totauxParUnite([{ ressource: 'electricite', unite: 'kWh', quantite: 100 }, { ressource: 'electricite', unite: 'kWh', quantite: 50 },
    { ressource: 'eau', unite: 'm³', quantite: 12 }, { ressource: 'eau', unite: 'm³', quantite: null }]);
  assert.deepEqual(t, [{ ressource: 'electricite', unite: 'kWh', quantite: 150, nonMesures: 0 }, { ressource: 'eau', unite: 'm³', quantite: 12, nonMesures: 1 }]);
});

test('relevés à faire : fréquence en jours, jamais relevé = dû, inactif ignoré', () => {
  const A = { id: 'a', frequenceJours: 7 }, B = { id: 'b', frequenceJours: 30 }, N = { id: 'n', frequenceJours: 1 }, X = { id: 'x', frequenceJours: 1, actif: false };
  const r = [rel('a', '2026-10-28T08:00', 1), rel('b', '2026-11-01T08:00', 1)];
  const d = C.relevesDus([A, B, N, X], r, '2026-11-06');
  assert.deepEqual(d.map(x => [x.compteur.id, x.retardJours]), [['a', 2], ['n', 0]]);
});

test('coûts : montants par devise, montant inconnu compté à part', () => {
  assert.deepEqual(C.totalFactures([{ montantHT: 1200.5 }, { montantHT: 300, devise: 'MAD' }, { montantHT: null }]), { parDevise: { MAD: 1500.5 }, sansMontant: 1 });
});
