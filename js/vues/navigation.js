/* GMAO terrain — lot R1 : navigation par rôle (docs/MAQUETTES_R1.md).
   Chaque rôle a sa barre du bas (outil principal en premier), son accueil et son menu « Plus » regroupé par domaine.
   Le serveur reste l'autorité des droits (lecture et écriture) ; ici on n'affiche que ce que le rôle peut utiliser.
   Script classique chargé après les autres vues. */
(() => {
  const { V, AFTER, esc, badge, empty, list, today, role, autorise, aModule, otCard, demCard, eqCard, actifs, otOuvert,
    estAdminClient, voitJournal, desigBesoin } = App;
  const { data } = Store;
  const R0 = () => role() || 'responsable';   // sans compte : l'appareil a tous les droits (comme un responsable)

  // ---------- barres du bas ----------
  // [adresse, icône, libellé, écrans qui l'allument, module requis]
  const PLUS = ['#/plus', '≡', 'Plus', ['plus']];
  const BARRES = {
    technicien: [['#/accueil', '☀', 'Ma journée', ['accueil']], ['#/signaler', '＋', 'Signaler', ['signaler', 'rapide']],
      ['#/ots?f=mine', '⚒', 'Mes travaux', ['ots', 'ot']], ['#/parc', '▦', 'Parc', ['parc', 'eq']], PLUS],
    prestataire: [['#/accueil', '⚒', 'Mes interventions', ['accueil', 'ots', 'ot']], ['#/signaler', '＋', 'Signaler', ['signaler', 'rapide']],
      ['#/compte', '◯', 'Mon compte', ['compte', 'reglages']]],
    responsable: [['#/accueil', '◉', 'Aujourd’hui', ['accueil']], ['#/demandes', '✎', 'Demandes', ['demandes', 'demande']],
      ['#/ots', '⚒', 'Travaux', ['ots', 'ot']], ['#/preventif', '↻', 'Préventif', ['preventif'], 'preventif'], PLUS],
    exploitation: [['#/accueil', '＋', 'Signaler', ['accueil', 'signaler']], ['#/demandes?f=miennes', '✎', 'Mes demandes', ['demandes', 'demande']],
      ['#/compteurs', '⏱', 'Relevés', ['compteurs', 'compteur', 'releve']], ['#/parc', '▦', 'Parc', ['parc', 'eq']]],
    magasinier: [['#/accueil', '▤', 'Magasin', ['accueil']], ['#/magasin', '▦', 'Articles', ['magasin', 'article'], 'magasin'],
      ['#/reappro', '↻', 'Réappro', ['reappro'], 'magasin'], ['#/achats?f=receptionner', '⇣', 'Réceptions', ['achats', 'achat'], 'achats'], PLUS],
    achats: [['#/accueil', '₪', 'Achats', ['accueil']], ['#/achats?f=commander', '＋', 'À commander', [], 'achats'],
      ['#/achats', '☰', 'Commandes', ['achats', 'achat'], 'achats'], ['#/reappro', '↻', 'Réappro', ['reappro'], 'magasin'], PLUS],
    pilote: [['#/accueil', '◉', 'Synthèse', ['accueil']], ['#/indicateurs', '▥', 'Indicateurs', ['indicateurs']],
      ['#/energie', '⚡', 'Énergie', ['energie', 'facture'], 'energie'], ['#/valeur', '∑', 'Coûts', ['valeur'], 'achats'], PLUS],
  };
  const barre = () => (BARRES[R0()] || BARRES.responsable).filter(b => !b[4] || aModule(b[4]));
  App.signalerDansBarre = () => barre().some(b => b[3].includes('signaler'));

  App.navigation = Rt => {
    const nav = document.querySelector('nav.tabs');
    if (!nav) return;
    const b = barre();
    const actif = b.findIndex(x => x[3].includes(Rt.name));
    const iPlus = b.findIndex(x => x[0] === '#/plus');
    const on = actif >= 0 ? actif : iPlus;   // écran hors barre : « Plus » allumé
    nav.innerHTML = b.map((x, i) => `<a href="${x[0]}" class="${i === on ? 'on' : ''}"><span class="ic">${x[1]}</span>${esc(x[2])}</a>`).join('');
  };

  // ---------- menu « Plus » (spécification R1 §3) ----------
  // [adresse, icône, libellé, description, rôles ('ADMIN' = droit administrateur), condition]
  const ADMIN = 'ADMIN';
  const MENU = [
    ['Terrain', [
      ['#/demandes', '✎', 'Demandes', 'Toutes les demandes', ['technicien']],
      ['#/preventif', '↻', 'Préventif', 'Programmes et échéances', ['technicien'], () => aModule('preventif')],
      ['#/compteurs', '⏱', 'Compteurs et relevés', 'Relevés, heures de marche', ['technicien', 'responsable']],
      ['#/qr', '▣', 'QR codes', 'Étiquettes des équipements', ['technicien', 'responsable', ADMIN]],
      ['#/parc', '▦', 'Parc', 'Équipements et lieux', ['responsable', 'magasinier', 'achats', 'pilote']]]],
    ['Magasin et achats', [
      ['#/magasin', '▤', 'Magasin', 'Articles et stock', ['responsable', 'technicien', 'achats'], () => aModule('magasin')],
      ['#/achats', '₪', 'Achats', 'Demandes d’achat, commandes', ['responsable', 'magasinier', 'pilote'], () => aModule('achats') && App.voitCouts?.()],
      ['#/valeur', '∑', 'Valeur du stock', 'Coût moyen par article et site', ['responsable', 'magasinier', 'achats'], () => aModule('achats') && App.voitCouts?.()]]],
    ['Énergie', [
      ['#/energie', '⚡', 'Énergie et eau', 'Consommations, factures', ['responsable', 'achats'], () => App.energie?.voitEnergie()]]],
    ['Pilotage', [
      ['#/indicateurs', '▥', 'Indicateurs', 'Pannes, préventif, délais', ['responsable']],
      ['#/journal', '☰', 'Journal d’audit', 'Toutes les modifications', ['responsable', 'pilote', ADMIN], () => voitJournal()]]],
    ['Entreprise', [
      ['#/entreprise', '⚙', 'Entreprise', 'Membres, sites, règles, abonnement, données', [ADMIN]],
      ['#/plateforme', '◆', 'Console plateforme', 'Clients, abonnements, démo', ['*'], () => Sync.profil()?.adminPlateforme || Sync.profil()?.adminMfa]]],
    ['Mon compte', [
      ['#/compte', '◯', 'Mon compte', 'Mot de passe, appareil, support', ['*']]]],
  ];
  const voit = roles => roles.includes('*') || roles.includes(R0()) || (roles.includes(ADMIN) && estAdminClient());
  V.plus = () => {
    const dansBarre = new Set(barre().map(b => b[0].split('?')[0]));
    const groupes = MENU.map(([g, items]) => [g, items.filter(i => voit(i[4]) && (!i[5] || i[5]()) && !dansBarre.has(i[0]))]).filter(([, l]) => l.length);
    return `<h1>Menu</h1>${groupes.map(([g, l]) => `<h2>${esc(g)}</h2>${l.map(i => `<a class="card" href="${i[0]}"><div class="t">${i[1]} ${esc(i[2])}</div><div class="s">${esc(i[3])}</div></a>`).join('')}`).join('')}`;
  };

  // ---------- accueil technicien et prestataire : « Ma journée » / « Mes interventions » ----------
  const moi = () => Store.currentUser();
  const mesOts = () => list('ots').filter(o => otOuvert(o) && actifs(o).some(i => i.personneId === moi()?.id));
  const jour = o => (o.creneau || o.echeance || '').slice(0, 10);
  V.accueilTerrain = () => {
    const presta = role() === 'prestataire';
    const l = mesOts(), t = today().slice(0, 10);
    const enCours = l.filter(o => o.statut === 'en_cours');
    const attente = l.filter(o => o.statut === 'suspendue');
    const aujourdhui = l.filter(o => !enCours.includes(o) && !attente.includes(o) && o.statut !== 'travail_termine' && jour(o) && jour(o) <= t);
    const aVenir = l.filter(o => !enCours.includes(o) && !attente.includes(o) && !aujourdhui.includes(o));
    const mvts = [...data.mouvements.values()];
    const prets = [...data.besoins.values()].filter(b => l.some(o => o.id === b.otId) && Calculs.etatBesoin(b, mvts) === 'reserve');
    const rel = App.compteurs && autorise('releve-saisir') ? App.compteurs.dus() : [];
    const aPrendre = presta ? [] : list('demandes').filter(d => d.statut === 'a_examiner').sort((a, b) => (b.creeLe || "").localeCompare(a.creeLe || ""));
    const section = (titre, items, rendu = otCard) => items.length ? `<h2>${titre}</h2>${items.map(rendu).join('')}` : '';
    return `<h1>${presta ? 'Mes interventions' : 'Ma journée'} <span class="muted small" style="font-weight:400">${App.fmtY(today())}</span></h1>
      ${!moi() ? '<p class="warn">Compte sans fiche personne : reconnectez-vous pour retrouver vos interventions.</p>' : ''}
      <div class="tiles">
        <a class="tile blue" href="#/ots?f=mine"><b>${l.length}</b><span>${presta ? 'Interventions confiées' : 'Mes travaux ouverts'}</span></a>
        <a class="tile ${attente.length ? 'amber' : ''}" href="#/ots?f=mine"><b>${attente.length}</b><span>En attente</span></a>
        ${rel.length ? `<a class="tile ${rel.some(x => x.retardJours > 0) ? 'amber' : ''}" href="#/compteurs"><b>${rel.length}</b><span>Relevés à faire</span></a>` : ''}
        ${prets.length ? `<div class="tile green"><b>${prets.length}</b><span>Pièces prêtes au magasin</span></div>` : ''}
      </div>
      ${section('En cours', enCours)}
      ${section('Aujourd’hui', aujourdhui)}
      ${prets.length ? `<h2>Pièces prêtes à récupérer</h2><div class="card"><ul class="lines">${prets.map(b => `<li><span class="grow">${esc(b.qte)} × ${esc(desigBesoin(b))}<br><span class="small muted">pour ${esc(data.ots.get(b.otId)?.ref || '')}</span></span>${badge('Réservée', 'green')}</li>`).join('')}</ul></div>` : ''}
      ${section('En attente', attente)}
      ${section('À venir', aVenir)}
      ${!l.length ? empty(presta ? 'Aucune intervention ne vous est confiée pour le moment.' : 'Aucun travail affecté. Les demandes à prendre sont ci-dessous.') : ''}
      ${rel.length ? `<h2>Relevés à faire</h2>${rel.slice(0, 5).map(App.carteReleveDu).join('')}` : ''}
      ${aPrendre.length ? `<h2>Demandes à prendre</h2>${aPrendre.slice(0, 5).map(demCard).join('')}${aPrendre.length > 5 ? `<a class="btn ghost" href="#/demandes?f=a_examiner">Toutes (${aPrendre.length})</a>` : ''}` : ''}`;
  };

  // ---------- accueil exploitation (opérateur) ----------
  V.accueilExploitation = () => {
    const miennes = list('demandes').filter(d => d.creePar === Store.currentUserName()).sort((a, b) => (b.creeLe || "").localeCompare(a.creeLe || ""));
    const rel = App.compteurs && autorise('releve-saisir') ? App.compteurs.dus() : [];
    return `<a class="btn primary block" href="#/signaler" style="min-height:64px;font-size:1.15rem;margin:6px 0 16px">＋ Signaler un problème</a>
      <p class="small muted" style="margin-top:-6px">Scannez le QR collé sur la machine, ou choisissez-la dans la liste.</p>
      <h2>Mes signalements</h2>${miennes.length ? miennes.slice(0, 8).map(demCard).join('') + (miennes.length > 8 ? `<a class="btn ghost" href="#/demandes?f=miennes">Tous (${miennes.length})</a>` : '') : empty('Vous n’avez encore rien signalé.')}
      ${rel.length ? `<h2>Relevés à faire</h2>${rel.slice(0, 5).map(App.carteReleveDu).join('')}` : ''}`;
  };

  // ---------- accueil direction : chiffres disponibles aujourd'hui (MTBF, MTTR, disponibilité : lot R4) ----------
  V.accueilDirection = () => {
    const from = Calculs.addDays(today(), -30);
    const I = Calculs.indicateurs({ demandes: list('demandes'), ots: list('ots'), programmes: list('programmes') }, { from, today: today() });
    const med = I.delaiCloture.mediane, dus = I.preventif.dus, aTemps = I.preventif.aTemps;
    const h = m => (m == null ? '—' : m < 120 ? `${Math.round(m)} min` : m < 2880 ? `${Math.round(m / 60)} h` : `${Math.round(m / 1440)} j`);
    const nrj = App.energie ? App.energie.aExaminer() : 0;
    const indispo = list('equipements').filter(e => e.actif !== false && Calculs.etatEquipement(e.id, list('demandes'), list('ots')) === 'indisponible');
    return `<h1>Tableau de bord <span class="muted small" style="font-weight:400">30 derniers jours</span></h1>
      <div class="tiles">
        <a class="tile ${indispo.length ? 'red' : 'green'}" href="#/parc?f=indisponible"><b>${indispo.length}</b><span>Équipements indisponibles</span></a>
        <a class="tile blue" href="#/indicateurs?p=30"><b>${I.interventions}</b><span>Interventions</span></a>
        <a class="tile ${dus && aTemps / dus < .8 ? 'amber' : ''}" href="#/indicateurs?p=30"><b>${dus ? Math.round(100 * aTemps / dus) + ' %' : '—'}</b><span>Préventif à l’heure</span></a>
        <a class="tile" href="#/indicateurs?p=30"><b>${h(med)}</b><span>Délai médian de clôture</span></a>
        <a class="tile ${I.repetitives.length ? 'amber' : ''}" href="#/indicateurs?p=30"><b>${I.repetitives.length}</b><span>Équipements à pannes répétitives</span></a>
        ${App.energie?.voitEnergie() ? `<a class="tile ${nrj ? 'amber' : ''}" href="#/energie?o=examiner"><b>${nrj}</b><span>Énergie : à examiner</span></a>` : ''}
      </div>
      ${I.repetitives.length ? `<h2>À regarder</h2><div class="card"><ul class="lines">${I.repetitives.slice(0, 5).map(([id, n]) => `<li><a class="grow" href="#/eq/${id}">${esc(App.eq(id)?.designation || '')}</a><b>${n} faits</b></li>`).join('')}</ul></div>` : ''}
      <p class="small muted">Disponibilité, MTBF et MTTR (arrêts planifiés et non planifiés) arrivent avec les tableaux de bord du lot R4.</p>`;
  };

  // ---------- recherche ----------
  V.recherche = r => `<h1>Rechercher</h1><input type="search" id="q" placeholder="Code, nom, référence (ex. PRESSE, DEM-, OT-)" value="${esc(r.q.get('q') || '')}" autocomplete="off" style="margin-bottom:12px"><div id="res"></div>`;
  AFTER.recherche = () => {
    const champ = document.querySelector('#q'), res = document.querySelector('#res');
    const chercher = () => {
      const q = champ.value.trim().toLowerCase();
      history.replaceState(null, '', '#/recherche' + (q ? '?q=' + encodeURIComponent(q) : ''));
      if (q.length < 2) { res.innerHTML = '<p class="small muted">Au moins 2 caractères.</p>'; return; }
      const has = (...v) => v.some(x => String(x || '').toLowerCase().includes(q));
      const eqs = list('equipements').filter(e => has(e.code, e.designation)).slice(0, 8);
      const dems = list('demandes').filter(d => has(d.ref, d.constat, App.eq(d.equipementId)?.designation)).slice(0, 8);
      const ots = list('ots').filter(o => has(o.ref, o.travaux, App.eq(o.equipementId)?.designation)).slice(0, 8);
      const arts = aModule('magasin') && R0() !== 'prestataire' ? list('articles').filter(a => has(a.ref, a.designation)).slice(0, 8) : [];
      const cpts = App.compteurs ? App.compteurs.visibles().filter(c => has(c.code, c.libelle)).slice(0, 8) : [];
      const bloc = (t, l, f) => l.length ? `<h2>${t}</h2>${l.map(f).join('')}` : '';
      const html = bloc('Équipements', eqs, eqCard) + bloc('Demandes', dems, demCard) + bloc('Interventions', ots, otCard)
        + bloc('Articles', arts, a => `<a class="card" href="#/article/${a.id}"><div class="t">${esc(a.designation)}</div><div class="s">${esc(a.ref)}</div></a>`)
        + bloc('Compteurs', cpts, c => `<a class="card" href="#/compteur/${c.id}"><div class="t">${esc(c.libelle || c.code)}</div><div class="s">${esc(c.code)} · ${esc(c.unite)}</div></a>`);
      res.innerHTML = html || empty('Aucun résultat.');
    };
    champ.oninput = chercher;
    champ.focus();
    chercher();
  };
})();
