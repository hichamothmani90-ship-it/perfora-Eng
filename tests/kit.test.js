// Kit de démarrage → fiches : conversion, références par code, erreurs ligne par ligne, valeurs inconnues jamais à 0.
const test = require('node:test');
const assert = require('node:assert/strict');
const Kit = require('../js/kit.js');
const C = require('../js/calculs.js');

let n = 0;
const ctx = (o = {}) => ({ sites: [{ id: 's-tng', code: 'TNG' }, { id: 's-cas', code: 'CAS' }], existants: {}, classes: ['ROT-COMPR', 'ROT-POMPE', 'ELE-MOTEUR'],
  aujourdhui: '2026-11-10', lot: 'lot-1', uid: () => 'id' + (++n), par: 'Admin', ...o });
const L = (ligne, o) => ({ _ligne: ligne, ...o });
const KIT = () => ({
  'Lieux': [
    L(5, { 'Code site': 'TNG', 'Code lieu': 'EX-ATL-B', 'Nom du lieu': 'Atelier B' }),                 // exemple ignoré
    L(6, { 'Code site': 'TNG', 'Code lieu': 'ATL-B', 'Nom du lieu': 'Atelier B', 'Code du lieu parent': 'BAT-1' }),  // parent plus bas
    L(7, { 'Code site': 'tng', 'Code lieu': 'bat-1', 'Nom du lieu': 'Bâtiment 1' }),
    L(8, {}),                                                                                          // ligne vide
  ],
  'Équipements': [
    L(6, { 'Code équipement': 'CMP-01', 'Désignation': 'Compresseur', 'Code site': 'TNG', 'Code lieu': 'ATL-B', 'Classe': 'ROT-COMPR · Compresseur', 'Criticité': 'A · critique', 'Contrôle réglementaire': 'Appareil à pression', 'Année de mise en service': 2019, 'Fin de garantie': 46387 }),
    L(7, { 'Code équipement': 'MOT-01', 'Désignation': 'Moteur compresseur', 'Code site': 'TNG', 'Code lieu': 'ATL-B', 'Code équipement parent': 'CMP-01', 'Classe': 'ELE-MOTEUR · Moteur électrique', 'Statut': 'En secours' }),
  ],
  'Compteurs': [
    L(6, { 'Code compteur': 'HRS-CMP01', 'Libellé': 'Heures compresseur', 'Usage': 'Équipement', 'Code site': 'TNG', 'Code équipement': 'CMP-01', 'Unité': 'h', 'Type': 'Cumulatif (index)', 'Fréquence de relevé (jours)': 7, 'Dernier index connu': 12300, 'Date du dernier index': '05/11/2026' }),
    L(7, { 'Code compteur': 'EL-GEN', 'Libellé': 'Arrivée générale', 'Usage': 'Ressource', 'Code site': 'TNG', 'Ressource': 'Électricité', 'Unité': 'kWh', 'Type': 'Cumulatif (index)', 'Coefficient': 40, 'Fréquence de relevé (jours)': 7 }),
    L(8, { 'Code compteur': 'EL-ATL', 'Libellé': 'Atelier B', 'Usage': 'Ressource', 'Code site': 'TNG', 'Ressource': 'Électricité', 'Unité': 'kWh', 'Type': 'Cumulatif (index)', 'Code compteur parent': 'EL-GEN', 'Fréquence de relevé (jours)': 7 }),
  ],
  'Fournisseurs': [L(6, { 'Nom': 'Atlas Copco Maroc', 'Délai habituel (jours)': 10 })],
  'Articles': [
    L(6, { 'Référence': 'FIL-15', 'Désignation': 'Filtre à air', 'Unité': 'u', 'Code site': 'TNG', 'Emplacement': 'A3-02', 'Stock actuel': 4, 'Prix unitaire HT (MAD)': 310, 'Article critique': 'Oui', 'Fournisseur habituel': 'atlas copco maroc', 'Code équipement concerné': 'CMP-01' }),
    L(7, { 'Référence': 'FIL-15', 'Désignation': 'Filtre à air', 'Unité': 'u', 'Code site': 'CAS', 'Stock actuel': 2 }),            // même article, autre site, sans prix
    L(8, { 'Référence': 'HUILE', 'Désignation': 'Huile compresseur', 'Unité': 'L', 'Code site': 'TNG', 'Unité d’achat': 'bidon', 'Contenu de l’unité d’achat': 20 }),  // stock inconnu
  ],
  'Préventif': [
    L(6, { 'Code équipement': 'CMP-01', 'Opération': 'Vidange', 'Type': 'Entretien', 'Tous les … jours': 180, 'Code compteur': 'HRS-CMP01', 'Toutes les … (unité du compteur)': 500, 'Règle': 'Après réalisation', 'Dernière réalisation': '01/09/2026', 'Index à la dernière réalisation': 12000 }),
    L(7, { 'Code équipement': 'CMP-01', 'Opération': 'Épreuve appareil à pression', 'Type': 'Vérification externe', 'Tous les … jours': 365 }),
  ],
  'Personnes': [
    L(6, { 'Nom': 'Karim Alaoui', 'E-mail': 'Karim.Alaoui@exemple.ma', 'Rôle': 'Technicien', 'Codes sites': 'TNG, CAS' }),
    L(7, { 'Nom': 'Sous-traitant froid', 'Rôle': 'Prestataire', 'Codes sites': 'TNG', 'Société (prestataire)': 'FroidPlus' }),
  ],
});

test('kit complet : fiches reliées par code, aucune erreur', () => {
  const r = Kit.convertir(KIT(), ctx());
  assert.deepEqual(r.erreurs, []);
  assert.deepEqual(r.resume, { localisations: 2, equipements: 2, compteurs: 3, releves: 1, fournisseurs: 1, articles: 2, mouvements: 2, valorisations: 1, programmes: 2, personnes: 2 });
  const by = t => r.fiches.filter(f => f.type === t).map(f => f.data);
  const [atl, bat] = by('localisations');
  assert.equal(atl.parentId, bat.id, 'parent déclaré plus bas dans le fichier');
  assert.equal(bat.code, 'BAT-1', 'codes en majuscules');
  const [cmp, mot] = by('equipements');
  assert.deepEqual([cmp.classe, cmp.criticite, cmp.reglementaire, cmp.finGarantie, cmp.localisationId], ['ROT-COMPR', 'A', 'pression', '2026-12-31', atl.id]);
  assert.deepEqual([mot.parentId, mot.statut, mot.actif], [cmp.id, 'secours', true]);
  const [hrs, gen, sub] = by('compteurs');
  assert.deepEqual([hrs.usage, hrs.equipementId, hrs.mode], ['equipement', cmp.id, 'cumulatif']);
  assert.equal(gen.coefficient, 40);
  assert.equal(sub.parentId, gen.id);
  assert.deepEqual(by('releves')[0], { ...by('releves')[0], compteurId: hrs.id, le: '2026-11-05T00:00', valeur: 12300, estime: false, source: 'reprise' });
  const [fil, huile] = by('articles');
  assert.deepEqual([fil.critique, fil.emplacements, fil.fournisseurId, fil.equipementIds], [true, { 's-tng': 'A3-02' }, by('fournisseurs')[0].id, [cmp.id]]);
  assert.deepEqual([huile.uniteAchat, huile.contenuUniteAchat], ['bidon', 20]);
  const prog = by('programmes')[0];
  assert.deepEqual([prog.periodiciteJours, prog.prochaineEcheance, prog.compteurId, prog.intervalleCompteur, prog.dernierIndex, prog.regle, prog.siteId],
    [180, '2027-02-28', hrs.id, 500, 12000, 'apres_realisation', 's-tng']);
  assert.equal(by('programmes')[1].modele, 'verification_externe');
  assert.ok(r.fiches.every(f => f.data.lotImport === 'lot-1'), 'chaque fiche porte son lot (annulation)');
  assert.deepEqual(r.invitations, [{ personneId: by('personnes')[0].id, nom: 'Karim Alaoui', email: 'karim.alaoui@exemple.ma', role: 'technicien', sites: ['s-tng', 's-cas'] }]);
  assert.ok(!('email' in by('personnes')[0]), 'l’e-mail ne va pas dans la fiche personne (lisible par toute l’équipe)');
});

test('stock de départ = entrée « inventaire initial » ; le coût moyen part du prix repris', () => {
  const r = Kit.convertir(KIT(), ctx());
  const mv = r.fiches.filter(f => f.type === 'mouvements').map(f => f.data);
  const vals = r.fiches.filter(f => f.type === 'valorisations').map(f => f.data);
  const fil = r.fiches.find(f => f.type === 'articles' && f.data.ref === 'FIL-15').data;
  assert.equal(C.stockPhysique(mv, fil.id, 's-tng'), 4);
  assert.equal(C.stockPhysique(mv, fil.id, 's-cas'), 2);
  const v = C.valorisation(mv, vals, fil.id, 's-tng');
  assert.equal(v.cump, 310);
  assert.equal(C.valorisation(mv, vals, fil.id, 's-cas').cump, null, 'sans prix : non valorisé, jamais 0');
  assert.ok(r.avertissements.some(a => a.champ === 'Stock actuel' && a.ligne === 8), 'stock inconnu signalé, aucun mouvement');
});

test('erreurs ligne par ligne : rien n’est importé tant qu’il en reste', () => {
  const k = KIT();
  k['Lieux'].push(L(9, { 'Code site': 'RAB', 'Code lieu': 'X', 'Nom du lieu': 'X' }));
  k['Équipements'].push(L(8, { 'Code équipement': 'CMP-01', 'Désignation': 'Doublon', 'Code site': 'TNG', 'Code lieu': 'ATL-B', 'Classe': 'ROT-COMPR' }));
  k['Équipements'].push(L(9, { 'Code équipement': 'P-9', 'Désignation': 'Pompe', 'Code site': 'TNG', 'Code lieu': 'INCONNU', 'Classe': 'XYZ-FOO · Truc' }));
  k['Compteurs'].push(L(9, { 'Code compteur': 'EAU', 'Libellé': 'Eau', 'Usage': 'Ressource', 'Code site': 'TNG', 'Unité': 'm³', 'Type': 'Cumulatif (index)', 'Code compteur parent': 'EL-GEN' }));
  k['Articles'].push(L(9, { 'Référence': 'J-1', 'Désignation': 'Joint', 'Unité': 'u', 'Code site': 'TNG', 'Stock actuel': -1, 'Prix unitaire HT (MAD)': 0 }));
  k['Préventif'].push(L(8, { 'Code équipement': 'CMP-01', 'Opération': 'Graissage', 'Type': 'Entretien' }));
  k['Personnes'].push(L(8, { 'Nom': 'Ali', 'E-mail': 'ali@', 'Rôle': 'Chef', 'Codes sites': 'TNG' }));
  k['Compteurs'][0]['Date du dernier index'] = '31/02/2026';
  const r = Kit.convertir(k, ctx());
  const e = r.erreurs.map(x => `${x.onglet}:${x.ligne}:${x.champ}`);
  for (const attendu of ['Lieux:9:Code site', 'Équipements:8:Code équipement', 'Équipements:9:Code lieu', 'Équipements:9:Classe', 'Compteurs:9:Ressource',
    'Compteurs:9:Code compteur parent', 'Articles:9:Stock actuel', 'Articles:9:Prix unitaire HT (MAD)', 'Préventif:8:Tous les … jours',
    'Personnes:8:E-mail', 'Personnes:8:Rôle', 'Compteurs:6:Date du dernier index']) assert.ok(e.includes(attendu), 'erreur attendue : ' + attendu + '\n' + e.join('\n'));
  assert.deepEqual(r.fiches, [], 'tout ou rien');
  assert.ok(r.aImporter > 0);
});

test('existant chez le client : doublons refusés, références acceptées', () => {
  const r = Kit.convertir({
    'Équipements': [L(6, { 'Code équipement': 'CMP-01', 'Désignation': 'X', 'Code site': 'TNG', 'Code lieu': 'ATL-B', 'Classe': 'ROT-COMPR' }),
      L(7, { 'Code équipement': 'MOT-02', 'Désignation': 'Moteur', 'Code site': 'TNG', 'Code lieu': 'ATL-B', 'Code équipement parent': 'CMP-01', 'Classe': 'ELE-MOTEUR' })],
    'Personnes': [L(6, { 'Nom': 'karim alaoui', 'Rôle': 'Technicien', 'Codes sites': 'TNG' })],
  }, ctx({ existants: { localisations: [{ id: 'l1', code: 'ATL-B', siteId: 's-tng' }], equipements: [{ id: 'e1', code: 'CMP-01', siteId: 's-tng' }], personnes: [{ id: 'p1', nom: 'Karim Alaoui' }] } }));
  assert.deepEqual(r.erreurs.map(x => x.ligne + ' ' + x.message), ['6 déjà présent chez le client (« CMP-01 »)']);
  const r2 = Kit.convertir({ 'Équipements': [L(7, { 'Code équipement': 'MOT-02', 'Désignation': 'Moteur', 'Code site': 'TNG', 'Code lieu': 'ATL-B', 'Code équipement parent': 'CMP-01', 'Classe': 'ELE-MOTEUR' })],
    'Personnes': [L(6, { 'Nom': 'karim alaoui', 'Rôle': 'Technicien', 'Codes sites': 'TNG' })] },
  ctx({ existants: { localisations: [{ id: 'l1', code: 'ATL-B', siteId: 's-tng' }], equipements: [{ id: 'e1', code: 'CMP-01', siteId: 's-tng' }], personnes: [{ id: 'p1', nom: 'Karim Alaoui' }] } }));
  assert.deepEqual(r2.erreurs, []);
  assert.deepEqual([r2.fiches[0].data.parentId, r2.fiches[0].data.localisationId], ['e1', 'l1']);
  assert.equal(r2.resume.personnes, undefined, 'personne existante non recréée (avertissement)');
});

test('boucle de parenté refusée', () => {
  const r = Kit.convertir({ 'Lieux': [L(6, { 'Code site': 'TNG', 'Code lieu': 'A', 'Nom du lieu': 'A', 'Code du lieu parent': 'B' }), L(7, { 'Code site': 'TNG', 'Code lieu': 'B', 'Nom du lieu': 'B', 'Code du lieu parent': 'A' })] }, ctx());
  assert.ok(r.erreurs.some(x => /boucle/.test(x.message)));
});

test('dates Excel : numéro de série, JJ/MM/AAAA, date ISO ; date impossible refusée', () => {
  assert.equal(Kit.dateISO(46387), '2026-12-31');
  assert.equal(Kit.dateISO('5/11/2026'), '2026-11-05');
  assert.equal(Kit.dateISO('2026-11-05T00:00:00'), '2026-11-05');
  assert.equal(Kit.dateISO('31/02/2026'), null);
});

test('lecture d’une feuille : en-têtes de la ligne 4, « * » retiré', () => {
  const o = Kit.objets([{ n: 1, cellules: ['Titre'] }, { n: 4, cellules: ['Code site *', 'Nom du lieu *', 'Remarques'] }, { n: 6, cellules: ['TNG', 'Atelier'] }]);
  assert.deepEqual(o, [{ _ligne: 6, 'Code site': 'TNG', 'Nom du lieu': 'Atelier', 'Remarques': null }]);
});
