// Volet C — stocks, réapprovisionnement et achats : scénarios V3 §14, §16, §18, §37 et cas limites.
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../js/calculs.js');

const A = { id: 'art-filtre', designation: 'Filtre', stockMin: 0, actif: true }, S1 = 'site-1', S2 = 'site-2';
let n = 0;
const mv = o => ({ id: 'm' + (++n), articleId: A.id, siteId: S1, ...o });
const entree = (q, le = '2026-11-01T08:00', o = {}) => mv({ type: 'entree', qte: q, le, ...o });
const seuil = o => ({ id: 's' + (++n), articleId: A.id, siteId: S1, statut: 'valide', securite: 2, pointCommande: 8, cible: 14, valideLe: '2026-11-01T08:00', ...o });
const commande = (lignes, o = {}) => ({ id: 'ach' + (++n), siteId: S1, statut: 'commandee', lignes, ...o });

test('V3 §37 : 10 commandées, 6 reçues dont 1 isolée → 5 utilisables, 1 isolée, 4 attendues', () => {
  const a = commande([{ id: 'l1', articleId: A.id, qteCommandee: 10 }]);
  const m = [entree(5, '2026-11-05T10:00', { achatId: a.id, ligneId: 'l1' }), mv({ type: 'isolement', qte: 0, quantite: 1, achatId: a.id, ligneId: 'l1', motif: 'Endommagée' })];
  assert.deepEqual(C.receptionLigne(a, a.lignes[0], m), { commande: 10, recu: 6, utilisable: 5, isole: 1, reliquat: 4 });
  assert.equal(C.stockPhysique(m, A.id, S1), 5, 'l’isolé n’est pas dans le stock utilisable');
  assert.equal(C.qteIsolee(m, A.id, S1), 1);
  assert.equal(C.qteEnCommande([a], m, A.id, S1), 4, 'seul le reliquat est « en commande »');
  assert.equal(C.etatAchat(a, m), 'partiellement_recue');
});

test('pièce isolée : libérée → stock utilisable ; retour fournisseur → sort de l’isolé sans entrer en stock', () => {
  const iso = mv({ type: 'isolement', qte: 0, quantite: 2 });
  let m = [iso, mv({ type: 'liberation', qte: 1, isolementId: iso.id })];
  assert.equal(C.stockPhysique(m, A.id, S1), 1);
  assert.equal(C.qteIsolee(m, A.id, S1), 1);
  m = [...m, mv({ type: 'disposition', qte: 0, quantite: 1, isolementId: iso.id, decision: 'retour_fournisseur' })];
  assert.equal(C.qteIsolee(m, A.id, S1), 0);
  assert.equal(C.stockPhysique(m, A.id, S1), 1);
});

test('commande soldée ou entièrement reçue : plus rien en commande ; état « reçue »', () => {
  const a = commande([{ id: 'l1', articleId: A.id, qteCommandee: 4 }, { id: 'l2', articleId: 'autre', qteCommandee: 3, solde: true }]);
  const m = [entree(4, '2026-11-05T10:00', { achatId: a.id, ligneId: 'l1' })];
  assert.equal(C.qteEnCommande([a], m, A.id, S1), 0);
  assert.equal(C.etatAchat(a, m), 'recue');
  assert.equal(C.etatAchat({ ...a, statut: 'validee' }, m), 'validee', 'avant la commande, l’état est celui saisi');
  assert.equal(C.qteEnCommande([{ ...a, statut: 'validee', lignes: [{ id: 'l9', articleId: A.id, qte: 5 }] }], [], A.id, S1), 0, 'une demande validée n’est pas encore en commande');
});

test('V3 §14 : seuil actif = dernière version validée ; une proposition ne compte pas ; repère provisoire stockMin', () => {
  const S = [seuil({ pointCommande: 6, valideLe: '2026-10-01T08:00' }), seuil({ pointCommande: 8, valideLe: '2026-11-01T08:00' }), seuil({ statut: 'propose', pointCommande: 20, valideLe: null })];
  assert.equal(C.seuilActif(S, A, S1).pointCommande, 8);
  assert.equal(C.seuilActif(S, A, S2), null, 'seuil par site');
  const p = C.seuilActif([], { ...A, stockMin: 3 }, S1);
  assert.equal(p.provisoire, true);
  assert.equal(p.pointCommande, 3);
  assert.equal(C.seuilActif([], A, S1), null, 'sans seuil ni mini : pas d’alerte');
});

test('V3 §14 : alerte sur disponible + en commande − besoins non couverts, sans double compte ; ne commande rien', () => {
  const D = {
    articles: [A], seuils: [seuil()],
    mouvements: [entree(10), mv({ type: 'remise', qte: -1, besoinId: 'b1' })],
    besoins: [
      { id: 'b1', articleId: A.id, siteId: S1, qte: 3, qteReservee: 3, statut: 'reserve' }, // 1 remis, 2 encore réservés
      { id: 'b2', articleId: A.id, siteId: S1, qte: 2, statut: 'demande' },                 // non couvert
      { id: 'b3', articleId: A.id, siteId: S1, qte: 5, statut: 'annule' }],
    achats: [commande([{ id: 'l1', articleId: A.id, qteCommandee: 3 }])],
  };
  const s = C.situationArticle(D, A, S1);
  assert.equal(s.physique, 9);
  assert.equal(s.reserve, 2);
  assert.equal(s.disponible, 7);
  assert.equal(s.nonCouverts, 2, 'la partie réservée du besoin b1 n’est pas recomptée');
  assert.equal(s.enCommande, 3);
  assert.equal(s.couverture, 8, '7 − 2 + 3');
  assert.equal(s.alerte, false, 'couverture = point de commande : pas d’alerte');
  D.besoins.push({ id: 'b4', articleId: A.id, siteId: S1, qte: 1, statut: 'demande' });
  const r = C.aReapprovisionner(D, S1);
  assert.equal(r.length, 1);
  assert.equal(r[0].proposee, 7, 'cible 14 − couverture 7');
});

test('récapitulatif trié : rupture d’abord, puis article critique, puis écart au seuil', () => {
  const art = id => ({ id, designation: id, actif: true });
  const D = {
    articles: [art('x-ecart'), art('x-critique'), art('x-rupture'), art('x-ok')],
    seuils: [
      seuil({ articleId: 'x-ecart', pointCommande: 10, cible: 10 }),
      seuil({ articleId: 'x-critique', pointCommande: 4, cible: 4, critique: true }),
      seuil({ articleId: 'x-rupture', pointCommande: 2, cible: 2 }),
      seuil({ articleId: 'x-ok', pointCommande: 1, cible: 1 })],
    mouvements: [mv({ articleId: 'x-ecart', type: 'entree', qte: 1 }), mv({ articleId: 'x-critique', type: 'entree', qte: 3 }), mv({ articleId: 'x-ok', type: 'entree', qte: 5 })],
    besoins: [], achats: [],
  };
  assert.deepEqual(C.aReapprovisionner(D, S1).map(x => x.article.id), ['x-rupture', 'x-critique', 'x-ecart']);
});

test('V3 §18 / §37 : CUMP 10 à 100 puis 10 à 120 = 110 ; remise figée à 220 ; retour réintégré à sa valeur de sortie', () => {
  const e1 = entree(10, '2026-11-01T08:00'), e2 = entree(10, '2026-11-02T08:00');
  const rem = mv({ type: 'remise', qte: -2, besoinId: 'b1', le: '2026-11-03T08:00' });
  const ret = mv({ type: 'retour', qte: 1, besoinId: 'b1', le: '2026-11-04T08:00' });
  const V = [{ mouvementId: e1.id, prixUnitaire: 100, devise: 'MAD', statut: 'connu' }, { mouvementId: e2.id, prixUnitaire: 120, devise: 'MAD', statut: 'connu' }];
  let r = C.valorisation([e1, e2], V, A.id, S1);
  assert.equal(r.cump, 110);
  r = C.valorisation([e1, e2, rem, ret], V, A.id, S1);
  assert.equal(r.couts.get(rem.id) * 2, 220, 'valeur de la remise figée');
  assert.equal(r.couts.get(ret.id), 110, 'retour à sa valeur de sortie, pas au dernier prix');
  assert.equal(r.quantite, 19);
  assert.equal(r.cump, 110);
  // une pièce utilisée sur deux remises : coût consommé 110, pas de second débit
  assert.equal(C.coutConsomme({ id: 'b1', qte: 2 }, [rem, ret], [{ besoinId: 'b1', qte: 1 }], r.couts), 110);
});

test('V3 §18 : une livraison postérieure ne réécrit pas le coût d’une sortie passée', () => {
  const e1 = entree(10, '2026-11-01T08:00'), s = mv({ type: 'sortie', qte: -1, otId: 'o', le: '2026-11-02T08:00' }), e2 = entree(10, '2026-11-03T08:00');
  const V = [{ mouvementId: e1.id, prixUnitaire: 100 }, { mouvementId: e2.id, prixUnitaire: 200 }];
  const r = C.valorisation([e2, s, e1], V, A.id, S1);
  assert.equal(r.couts.get(s.id), 100);
  assert.equal(Math.round(r.cump * 100) / 100, Math.round((900 + 2000) / 19 * 100) / 100);
});

test('V3 §18 : prix absent jamais assimilé à zéro ; autre devise sans conversion = non valorisé ; provisoire signalé', () => {
  const e1 = entree(10, '2026-11-01T08:00'), e2 = entree(5, '2026-11-02T08:00'), e3 = entree(2, '2026-11-03T08:00'), e4 = entree(1, '2026-11-04T08:00');
  const V = [{ mouvementId: e1.id, prixUnitaire: 100 }, { mouvementId: e3.id, prixUnitaire: 30, devise: 'EUR' }, { mouvementId: e4.id, prixUnitaire: 100, statut: 'provisoire' }];
  const r = C.valorisation([e1, e2, e3, e4], V, A.id, S1);
  assert.equal(r.cump, 100, 'le CUMP ne baisse pas à cause des quantités sans prix');
  assert.equal(r.quantiteNonValorisee, 7);
  assert.equal(r.incomplet, true);
  assert.equal(r.provisoire, true);
  assert.equal(r.couts.get(e2.id), null);
  assert.equal(C.prixMAD({ prixUnitaire: 30, devise: 'EUR', prixUnitaireMAD: 325 }), 325, 'conversion explicite acceptée');
  assert.equal(C.prixMAD({ prixUnitaire: 0 }), 0, 'un prix saisi à 0 (gratuit) reste distinct d’un prix absent');
  assert.equal(C.prixMAD(null), null);
});

test('valorisation par site : le stock d’un site ne valorise pas l’autre ; pièce libérée valorisée au prix de sa réception', () => {
  const e1 = entree(4, '2026-11-01T08:00'), e2 = mv({ type: 'entree', qte: 4, siteId: S2, le: '2026-11-01T08:00' });
  const iso = mv({ type: 'isolement', qte: 0, quantite: 1, le: '2026-11-01T08:00' }), lib = mv({ type: 'liberation', qte: 1, isolementId: iso.id, le: '2026-11-02T08:00' });
  const V = [{ mouvementId: e1.id, prixUnitaire: 50 }, { mouvementId: e2.id, prixUnitaire: 80 }, { mouvementId: iso.id, prixUnitaire: 50 }];
  assert.equal(C.valorisation([e1, e2, iso, lib], V, A.id, S1).cump, 50);
  assert.equal(C.valorisation([e1, e2, iso, lib], V, A.id, S1).quantite, 5);
  assert.equal(C.valorisation([e1, e2], V, A.id, S2).cump, 80);
});

test('V3 §14 : aide au seuil — 2 par semaine × 3 semaines de délai + 2 de sécurité = 8 (indicatif)', () => {
  const m = [];
  for (let s = 0; s < 12; s++) m.push(mv({ type: 'remise', qte: -2, le: C.addDays('2026-11-06', -7 * s - 1) + 'T09:00' }));
  m.push(mv({ type: 'retour', qte: 1, le: '2026-11-05T09:00' }), mv({ type: 'remise', qte: -50, le: '2026-01-01T09:00' }));
  const c = C.consommationHebdo(m, A.id, S1, '2026-11-06', 84);
  assert.equal(Math.round(c * 100) / 100, Math.round(23 / 12 * 100) / 100, 'retours déduits, hors période exclue');
  assert.equal(C.seuilIndicatif(2, 21, 2), 8);
  assert.equal(C.consommationHebdo([], A.id, S1, '2026-11-06'), 0);
});

test('montant commandé : lignes sans prix comptées à part, jamais à zéro', () => {
  const a = { lignes: [{ qteCommandee: 10, prixUnitaire: 100 }, { qte: 2, prixUnitaire: 50, devise: 'MAD' }, { qteCommandee: 3 }, { qteCommandee: 1, prixUnitaire: 20, devise: 'EUR' }] };
  assert.deepEqual(C.montantCommande(a), { montant: 1100, sansPrix: 2, complet: false });
  assert.equal(C.montantCommande({ lignes: [] }).complet, true);
});

test('isolements en attente : décisions partielles déduites, isolement soldé retiré', () => {
  const i1 = mv({ type: 'isolement', qte: 0, quantite: 3, le: '2026-11-02T08:00' }), i2 = mv({ type: 'isolement', qte: 0, quantite: 1, le: '2026-11-01T08:00' });
  const m = [i1, i2, mv({ type: 'liberation', qte: 1, isolementId: i1.id }), mv({ type: 'disposition', qte: 0, quantite: 1, isolementId: i1.id, decision: 'rebut' }),
    mv({ type: 'disposition', qte: 0, quantite: 1, isolementId: i2.id, decision: 'retour_fournisseur' })];
  assert.deepEqual(C.isolementsEnAttente(m).map(x => [x.m.id, x.reste]), [[i1.id, 1]]);
});
