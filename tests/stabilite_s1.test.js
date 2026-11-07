// Lot S1 : listes fusionnées élément par élément (même règle que supabase/stabilite_s1.sql et le serveur factice).
// Lancer : node --test tests/
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../js/calculs.js');

/** Ce que fait le serveur : patch fusionné puis appliqué champ par champ. */
const serveur = (d, patch) => ({ ...d, ...C.fusionPatch(d, patch) });
/** Ce que l'appareil envoie : la nouvelle liste et la description de ses changements. */
const envoi = (avant, apres, champ) => ({ [champ]: apres[champ], $listes: { [champ]: C.decrireListe(avant[champ], apres[champ]) } });

test('description : ajoutés / modifiés et retirés', () => {
  const a = [{ id: 'i1', n: 1 }, { id: 'i2', n: 1 }], b = [{ id: 'i2', n: 2 }, { id: 'i3', n: 1 }];
  assert.deepEqual(C.decrireListe(a, b), { modifies: ['i2', 'i3'], retraits: ['i1'] });
  assert.deepEqual(C.decrireListe(['diagnostic'], ['diagnostic', 'essai']), { modifies: ['essai'], retraits: [] });
  assert.equal(C.decrireListe([{ v: 1 }], [{ v: 2 }]), null);   // éléments sans id : pas de fusion
});

test('deux appareils ajoutent chacun un intervenant : les deux restent', () => {
  const base = { intervenants: [] };
  const tech = { intervenants: [{ id: 'i1', personneId: 't' }] }, resp = { intervenants: [{ id: 'i2', personneId: 'r' }] };
  let srv = serveur(base, envoi(base, tech, 'intervenants'));
  srv = serveur(srv, envoi(base, resp, 'intervenants'));
  assert.deepEqual(srv.intervenants.map(x => x.id), ['i1', 'i2']);
});

test('retrait sur un appareil, ajout sur l’autre : pas de résurrection', () => {
  const base = { intervenants: [{ id: 'i1' }, { id: 'i2' }] };
  let srv = serveur(base, envoi(base, { intervenants: [{ id: 'i2' }] }, 'intervenants'));
  srv = serveur(srv, envoi(base, { intervenants: [{ id: 'i1' }, { id: 'i2' }, { id: 'i3' }] }, 'intervenants'));
  assert.deepEqual(srv.intervenants.map(x => x.id), ['i2', 'i3']);
});

test('même élément modifié des deux côtés : le dernier gagne, le reste est gardé', () => {
  const base = { pieces: [{ id: 'p1', qte: 1 }, { id: 'p2', qte: 1 }] };
  let srv = serveur(base, envoi(base, { pieces: [{ id: 'p1', qte: 2 }, { id: 'p2', qte: 1 }] }, 'pieces'));
  srv = serveur(srv, envoi(base, { pieces: [{ id: 'p1', qte: 3 }, { id: 'p2', qte: 1 }, { id: 'p3', qte: 1 }] }, 'pieces'));
  assert.deepEqual(srv.pieces, [{ id: 'p1', qte: 3 }, { id: 'p2', qte: 1 }, { id: 'p3', qte: 1 }]);
});

test('ancienne appli (liste complète, sans description) : tout est ajouté, rien n’est retiré', () => {
  const srv = serveur({ activites: ['diagnostic', 'reglage'] }, { activites: ['essai'] });
  assert.deepEqual(srv.activites, ['diagnostic', 'reglage', 'essai']);
});

test('liste sans identifiant ou champ absent : remplacée telle quelle, « $listes » jamais gardé', () => {
  assert.deepEqual(serveur({ mesures: [{ v: 1 }] }, { mesures: [{ v: 2 }] }).mesures, [{ v: 2 }]);
  const r = serveur({}, { activites: ['essai'], $listes: { activites: { modifies: ['essai'], retraits: [] } } });
  assert.deepEqual(r, { activites: ['essai'] });
});
