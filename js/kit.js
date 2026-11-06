/* Kit de démarrage (kit/Kit_demarrage_Perfora.xlsx) → fiches Perfora. Fonctions pures, sans accès au stockage.
   Utilisé par la page « Mise en service » de la console plateforme et par les tests (node --test).
   Entrée : onglets = { 'Lieux': [{ _ligne, 'Code site': …, … }], … } (en-têtes du kit, sans « * »).
   Contexte : { sites: [{id, code}], existants: { localisations, equipements, compteurs, articles, fournisseurs, personnes },
     classes: ['ROT-POMPE', …], aujourdhui: 'YYYY-MM-DD', lot: 'id du lot', uid: () => 'id', par: 'nom' }.
   Sortie : { fiches: [{ id, type, data }], erreurs, avertissements: [{ onglet, ligne, champ, message }], resume, invitations }.
   Règles : une valeur inconnue reste vide (jamais 0) ; les références se font par code, dans le fichier ou dans
   l'existant ; une ligne d'exemple (code « EX-… ») est ignorée. */
(function (root) {
  const ONGLETS = ['Lieux', 'Équipements', 'Compteurs', 'Fournisseurs', 'Articles', 'Préventif', 'Personnes'];
  const sansAccent = s => String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[’']/g, '\'').trim();
  const CHOIX = {
    criticite: { a: 'A', b: 'B', c: 'C' },
    statut: { 'en service': 'en_service', 'en secours': 'secours', 'a l\'arret': 'arret', reforme: 'reforme' },
    reglementaire: { levage: 'levage', 'appareil a pression': 'pression', 'installation electrique': 'electrique', incendie: 'incendie',
      ascenseur: 'ascenseur', 'visite technique vehicule': 'vehicule', 'autre controle': 'autre' },
    usage: { ressource: 'ressource', equipement: 'equipement' },
    ressource: { electricite: 'electricite', eau: 'eau', gasoil: 'gasoil', fuel: 'fuel', gaz: 'gaz', 'air comprime': 'air_comprime', froid: 'froid', autre: 'autre' },
    mode: { 'cumulatif (index)': 'cumulatif', cumulatif: 'cumulatif', 'non cumulatif (quantite)': 'periode', 'non cumulatif': 'periode' },
    modele: { entretien: 'entretien', inspection: 'inspection', test: 'test', 'verification externe': 'verification_externe', autre: 'autre' },
    regle: { 'echeance fixe': 'fixe', 'apres realisation': 'apres_realisation' },
    role: { responsable: 'responsable', technicien: 'technicien', prestataire: 'prestataire', magasinier: 'magasinier', achats: 'achats', exploitation: 'exploitation', pilote: 'pilote' },
    ouinon: { oui: true, non: false },
  };
  const UNITES_CPT = ['kWh', 'm³', 'L', 'kg', 'Nm³', 'h', 'cycles', 'km', 't', '°C', 'bar'];

  function addDays(s, n) {
    const [y, m, d] = s.slice(0, 10).split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
  }
  const vide = v => v == null || (typeof v === 'string' && v.trim() === '');
  const txt = v => (vide(v) ? null : String(v).trim());
  const code = v => (vide(v) ? null : String(v).trim().toUpperCase());

  function convertir(onglets, ctx) {
    const erreurs = [], avertissements = [], fiches = [], invitations = [];
    const uid = ctx.uid, auj = ctx.aujourdhui, lot = ctx.lot;
    const ex = ctx.existants || {};
    const err = (onglet, ligne, champ, message) => erreurs.push({ onglet, ligne, champ, message });
    const avert = (onglet, ligne, champ, message) => avertissements.push({ onglet, ligne, champ, message });
    const ajouter = (type, data) => { fiches.push({ id: data.id, type, data: { ...data, lotImport: lot, creeLe: auj + 'T00:00', creePar: ctx.par || 'Reprise Perfora' } }); return data; };
    const classes = new Set(ctx.classes || []);
    const sites = new Map((ctx.sites || []).map(s => [code(s.code), s.id]));

    // lecture typée d'une cellule, avec erreur à la ligne
    function lecteur(onglet, r) {
      const champ = (nom, { oblig = false } = {}) => {
        const v = r[nom];
        if (oblig && vide(v)) err(onglet, r._ligne, nom, 'obligatoire');
        return v;
      };
      return {
        t: (nom, o) => txt(champ(nom, o)),
        c: (nom, o) => code(champ(nom, o)),
        n: (nom, { min = null, entier = false, ...o } = {}) => {
          const v = champ(nom, o);
          if (vide(v)) return null;
          const x = typeof v === 'number' ? v : Number(String(v).replace(/\s/g, '').replace(',', '.'));
          if (!Number.isFinite(x)) { err(onglet, r._ligne, nom, `nombre attendu (« ${v} »)`); return null; }
          if (min != null && x < min) { err(onglet, r._ligne, nom, `doit être ≥ ${min}`); return null; }
          if (entier && !Number.isInteger(x)) { err(onglet, r._ligne, nom, 'nombre entier attendu'); return null; }
          return x;
        },
        d: (nom, o) => {
          const v = champ(nom, o);
          if (vide(v)) return null;
          const s = dateISO(v);
          if (!s) err(onglet, r._ligne, nom, `date attendue au format JJ/MM/AAAA (« ${v} »)`);
          return s;
        },
        l: (nom, liste, o) => {
          const v = champ(nom, o);
          if (vide(v)) return null;
          const k = sansAccent(String(v).split(' · ')[0]);
          if (!(k in CHOIX[liste])) { err(onglet, r._ligne, nom, `valeur hors liste (« ${v} »)`); return null; }
          return CHOIX[liste][k];
        },
        site: (nom = 'Code site') => {
          const c = code(champ(nom, { oblig: true }));
          if (!c) return null;
          if (!sites.has(c)) { err(onglet, r._ligne, nom, `site inconnu (« ${c} ») : créez-le d’abord dans la console`); return null; }
          return sites.get(c);
        },
      };
    }
    const lignes = nom => (onglets[nom] || []).filter(r => {
      const vals = Object.entries(r).filter(([k]) => k !== '_ligne').map(([, v]) => v);
      if (vals.every(vide)) return false;
      return !vals.some(v => typeof v === 'string' && /^EX-/i.test(v.trim()));
    });

    // index : fichier d'abord, existant ensuite
    const idx = { lieu: new Map(), eq: new Map(), cpt: new Map(), art: new Map(), four: new Map() };
    for (const l of ex.localisations || []) idx.lieu.set(`${l.siteId}|${code(l.code)}`, { id: l.id, siteId: l.siteId, existant: true });
    for (const e of ex.equipements || []) idx.eq.set(code(e.code), { id: e.id, siteId: e.siteId, existant: true });
    for (const c of ex.compteurs || []) idx.cpt.set(code(c.code), { id: c.id, siteId: c.siteId, unite: c.unite, existant: true });
    for (const a of ex.articles || []) idx.art.set(code(a.ref), { id: a.id, existant: true });
    for (const f of ex.fournisseurs || []) idx.four.set(sansAccent(f.nom), { id: f.id, existant: true });

    // ---------- Lieux (deux passes : parents dans le désordre acceptés) ----------
    const lieux = [];
    for (const r of lignes('Lieux')) {
      const L = lecteur('Lieux', r);
      const siteId = L.site(), c = L.c('Code lieu', { oblig: true }), nom = L.t('Nom du lieu', { oblig: true });
      if (!siteId || !c) continue;
      const k = `${siteId}|${c}`;
      if (idx.lieu.has(k)) { err('Lieux', r._ligne, 'Code lieu', idx.lieu.get(k).existant ? `déjà présent chez le client (« ${c} »)` : `en double dans le fichier (« ${c} »)`); continue; }
      const d = { id: uid(), code: c, nom, siteId, parentId: null, remarques: L.t('Remarques') };
      idx.lieu.set(k, { id: d.id, siteId });
      lieux.push({ d, parent: L.c('Code du lieu parent'), ligne: r._ligne });
    }
    for (const { d, parent, ligne } of lieux) {
      if (parent) {
        const p = idx.lieu.get(`${d.siteId}|${parent}`);
        if (!p) err('Lieux', ligne, 'Code du lieu parent', `lieu parent inconnu sur ce site (« ${parent} »)`);
        else if (p.id === d.id) err('Lieux', ligne, 'Code du lieu parent', 'un lieu ne peut pas être son propre parent');
        else d.parentId = p.id;
      }
    }
    // boucle de parenté (A dans B dans A)
    const parentDe = new Map(lieux.map(({ d }) => [d.id, d.parentId]));
    for (const { d, ligne } of lieux) {
      let p = d.parentId, n = 0;
      while (p && n++ < 50) { if (p === d.id) { err('Lieux', ligne, 'Code du lieu parent', 'boucle de parenté entre lieux'); break; } p = parentDe.get(p); }
    }
    lieux.forEach(({ d }) => ajouter('localisations', d));

    // ---------- Équipements ----------
    const eqs = [];
    for (const r of lignes('Équipements')) {
      const L = lecteur('Équipements', r);
      const c = L.c('Code équipement', { oblig: true }), des = L.t('Désignation', { oblig: true }), siteId = L.site();
      const lieu = L.c('Code lieu', { oblig: true });
      const classeBrute = L.t('Classe', { oblig: true });
      const classe = classeBrute ? classeBrute.split(' · ')[0].trim().toUpperCase() : null;
      if (classe && classes.size && !classes.has(classe)) err('Équipements', r._ligne, 'Classe', `classe inconnue (« ${classeBrute} ») : choisissez dans la liste`);
      const statut = L.l('Statut', 'statut') || 'en_service';
      const d = { id: uid(), code: c, designation: des, siteId, localisationId: null, parentId: null, classe, sousType: L.t('Sous-type'),
        criticite: L.l('Criticité', 'criticite'), statut, actif: statut !== 'reforme', reglementaire: L.l('Contrôle réglementaire', 'reglementaire'),
        fabricant: L.t('Fabricant'), modele: L.t('Modèle'), numeroSerie: L.t('N° de série'), anneeService: L.n('Année de mise en service', { min: 1900, entier: true }),
        finGarantie: L.d('Fin de garantie'), remarques: L.t('Remarques') };
      if (!d.criticite) avert('Équipements', r._ligne, 'Criticité', 'criticité à fixer avec le responsable');
      if (!c || !siteId) continue;
      if (idx.eq.has(c)) { err('Équipements', r._ligne, 'Code équipement', idx.eq.get(c).existant ? `déjà présent chez le client (« ${c} »)` : `en double dans le fichier (« ${c} »)`); continue; }
      if (lieu) {
        const l = idx.lieu.get(`${siteId}|${lieu}`);
        if (!l) err('Équipements', r._ligne, 'Code lieu', `lieu inconnu sur ce site (« ${lieu} »)`); else d.localisationId = l.id;
      }
      idx.eq.set(c, { id: d.id, siteId });
      eqs.push({ d, parent: L.c('Code équipement parent'), ligne: r._ligne });
    }
    for (const { d, parent, ligne } of eqs) {
      if (!parent) continue;
      const p = idx.eq.get(parent);
      if (!p) err('Équipements', ligne, 'Code équipement parent', `équipement parent inconnu (« ${parent} »)`);
      else if (p.id === d.id) err('Équipements', ligne, 'Code équipement parent', 'un équipement ne peut pas être son propre parent');
      else d.parentId = p.id;
    }
    const parentEq = new Map(eqs.map(({ d }) => [d.id, d.parentId]));
    for (const { d, ligne } of eqs) {
      let p = d.parentId, n = 0;
      while (p && n++ < 50) { if (p === d.id) { err('Équipements', ligne, 'Code équipement parent', 'boucle de parenté entre équipements'); break; } p = parentEq.get(p); }
    }
    eqs.forEach(({ d }) => ajouter('equipements', d));

    // ---------- Compteurs (+ dernier index connu = premier relevé) ----------
    const cpts = [];
    for (const r of lignes('Compteurs')) {
      const L = lecteur('Compteurs', r);
      const c = L.c('Code compteur', { oblig: true }), lib = L.t('Libellé', { oblig: true }), usage = L.l('Usage', 'usage', { oblig: true });
      const siteId = L.site(), unite = L.t('Unité', { oblig: true }), mode = L.l('Type', 'mode', { oblig: true });
      if (unite && !UNITES_CPT.includes(unite)) err('Compteurs', r._ligne, 'Unité', `unité hors liste (« ${unite} »)`);
      const coef = L.n('Coefficient', { min: 0 });
      if (coef === 0) err('Compteurs', r._ligne, 'Coefficient', 'doit être supérieur à 0');
      const d = { id: uid(), code: c, libelle: lib, usage, siteId, equipementId: null, ressource: L.l('Ressource', 'ressource'), unite, mode,
        coefficient: coef || 1, parentId: null, frequenceJours: L.n('Fréquence de relevé (jours)', { min: 1, entier: true }), actif: true, remarques: L.t('Remarques') };
      const eqc = L.c('Code équipement');
      if (usage === 'equipement') {
        if (!eqc) err('Compteurs', r._ligne, 'Code équipement', 'obligatoire pour un compteur d’équipement');
        else if (!idx.eq.has(eqc)) err('Compteurs', r._ligne, 'Code équipement', `équipement inconnu (« ${eqc} »)`);
        else d.equipementId = idx.eq.get(eqc).id;
      } else if (usage === 'ressource') {
        if (!d.ressource) err('Compteurs', r._ligne, 'Ressource', 'obligatoire pour un compteur de ressource');
        if (eqc) { if (idx.eq.has(eqc)) d.equipementId = idx.eq.get(eqc).id; else err('Compteurs', r._ligne, 'Code équipement', `équipement inconnu (« ${eqc} »)`); }
      }
      if (!d.frequenceJours) avert('Compteurs', r._ligne, 'Fréquence de relevé (jours)', 'sans fréquence, le compteur n’apparaîtra pas dans « Relevés à faire »');
      const index = L.n('Dernier index connu'), le = L.d('Date du dernier index');
      if (!c || !siteId) continue;
      if (idx.cpt.has(c)) { err('Compteurs', r._ligne, 'Code compteur', idx.cpt.get(c).existant ? `déjà présent chez le client (« ${c} »)` : `en double dans le fichier (« ${c} »)`); continue; }
      idx.cpt.set(c, { id: d.id, siteId, unite });
      cpts.push({ d, parent: L.c('Code compteur parent'), index, le, ligne: r._ligne });
    }
    for (const x of cpts) {
      if (x.parent) {
        const p = idx.cpt.get(x.parent);
        if (!p) err('Compteurs', x.ligne, 'Code compteur parent', `compteur principal inconnu (« ${x.parent} »)`);
        else if (p.id === x.d.id) err('Compteurs', x.ligne, 'Code compteur parent', 'un compteur ne peut pas être son propre parent');
        else if (p.unite && x.d.unite && p.unite !== x.d.unite) err('Compteurs', x.ligne, 'Code compteur parent', `unités différentes (${x.d.unite} / ${p.unite}) : un sous-compteur mesure la même chose que son principal`);
        else x.d.parentId = p.id;
      }
      ajouter('compteurs', x.d);
      if (x.index != null) {
        if (x.d.mode !== 'cumulatif') { avert('Compteurs', x.ligne, 'Dernier index connu', 'compteur non cumulatif : l’index n’est pas repris'); continue; }
        if (!x.le) avert('Compteurs', x.ligne, 'Date du dernier index', `date inconnue : l’index est daté du jour de l’import (${auj})`);
        ajouter('releves', { id: uid(), compteurId: x.d.id, siteId: x.d.siteId, le: (x.le || auj) + 'T00:00', valeur: x.index, estime: !x.le, source: 'reprise' });
      }
    }

    // ---------- Fournisseurs ----------
    for (const r of lignes('Fournisseurs')) {
      const L = lecteur('Fournisseurs', r);
      const nom = L.t('Nom', { oblig: true });
      if (!nom) continue;
      const k = sansAccent(nom);
      if (idx.four.has(k)) { err('Fournisseurs', r._ligne, 'Nom', idx.four.get(k).existant ? `déjà présent chez le client (« ${nom} »)` : `en double dans le fichier (« ${nom} »)`); continue; }
      const d = ajouter('fournisseurs', { id: uid(), nom, contact: L.t('Contact'), telephone: L.t('Téléphone'), email: L.t('E-mail'),
        delaiJours: L.n('Délai habituel (jours)', { min: 0, entier: true }), actif: true, remarques: L.t('Remarques') });
      idx.four.set(k, { id: d.id });
    }

    // ---------- Articles (un article par référence, une ligne par site) + inventaire initial ----------
    const arts = new Map();
    for (const r of lignes('Articles')) {
      const L = lecteur('Articles', r);
      const ref = L.c('Référence', { oblig: true }), des = L.t('Désignation', { oblig: true }), unite = L.t('Unité', { oblig: true }), siteId = L.site();
      const stock = L.n('Stock actuel', { min: 0 }), prix = L.n('Prix unitaire HT (MAD)', { min: 0 });
      if (prix === 0) err('Articles', r._ligne, 'Prix unitaire HT (MAD)', 'un prix à 0 est faux : laissez vide si inconnu');
      const contenu = L.n('Contenu de l’unité d’achat', { min: 1 });
      const fourNom = L.t('Fournisseur habituel'), eqc = L.c('Code équipement concerné');
      if (!ref || !siteId) continue;
      let a = arts.get(ref);
      if (!a) {
        if (idx.art.has(ref)) { err('Articles', r._ligne, 'Référence', `déjà présent chez le client (« ${ref} »)`); continue; }
        a = { id: uid(), ref, designation: des, unite, critique: L.l('Article critique', 'ouinon') === true, emplacements: {}, uniteAchat: L.t('Unité d’achat'),
          contenuUniteAchat: contenu, fournisseurId: null, refFournisseur: L.t('Référence fournisseur'), equipementIds: [], actif: true, remarques: L.t('Remarques'), _sites: new Set() };
        arts.set(ref, a);
      } else if (a.designation !== des || a.unite !== unite) {
        err('Articles', r._ligne, 'Référence', `même référence avec une autre désignation ou unité (« ${ref} »)`); continue;
      }
      if (a._sites.has(siteId)) { err('Articles', r._ligne, 'Code site', `référence déjà saisie pour ce site (« ${ref} »)`); continue; }
      a._sites.add(siteId);
      const emp = L.t('Emplacement');
      if (emp) a.emplacements[siteId] = emp;
      if (fourNom) { const f = idx.four.get(sansAccent(fourNom)); if (f) a.fournisseurId = f.id; else avert('Articles', r._ligne, 'Fournisseur habituel', `fournisseur absent de l’onglet Fournisseurs (« ${fourNom} ») : non relié`); }
      if (eqc) { const e = idx.eq.get(eqc); if (e) { if (!a.equipementIds.includes(e.id)) a.equipementIds.push(e.id); } else avert('Articles', r._ligne, 'Code équipement concerné', `équipement inconnu (« ${eqc} ») : non relié`); }
      if ((a.uniteAchat && !contenu) || (!a.uniteAchat && contenu)) avert('Articles', r._ligne, 'Unité d’achat', 'unité d’achat et contenu vont ensemble : conditionnement ignoré');
      if (stock == null) { avert('Articles', r._ligne, 'Stock actuel', 'stock inconnu : à compter à l’inventaire'); if (prix != null) avert('Articles', r._ligne, 'Prix unitaire HT (MAD)', 'prix sans stock : il sera repris à la première entrée'); }
      else if (stock > 0) {
        const m = { id: uid(), type: 'entree', origine: 'inventaire_initial', articleId: a.id, siteId, qte: stock, le: auj + 'T00:00', motif: 'Inventaire initial (reprise)' };
        a._mvts = [...(a._mvts || []), { m, prix }];
      }
    }
    for (const a of arts.values()) {
      if (a.uniteAchat == null || a.contenuUniteAchat == null) { a.uniteAchat = null; a.contenuUniteAchat = null; }
      const { _sites, _mvts, ...d } = a;
      ajouter('articles', d);
      for (const { m, prix } of _mvts || []) {
        ajouter('mouvements', m);
        if (prix != null) ajouter('valorisations', { id: uid(), mouvementId: m.id, siteId: m.siteId, prixUnitaire: prix, devise: 'MAD', statut: 'connu' });
      }
    }

    // ---------- Préventif ----------
    for (const r of lignes('Préventif')) {
      const L = lecteur('Préventif', r);
      const eqc = L.c('Code équipement', { oblig: true }), lib = L.t('Opération', { oblig: true }), modele = L.l('Type', 'modele', { oblig: true });
      const jours = L.n('Tous les … jours', { min: 1, entier: true }), cptc = L.c('Code compteur'), pas = L.n('Toutes les … (unité du compteur)', { min: 0 });
      const derniere = L.d('Dernière réalisation'), idxDer = L.n('Index à la dernière réalisation', { min: 0 });
      const d = { id: uid(), equipementId: null, siteId: null, libelle: lib, modele, periodiciteJours: jours, regle: L.l('Règle', 'regle') || 'fixe',
        prochaineEcheance: null, derniereRealisation: derniere ? derniere + 'T00:00' : null, compteurId: null, intervalleCompteur: null, dernierIndex: null,
        instruction: L.t('Instructions'), organisme: L.t('Organisme (contrôle externe)'), actif: true, remarques: L.t('Remarques') };
      if (eqc) { const e = idx.eq.get(eqc); if (!e) err('Préventif', r._ligne, 'Code équipement', `équipement inconnu (« ${eqc} »)`); else { d.equipementId = e.id; d.siteId = e.siteId; } }
      if (cptc || pas != null) {
        const c = cptc && idx.cpt.get(cptc);
        if (!cptc) err('Préventif', r._ligne, 'Code compteur', 'obligatoire avec « Toutes les … (unité du compteur) »');
        else if (!c) err('Préventif', r._ligne, 'Code compteur', `compteur inconnu (« ${cptc} »)`);
        else if (!pas) err('Préventif', r._ligne, 'Toutes les … (unité du compteur)', 'obligatoire avec un compteur (ex. 500)');
        else { d.compteurId = c.id; d.intervalleCompteur = pas; d.dernierIndex = idxDer; if (idxDer == null) avert('Préventif', r._ligne, 'Index à la dernière réalisation', 'index inconnu : l’échéance compteur partira du premier relevé'); }
      }
      if (!jours && !(cptc && pas)) err('Préventif', r._ligne, 'Tous les … jours', 'indiquez une périodicité en jours, ou un compteur et son pas (ou les deux)');
      if (jours) d.prochaineEcheance = derniere ? addDays(derniere, jours) : auj;
      if (jours && !derniere) avert('Préventif', r._ligne, 'Dernière réalisation', `date inconnue : première échéance fixée au jour de l’import (${auj})`);
      if (modele === 'verification_externe' && !d.organisme) avert('Préventif', r._ligne, 'Organisme (contrôle externe)', 'organisme non renseigné');
      if (d.equipementId && lib && modele) ajouter('programmes', d);
    }

    // ---------- Personnes (fiches sans e-mail ; e-mails gardés pour les invitations) ----------
    const nomsExistants = new Set((ex.personnes || []).map(p => sansAccent(p.nom)));
    const nomsFichier = new Set();
    for (const r of lignes('Personnes')) {
      const L = lecteur('Personnes', r);
      const nom = L.t('Nom', { oblig: true }), role = L.l('Rôle', 'role', { oblig: true }), email = L.t('E-mail');
      const codes = (L.t('Codes sites', { oblig: true }) || '').split(/[,;]/).map(code).filter(Boolean);
      const siteIds = [];
      for (const c of codes) { if (sites.has(c)) siteIds.push(sites.get(c)); else err('Personnes', r._ligne, 'Codes sites', `site inconnu (« ${c} »)`); }
      if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) err('Personnes', r._ligne, 'E-mail', `adresse invalide (« ${email} »)`);
      if (!nom || !role) continue;
      const k = sansAccent(nom);
      if (nomsFichier.has(k)) { err('Personnes', r._ligne, 'Nom', `en double dans le fichier (« ${nom} »)`); continue; }
      nomsFichier.add(k);
      if (nomsExistants.has(k)) { avert('Personnes', r._ligne, 'Nom', `déjà présent chez le client (« ${nom} ») : non recréé`); continue; }
      const d = ajouter('personnes', { id: uid(), nom, role, societe: L.t('Société (prestataire)'), telephone: L.t('Téléphone'), actif: true });
      if (email) invitations.push({ personneId: d.id, nom, email: email.toLowerCase(), role, sites: siteIds });
    }

    const resume = {};
    for (const f of fiches) resume[f.type] = (resume[f.type] || 0) + 1;
    return { fiches: erreurs.length ? [] : fiches, erreurs, avertissements, resume, invitations, aImporter: fiches.length };
  }

  /** Date d'une cellule Excel : nombre de série (système 1900), Date, « JJ/MM/AAAA » ou « AAAA-MM-JJ ». null si illisible. */
  function dateISO(v) {
    if (v instanceof Date && !isNaN(v)) return v.toISOString().slice(0, 10);
    if (typeof v === 'number' && v > 59 && v < 2958466) return new Date(Date.UTC(1899, 11, 30) + Math.round(v) * 864e5).toISOString().slice(0, 10);
    const s = String(v).trim();
    let m = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/.exec(s);
    if (m) { const [, d, mo, y] = m.map(Number); return valide(y, mo, d); }
    m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
    if (m) { const [, y, mo, d] = m.map(Number); return valide(y, mo, d); }
    return null;
  }
  function valide(y, m, d) {
    const t = new Date(Date.UTC(y, m - 1, d));
    return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d ? t.toISOString().slice(0, 10) : null;
  }

  /** Lignes d'une feuille lue (tableau de lignes { n, cellules[] }) → objets par en-tête (ligne 4 du kit, « * » retiré). */
  function objets(lignesFeuille, ligneEntete = 4) {
    const ent = lignesFeuille.find(l => l.n === ligneEntete);
    if (!ent) return [];
    const noms = ent.cellules.map(h => (h == null ? null : String(h).replace(/\s*\*\s*$/, '').trim()));
    return lignesFeuille.filter(l => l.n > ligneEntete).map(l => {
      const o = { _ligne: l.n };
      noms.forEach((h, i) => { if (h) o[h] = l.cellules[i] ?? null; });
      return o;
    });
  }

  const Kit = { ONGLETS, convertir, dateISO, objets };
  if (typeof module === 'object' && module.exports) module.exports = Kit; else root.Kit = Kit;
})(this);
