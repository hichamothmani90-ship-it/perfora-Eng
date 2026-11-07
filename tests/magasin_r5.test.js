// Lot R5 : suivi d'une pièce reliée à une demande d'achat, réservation proposée à l'entrée, urgents, qui commande.
// Lancer : node --test tests/
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../js/calculs.js');

const etapes = (b, achats = [], mvts = []) => C.suiviBesoin(b, achats, mvts).map(e => `${e.cle}${e.fait ? '✓' : ''}`).join(' ');
const b0 = { id: 'b1', articleId: 'a1', qte: 2, otId: 'o1', demandeLe: '2026-11-05T08:00', siteId: 's1' };

test('pièce en stock : demandée → réservée → remise', () => {
  assert.equal(etapes(b0), 'demandee✓ reservee remise');
  assert.equal(etapes({ ...b0, qteReservee: 2 }), 'demandee✓ reservee✓ remise');
  const remise = [{ id: 'm1', type: 'remise', besoinId: 'b1', qte: -2, articleId: 'a1' }];
  assert.equal(etapes(b0, [], remise), 'demandee✓ reservee✓ remise✓');
});

test('pièce indisponible avec délai annoncé seulement', () => {
  assert.equal(etapes({ ...b0, statut: 'indisponible', delai: '2026-11-09' }), 'demandee✓ indisponible✓ livraison reservee remise');
});

test('pièce reliée à une demande d’achat : chaque étape se lit sur la demande', () => {
  const b = { ...b0, statut: 'indisponible', achatId: 'da1', ligneId: 'l1' };
  const da = { id: 'da1', ref: 'DA-K3-0013', statut: 'soumise', lignes: [{ id: 'l1', articleId: 'a1', qte: 2, besoinId: 'b1' }] };
  assert.equal(etapes(b, [da]), 'demandee✓ indisponible✓ achat✓ validee commandee recue reservee remise');
  const cmd = { ...da, statut: 'commandee', valideLe: '2026-11-07', fournisseur: 'Roulements SA', dateCommande: '2026-11-07', livraisonPrevue: '2026-11-09' };
  assert.equal(etapes(b, [cmd]), 'demandee✓ indisponible✓ achat✓ validee✓ commandee✓ livraison recue reservee remise');
  assert.match(C.suiviBesoin(b, [cmd], []).find(e => e.cle === 'commandee').libelle, /Roulements SA/);
  const recu = [{ id: 'm1', type: 'entree', achatId: 'da1', ligneId: 'l1', qte: 2, articleId: 'a1' }];
  assert.equal(etapes({ ...b, qteReservee: 2 }, [cmd], recu), 'demandee✓ indisponible✓ achat✓ validee✓ commandee✓ recue✓ reservee✓ remise');
});

test('achat urgent : pas d’étape « validé » avant la commande ; demande annulée = plus de lien', () => {
  const b = { ...b0, statut: 'indisponible', achatId: 'da1' };
  const da = { id: 'da1', ref: 'DA-1', statut: 'commandee', urgent: true, lignes: [{ id: 'l1', besoinId: 'b1', qte: 2 }] };
  assert.equal(etapes(b, [da]), 'demandee✓ indisponible✓ achat✓ commandee✓ recue reservee remise');
  assert.equal(etapes(b, [{ ...da, statut: 'annulee' }]), 'demandee✓ indisponible✓ reservee remise');
});

test('sans module achats : suivi « commandée » noté sur la pièce', () => {
  const b = { ...b0, statut: 'indisponible', commande: { fournisseur: 'Roulements SA', le: '2026-11-07', livraisonPrevue: '2026-11-09' } };
  assert.equal(etapes(b), 'demandee✓ indisponible✓ commandee✓ livraison reservee remise');
});

test('entrée en stock : pièces en attente de l’article, urgentes puis plus anciennes, reste à réserver', () => {
  const besoins = [
    { id: 'x1', articleId: 'a1', qte: 2, demandeLe: '2026-11-01', statut: 'indisponible', siteId: 's1' },
    { id: 'x2', articleId: 'a1', qte: 1, demandeLe: '2026-11-04', urgent: true, siteId: 's1' },
    { id: 'x3', articleId: 'a1', qte: 3, qteReservee: 1, demandeLe: '2026-10-30', siteId: 's1' },
    { id: 'x4', articleId: 'a1', qte: 1, qteReservee: 1, siteId: 's1' },
    { id: 'x5', articleId: 'a2', qte: 1, siteId: 's1' },
    { id: 'x6', articleId: 'a1', qte: 1, siteId: 's2' },
    { id: 'x7', articleId: 'a1', qte: 1, statut: 'annule', siteId: 's1' }];
  assert.deepEqual(C.besoinsEnAttenteArticle(besoins, [], 'a1', 's1').map(x => `${x.b.id}:${x.reste}`), ['x2:1', 'x3:2', 'x1:2']);
});

test('urgents à valider après coup, et qui peut commander', () => {
  const l = [{ id: 1, urgent: true, statut: 'commandee' }, { id: 2, urgent: true, statut: 'commandee', valideLe: 'x' }, { id: 3, statut: 'soumise' }, { id: 4, urgent: true, statut: 'annulee' }];
  assert.deepEqual(C.urgentsAValider(l).map(a => a.id), [1]);
  assert.equal(C.peutCommander('achats', 'achats'), true);
  assert.equal(C.peutCommander('responsable', 'achats'), true);
  assert.equal(C.peutCommander('magasinier', 'achats'), false);
  assert.equal(C.peutCommander('magasinier', 'magasinier'), true);
  assert.equal(C.peutCommander('technicien', 'magasinier'), false);
});

test('technicien sans accès aux achats : le résumé recopié sur la pièce suffit', () => {
  const b = { ...b0, statut: 'indisponible', achatId: 'da1', suiviAchat: { achatId: 'da1', ligneId: 'l1', ref: 'DA-1', statut: 'commandee', fournisseur: 'Roulements SA', livraisonPrevue: '2026-11-09', valideLe: '2026-11-07' } };
  assert.equal(etapes(b), 'demandee✓ indisponible✓ achat✓ validee✓ commandee✓ livraison recue reservee remise');
  const recu = [{ id: 'm1', type: 'entree', achatId: 'da1', ligneId: 'l1', qte: 2, articleId: 'a1' }];
  assert.equal(etapes({ ...b, qteReservee: 2 }, [], recu), 'demandee✓ indisponible✓ achat✓ validee✓ commandee✓ recue✓ reservee✓ remise');
});
