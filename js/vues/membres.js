/* GMAO terrain — lot R3 : membres, équipes, sociétés prestataires, habilitations (docs/MAQUETTES_R3.md).
   Un membre = une fiche « personnes », avec ou sans accès à l'appli (compte relié par profils.personne_id).
   Gérés par le responsable et l'administrateur de l'entreprise ; l'accès (invitation, sites, rôle d'un compte,
   ★ administrateur) est réservé à l'administrateur. Le serveur reste l'autorité (supabase/membres_r3.sql).
   Script classique chargé après app.js. */
(() => {
  const { V, A, L, AFTER, esc, badge, empty, seg, search, askForm, askConfirm, alertBox, toast, edit, list, render, role, estAdminClient,
    mesSites, siteActif, adressePublique, otOuvert, actifs } = App;
  const { data } = Store;

  const gere = () => !role() || role() === 'responsable' || estAdminClient();
  const admin = () => estAdminClient();
  const connecte = () => !!Sync.profil();
  const jour = () => Store.now().slice(0, 10);
  const membres = () => list('personnes');
  const equipes = () => list('equipes').filter(e => e.actif !== false).sort((a, b) => (a.nom || '').localeCompare(b.nom || ''));
  const societes = (filtre = 'prestataire') => list('fournisseurs').filter(s => s.actif !== false && (filtre === 'tous' || !!s[filtre]))
    .sort((a, b) => (a.nom || '').localeCompare(b.nom || ''));
  const nomSociete = id => data.fournisseurs.get(id)?.nom || '';
  const nomMembre = id => data.personnes.get(id)?.nom || '—';
  const telLien = t => t ? `<a href="tel:${esc(String(t).replace(/[^\d+]/g, ''))}">${esc(t)}</a>` : '';
  const HABILITATIONS = { B1V: 'B1V', B2V: 'B2V', BR: 'BR', H0: 'H0', CACES: 'CACES', hauteur: 'Travail en hauteur', ATEX: 'ATEX', autre: 'Autre' };
  const contratEchu = s => !!(s.contratFin && s.contratFin < jour());

  // ---------- comptes (lus par le responsable et l'administrateur, connectés) ----------
  // Lus à la demande ; relus après une minute, ou si le compte connecté change. Un échec (hors ligne, session expirée)
  // ne laisse pas une liste vide : l'accès reste « … » et la lecture est retentée au prochain affichage.
  let comptes = null, utilisation = null, chargement = null, luLe = 0, luPour = null;
  function chargerComptes() {
    if (!connecte() || !gere()) return Promise.resolve(false);
    if (!chargement) chargement = Promise.all([Sync.equipe(), Sync.utilisation()])
      .then(([c, u]) => { comptes = c || []; utilisation = u; luLe = Date.now(); luPour = Sync.profil()?.userId; return true; })
      .catch(() => false)
      .finally(() => { chargement = null; });
    return chargement;
  }
  const aRelire = () => connecte() && gere() && (comptes === null || Date.now() - luLe > 60000 || luPour !== Sync.profil()?.userId);
  const compteDe = id => (comptes || []).find(c => c.personne_id === id) || null;
  /** [libellé, couleur] de l'accès ; null hors connexion (appareil sans compte). */
  function acces(m) {
    if (!connecte() || !gere()) return null;
    if (comptes === null) return ['…', ''];
    const c = compteDe(m.id);
    return !c ? ['Sans accès', ''] : c.actif ? ['Actif', 'green'] : ['Accès retiré', 'red'];
  }
  const sitesOpts = () => Object.fromEntries((utilisation?.sites || mesSites()).map(s => [s.id, s.nom]));
  const recharger = async () => { await chargerComptes(); Sync.planifier(300); render(); };

  // ---------- liste des membres ----------
  function carteMembre(m, tous) {
    const a = acces(m), echues = Calculs.habilitationsEchues(m, jour()), chefDe = equipes().filter(e => e.chefId === m.id);
    const doublon = gere() && Calculs.doublonsNom(m.nom, tous, m.id).length;
    return `<a class="card" href="#/membre/${esc(m.id)}"><div class="row"><span class="t grow">${esc(m.nom)}${compteDe(m.id)?.admin_client ? ' ★' : ''}</span>${a ? badge(a[0], a[1]) : ''}</div>
      <div class="s">${esc(L.role[m.role] || m.role || '')}${chefDe.length ? ' · chef d’équipe' : ''}${m.telephone ? ' · ' + esc(m.telephone) : ''}
        ${echues.length ? ' ' + badge(echues.map(h => h.libelle).join(', ') + ' échue', 'amber') : ''}${doublon ? ' ' + badge('doublon possible', 'amber') : ''}${m.actif === false ? ' ' + badge('inactif', 'red') : ''}</div></a>`;
  }
  V.membres = r => {
    const f = r.q.get('f') || 'tous', tous = membres();
    const F = {
      tous: m => m.actif !== false, acces: m => m.actif !== false && compteDe(m.id)?.actif, sans: m => m.actif !== false && !compteDe(m.id)?.actif,
      presta: m => m.actif !== false && (m.role === 'prestataire' || !!m.societeId), inactifs: m => m.actif === false };
    const l = tous.filter(F[f] || F.tous).sort((a, b) => (a.nom || '').localeCompare(b.nom || ''));
    const nb = k => tous.filter(F[k]).length;
    // Groupes : équipes, puis sans équipe (internes), puis prestataires par société.
    const eqs = equipes(), dejaVu = new Set(), groupes = [];
    for (const e of eqs) {
      const g = l.filter(m => !m.societeId && Calculs.equipesDe(m.id, [e]).length);
      g.forEach(m => dejaVu.add(m.id));
      if (g.length) groupes.push([e.nom, g]);
    }
    const sans = l.filter(m => !m.societeId && !dejaVu.has(m.id));
    if (sans.length) groupes.push([eqs.length ? 'Sans équipe' : 'Interne', sans]);
    const parSoc = {};
    for (const m of l.filter(m => m.societeId)) (parSoc[m.societeId] = parSoc[m.societeId] || []).push(m);
    for (const [sid, g] of Object.entries(parSoc)) groupes.push(['Prestataire · ' + (nomSociete(sid) || 'société inconnue'), g]);
    const places = utilisation ? `${utilisation.actifs}${utilisation.maxTotal == null ? '' : ' / ' + utilisation.maxTotal} accès` : '';
    return `<h1>Membres ${places ? `<span class="small muted" style="float:right;font-weight:400">${esc(places)}</span>` : ''}</h1>
      ${seg([['#/membres', `Tous ${nb('tous')}`, 'tous'], ...(connecte() && gere() ? [['#/membres?f=acces', `Avec accès ${nb('acces')}`, 'acces'], ['#/membres?f=sans', `Sans accès ${nb('sans')}`, 'sans']] : []),
        ['#/membres?f=presta', `Prestataires ${nb('presta')}`, 'presta'], ['#/membres?f=inactifs', `Inactifs ${nb('inactifs')}`, 'inactifs']], f)}
      ${search('#lst', 'Chercher un nom, un téléphone')}
      <div id="lst">${groupes.length ? groupes.map(([titre, g]) => `<h3 class="sous">${esc(titre)}</h3>${g.map(m => carteMembre(m, tous)).join('')}`).join('') : empty('Aucun membre.')}</div>
      <div class="actions">${gere() ? '<button class="btn primary" data-act="membre-new">+ Ajouter un membre</button>' : ''}<a class="btn" href="#/equipes">Équipes</a>${gere() ? '<a class="btn" href="#/societes">Sociétés</a>' : ''}</div>`;
  };
  AFTER.membres = async () => {
    if (!aRelire() || chargement) return;
    const ecran = location.hash;
    if (await chargerComptes() && location.hash === ecran && !document.querySelector('dialog[open]')) render();
  };

  // ---------- ajouter / modifier un membre ----------
  const optSocietes = () => ({ '': 'Interne', ...Object.fromEntries(societes().map(s => [s.id, s.nom])), nouvelle: '+ Nouvelle société' });
  const optEquipes = () => Object.fromEntries(equipes().map(e => [e.id, e.nom]));
  async function societeChoisie(v) {
    if (v !== 'nouvelle') return v || null;
    const s = await askForm({ title: 'Nouvelle société prestataire', ok: 'Créer', fields: [{ name: 'nom', label: 'Nom de la société', type: 'text', required: true }] });
    if (!s) return undefined;
    const soc = { id: Store.uid(), nom: s.nom, prestataire: true, actif: true };
    await Store.save('fournisseurs', soc);
    return soc.id;
  }
  /** Les équipes d'un membre se lisent sur l'équipe : on met à jour les équipes concernées. */
  async function majEquipes(pid, ids) {
    for (const e of equipes()) {
      const dedans = (e.membreIds || []).includes(pid), veut = ids.includes(e.id);
      if (dedans !== veut) await Store.save('equipes', { ...e, membreIds: veut ? [...(e.membreIds || []), pid] : e.membreIds.filter(x => x !== pid) });
    }
  }
  A['membre-new'] = async () => {
    if (!gere()) { toast('Réservé au responsable et à l’administrateur'); return; }
    const avecAcces = connecte() && admin();
    const v = await askForm({ title: 'Ajouter un membre', ok: 'Ajouter', values: { role: 'technicien', societeId: '', sites: siteActif() && siteActif() !== 'tous' ? [siteActif()] : [] }, fields: [
      { name: 'nom', label: 'Nom', type: 'text', required: true },
      { name: 'role', label: 'Rôle', type: 'chips', options: L.role, required: true },
      { name: 'societeId', label: 'Société', type: 'chips', options: optSocietes() },
      ...(equipes().length ? [{ name: 'equipes', label: 'Équipe', type: 'chipsMulti', options: optEquipes() }] : []),
      { name: 'telephone', label: 'Téléphone', type: 'tel' },
      ...(avecAcces ? [{ name: 'acces', label: 'Lui donner un accès à l’appli', type: 'checkbox' },
        { name: 'email', label: 'E-mail (si accès)', type: 'email' },
        { name: 'sites', label: 'Sites (si accès)', type: 'chipsMulti', options: sitesOpts() }] : [])] });
    if (!v) return;
    const dbl = Calculs.doublonsNom(v.nom, membres());
    if (dbl.length && await askForm({ title: 'Membre déjà présent ?', ok: 'Ouvrir sa fiche', cancel: 'Non, créer quand même',
      fields: [{ type: 'info', text: `« ${dbl[0].nom} » (${L.role[dbl[0].role] || ''}) existe déjà. Si c’est la même personne, ouvrez sa fiche : cela évite un doublon.` }] })) {
      location.hash = '#/membre/' + dbl[0].id; return;
    }
    if (v.acces && (!v.email || !v.sites?.length)) { await alertBox('Accès incomplet', ['Pour donner un accès : e-mail et au moins un site. Le membre est créé sans accès ; « Donner un accès » reste possible sur sa fiche.']); v.acces = false; }
    const societeId = await societeChoisie(v.societeId);
    if (societeId === undefined) return;
    const m = { id: Store.uid(), nom: v.nom, role: v.role, societeId, telephone: v.telephone, actif: true, habilitations: [] };
    await Store.save('personnes', m);
    if (v.equipes?.length) await majEquipes(m.id, v.equipes);
    if (v.acces) await donnerAcces(m, v.email, v.sites);
    location.hash = '#/membre/' + m.id;
  };
  A['membre-edit'] = async el => {
    const m = data.personnes.get(el.dataset.id);
    const soi = m.id === Store.currentUser()?.id;
    if (!gere() && !soi) return;
    const lie = !!compteDe(m.id) || (soi && connecte());
    const v = await askForm({ title: 'Modifier le membre', values: { ...m, societeId: m.societeId || '', equipes: Calculs.equipesDe(m.id, equipes()).map(e => e.id) }, fields: [
      { name: 'nom', label: 'Nom', type: 'text', required: true },
      ...(gere() && !lie ? [{ name: 'role', label: 'Rôle', type: 'chips', options: L.role, required: true }] : []),
      ...(gere() && lie ? [{ type: 'info', text: 'Rôle d’un membre avec accès : par l’administrateur, bloc « Accès à l’appli ».' }] : []),
      ...(gere() ? [{ name: 'societeId', label: 'Société', type: 'chips', options: optSocietes() }] : []),
      ...(gere() && equipes().length ? [{ name: 'equipes', label: 'Équipes', type: 'chipsMulti', options: optEquipes() }] : []),
      { name: 'telephone', label: 'Téléphone', type: 'tel' }] });
    if (!v) return;
    const patch = { nom: v.nom, telephone: v.telephone };
    if (gere()) {
      const societeId = await societeChoisie(v.societeId);
      if (societeId === undefined) return;
      patch.societeId = societeId;
      if (!lie) patch.role = v.role;
      if (v.equipes) await majEquipes(m.id, v.equipes);
    }
    if (lie) luLe = 0;   // le nom du compte suit : relire
    await edit('personnes', m.id, patch);
  };
  A['membre-actif'] = async el => {
    const m = data.personnes.get(el.dataset.id);
    const c = compteDe(m.id);
    if (m.actif !== false && c?.actif) { await alertBox('Accès encore actif', ['Retirez d’abord son accès à l’appli (bloc « Accès à l’appli »), puis rendez le membre inactif.']); return; }
    if (m.actif !== false && !(await askConfirm('Rendre inactif', `${m.nom} n’apparaîtra plus dans les choix (intervenants, équipes). Son historique est conservé.`, 'Rendre inactif'))) return;
    await edit('personnes', m.id, { actif: m.actif === false });
  };

  // ---------- habilitations ----------
  async function formHabilitation(m, h = null) {
    const connue = h && Object.values(HABILITATIONS).includes(h.libelle);
    const v = await askForm({ title: h ? 'Habilitation' : 'Nouvelle habilitation', values: h ? { choix: connue ? Object.keys(HABILITATIONS).find(k => HABILITATIONS[k] === h.libelle) : 'autre', libelle: connue ? '' : h.libelle, echeance: h.echeance, supprimer: false } : { choix: 'B1V' }, fields: [
      { name: 'choix', label: 'Habilitation', type: 'chips', options: HABILITATIONS, required: true },
      { name: 'libelle', label: 'Libellé (si « Autre »)', type: 'text' },
      { name: 'echeance', label: 'Échéance', type: 'date' },
      ...(h ? [{ name: 'supprimer', label: 'Supprimer cette habilitation', type: 'checkbox' }] : [])] });
    if (!v) return;
    const libelle = v.choix === 'autre' ? v.libelle : HABILITATIONS[v.choix];
    if (!libelle) { toast('Indiquez le libellé'); return; }
    const liste = (m.habilitations || []).filter(x => !h || x.id !== h.id);
    if (!v.supprimer) liste.push({ id: h?.id || Store.uid(), libelle, echeance: v.echeance || null });
    await edit('personnes', m.id, { habilitations: liste });
  }
  A['hab-new'] = el => gere() && formHabilitation(data.personnes.get(el.dataset.id));
  A['hab-edit'] = el => { const m = data.personnes.get(el.dataset.id); return gere() && formHabilitation(m, (m.habilitations || []).find(h => h.id === el.dataset.sub)); };

  // ---------- accès à l'appli (administrateur) ----------
  /** La fiche du membre doit être sur le serveur avant d'y relier un compte (créée à l'instant ou hors ligne). */
  async function ficheEnvoyee(id) {
    const enAttente = () => [...data.sortie.values()].some(s => s.rid === id);
    for (let i = 0; i < 12 && enAttente(); i++) { await Sync.synchroniser(); if (enAttente()) await new Promise(r => setTimeout(r, 500)); }
    return !enAttente();
  }
  async function donnerAcces(m, email, sites) {
    if (!(await ficheEnvoyee(m.id))) {
      await alertBox('Pas encore possible', ['Le membre n’est pas encore enregistré sur le serveur (hors ligne ?). Réessayez « Donner un accès » une fois la synchronisation faite.']);
      return;
    }
    let userId = null, envoye = false;
    try {
      toast('Envoi de l’invitation…');
      const rep = await Sync.inviter({ email, role: m.role || 'technicien', nom: m.nom, sites, redirectTo: adressePublique() });
      userId = rep.userId; envoye = rep.emailEnvoye;
    } catch (e) {
      // Compte déjà dans l'entreprise (par exemple une invitation d'avant R3) : on propose de le relier à ce membre.
      await chargerComptes();
      const c = /déjà partie/.test(e.message) && (comptes || []).find(x => (x.email || '').toLowerCase() === email.trim().toLowerCase());
      if (!c) { await alertBox('Accès refusé', [e.message]); await recharger(); return; }
      if (c.personne_id === m.id) { toast('Ce compte est déjà relié à ce membre'); await recharger(); return; }
      if (!(await askConfirm('Compte déjà présent', `${email} a déjà un accès (${c.nom || email}). Le relier à ce membre ? Son ancienne fiche deviendra inactive (historique conservé).`, 'Relier'))) return;
      userId = c.user_id;
    }
    try {
      await Sync.relierMembre(userId, m.id);
      await alertBox('Accès donné', [envoye ? `E-mail envoyé à ${email} : la personne choisit son mot de passe et arrive sur sa fiche.` : `${email} est maintenant relié à ce membre.`]);
    } catch (e) { await alertBox('Compte créé, mais pas encore relié', [e.message, 'Réessayez « Donner un accès » avec le même e-mail : le compte sera relié à ce membre.']); }
    await recharger();
  }
  A['acces-donner'] = async el => {
    if (!admin()) { toast('Réservé à l’administrateur de l’entreprise'); return; }
    const m = data.personnes.get(el.dataset.id);
    const plein = utilisation && utilisation.maxTotal != null && utilisation.actifs >= utilisation.maxTotal;
    if (plein) { await alertBox('Plus de place dans le pack', ['Toutes les places sont prises : retirez un accès ou changez de pack.']); return; }
    const v = await askForm({ title: `Donner un accès — ${m.nom}`, ok: 'Envoyer l’invitation', values: { sites: siteActif() && siteActif() !== 'tous' ? [siteActif()] : [] }, fields: [
      { name: 'email', label: 'E-mail', type: 'email', required: true },
      { name: 'sites', label: 'Sites', type: 'chipsMulti', options: sitesOpts() },
      { type: 'info', text: `Rôle : ${L.role[m.role] || m.role}. La personne reçoit un e-mail, choisit son mot de passe et arrive dans l’appli, sur ses sites.` }] });
    if (!v) return;
    if (!v.sites.length) { toast('Choisissez au moins un site'); return; }
    await donnerAcces(m, v.email, v.sites);
  };
  const compteCible = el => (comptes || []).find(c => c.user_id === el.dataset.user);
  A['acces-sites'] = async el => {
    const c = compteCible(el);
    const actuels = (utilisation?.affectations || []).filter(a => a.userId === c.user_id).map(a => a.siteId);
    const v = await askForm({ title: 'Sites autorisés', values: { sites: actuels }, fields: [{ name: 'sites', label: 'Sites', type: 'chipsMulti', options: sitesOpts() }] });
    if (!v) return;
    try { await Sync.affecterSites(c.user_id, v.sites); toast('Sites mis à jour'); } catch (e) { await alertBox('Affectation refusée', [e.message]); }
    await recharger();
  };
  A['acces-role'] = async el => {
    const c = compteCible(el);
    const v = await askForm({ title: 'Rôle', values: { role: c.role }, fields: [{ name: 'role', label: 'Rôle', type: 'chips', options: L.role, required: true }] });
    if (!v || v.role === c.role) return;
    try { await Sync.definirProfil(c.user_id, v.role, c.nom, c.actif); toast('Rôle mis à jour'); } catch (e) { await alertBox('Modification refusée', [e.message]); }
    await recharger();
  };
  A['acces-admin'] = async el => {
    const c = compteCible(el), donner = !c.admin_client;
    if (!(await askConfirm(donner ? 'Donner le droit administrateur' : 'Retirer le droit administrateur',
      `${c.nom || c.email} ${donner ? 'pourra' : 'ne pourra plus'} donner des accès, changer les rôles et les sites, modifier les règles de l’entreprise.`, donner ? 'Donner' : 'Retirer'))) return;
    try { await Sync.definirAdminClient(c.user_id, donner); toast(donner ? 'Droit administrateur donné' : 'Droit administrateur retiré'); if (c.user_id === Sync.profil()?.userId) await Sync.chargerProfil(); }
    catch (e) { await alertBox('Modification refusée', [e.message]); }
    await recharger();
  };
  A['acces-lien'] = async el => {
    const c = compteCible(el);
    try { await Sync.demanderLien(c.email, adressePublique()); toast('Lien de connexion envoyé à ' + c.email); } catch (e) { await alertBox('Envoi impossible', [e.message]); }
  };
  A['acces-actif'] = async el => {
    const c = compteCible(el), retirer = c.actif;
    if (retirer && !(await askConfirm('Retirer l’accès', `${c.nom || c.email} ne pourra plus se connecter. Le membre reste (affectations et historique conservés) et sa place est libérée.`, 'Retirer l’accès'))) return;
    try { await Sync.definirProfil(c.user_id, c.role, c.nom, !retirer); toast(retirer ? 'Accès retiré' : 'Accès rétabli'); } catch (e) { await alertBox('Modification refusée', [e.message]); }
    await recharger();
  };
  function blocAcces(m) {
    if (!connecte()) return '<p class="small muted" style="margin:0">Les accès à l’appli se gèrent une fois connecté à un compte.</p>';
    if (!gere()) return '';
    if (comptes === null) return '<p class="small muted" style="margin:0">Chargement…</p>';
    const c = compteDe(m.id), moi = c && c.user_id === Sync.profil()?.userId;
    if (!c) return `<div class="row"><span class="grow">${badge('Sans accès')}</span>${admin() ? `<button class="btn sm primary" data-act="acces-donner" data-id="${esc(m.id)}">Donner un accès</button>` : ''}</div>
      ${admin() ? '' : '<p class="small muted">Donner un accès : réservé à l’administrateur de l’entreprise.</p>'}`;
    const sites = (utilisation?.affectations || []).filter(a => a.userId === c.user_id).map(a => sitesOpts()[a.siteId]).filter(Boolean);
    const k = `data-user="${esc(c.user_id)}"`;
    return `<p style="margin:0">${badge(c.actif ? 'Actif' : 'Accès retiré', c.actif ? 'green' : 'red')}${c.admin_client ? ' ' + badge('★ administrateur', 'blue') : ''} ${esc(c.email)}<br>
        <span class="small muted">${esc(L.role[c.role] || c.role)} · ${esc(sites.join(', ') || 'aucun site')}</span></p>
      ${admin() ? `<div class="actions" style="margin-bottom:0">${c.actif ? `${moi ? '' : `<button class="btn sm" data-act="acces-role" ${k}>Rôle</button><button class="btn sm" data-act="acces-sites" ${k}>Sites</button>`}
        <button class="btn sm ${c.admin_client ? '' : 'ghost'}" data-act="acces-admin" ${k}>${c.admin_client ? '★ Admin' : '☆ Admin'}</button>
        <button class="btn sm ghost" data-act="acces-lien" ${k}>Renvoyer un lien de connexion</button>
        ${moi ? '' : `<button class="btn sm ghost danger" data-act="acces-actif" ${k}>Retirer l’accès</button>`}` : `<button class="btn sm" data-act="acces-actif" ${k}>Rétablir l’accès</button>`}</div>` : ''}`;
  }

  // ---------- fiche membre ----------
  V.membre = r => {
    const m = data.personnes.get(r.id);
    if (!m) return empty('Membre introuvable.');
    const soi = m.id === Store.currentUser()?.id, eqs = Calculs.equipesDe(m.id, equipes());
    const ots = list('ots').filter(o => (o.intervenants || []).some(i => i.personneId === m.id));
    const enCours = ots.filter(o => otOuvert(o) && actifs(o).some(i => i.personneId === m.id)).length;
    const mois = ots.filter(o => (o.creeLe || '').slice(0, 7) === jour().slice(0, 7)).length;
    const dbl = gere() ? Calculs.doublonsNom(m.nom, membres(), m.id) : [];
    return `<h1>${esc(m.nom)}</h1>
      <div class="card"><div class="row"><span class="grow">${esc(L.role[m.role] || m.role || '')} · ${m.societeId ? `<a href="#/societe/${esc(m.societeId)}">${esc(nomSociete(m.societeId) || 'société')}</a>` : 'Interne'}${eqs.length ? ' · ' + eqs.map(e => `<a href="#/equipe/${esc(e.id)}">${esc(e.nom)}</a>`).join(', ') : ''}</span>
        ${gere() || soi ? `<button class="btn sm" data-act="membre-edit" data-id="${esc(m.id)}">Modifier</button>` : ''}</div>
        ${m.telephone ? `<p style="margin:8px 0 0">📞 ${telLien(m.telephone)}</p>` : ''}
        ${m.actif === false ? `<p class="warn small">Membre inactif (historique conservé).</p>` : ''}
        ${dbl.length ? `<p class="warn small">Doublon possible : ${dbl.map(x => `<a href="#/membre/${esc(x.id)}">${esc(x.nom)}</a>`).join(', ')}. Rendez inactive la fiche en trop (l’historique reste).</p>` : ''}</div>
      ${gere() ? `<h2>Accès à l’appli</h2><div class="card">${blocAcces(m)}</div>` : ''}
      <h2>Habilitations</h2><div class="card">${(m.habilitations || []).length ? `<ul class="lines">${m.habilitations.map(h => `<li><span class="grow">${esc(h.libelle)} <span class="small muted">${h.echeance ? (Calculs.habilitationEchue(h, jour()) ? '' : 'jusqu’au ') + esc(App.fmtY(h.echeance)) : 'sans échéance'}</span> ${Calculs.habilitationEchue(h, jour()) ? badge('échue', 'amber') : ''}</span>${gere() ? `<button class="btn sm ghost" data-act="hab-edit" data-id="${esc(m.id)}" data-sub="${esc(h.id)}">Modifier</button>` : ''}</li>`).join('')}</ul>` : '<p class="small muted" style="margin:0 0 8px">Aucune habilitation renseignée.</p>'}
        ${gere() ? `<button class="btn sm" data-act="hab-new" data-id="${esc(m.id)}">+ Habilitation</button>` : ''}</div>
      <h2>Travaux</h2><div class="card"><div class="row"><span class="grow">${enCours} en cours · ${mois} ce mois</span><a class="btn sm" href="#/ots?f=membre&m=${encodeURIComponent(m.id)}">Voir</a></div></div>
      ${gere() ? `<div class="actions"><button class="btn ghost" data-act="membre-actif" data-id="${esc(m.id)}">${m.actif === false ? 'Rendre actif' : 'Rendre inactif'}</button></div>` : ''}
      <div class="actions"><a class="btn ghost" href="#/membres">← Membres</a></div>`;
  };
  AFTER.membre = AFTER.membres;

  // ---------- équipes ----------
  V.equipes = () => {
    const l = equipes();
    return `<h1>Équipes</h1>
      ${l.length ? l.map(e => `<a class="card" href="#/equipe/${esc(e.id)}"><div class="row"><span class="t grow">${esc(e.nom)}</span><span class="small muted">${(e.membreIds || []).length} membre(s)</span></div>
        <div class="s">${e.chefId ? 'chef : ' + esc(nomMembre(e.chefId)) : 'sans chef d’équipe'}${e.siteId ? ' · ' + esc(App.nomSite(e.siteId) || '') : ''}</div></a>`).join('') : empty('Aucune équipe. Exemples : Mécanique, Électrique, Équipe de nuit.')}
      <div class="actions">${gere() ? '<button class="btn primary" data-act="eqp-new">+ Nouvelle équipe</button>' : ''}<a class="btn ghost" href="#/membres">← Membres</a></div>`;
  };
  async function formEquipe(e = null) {
    const actifsM = membres().filter(m => m.actif !== false).sort((a, b) => (a.nom || '').localeCompare(b.nom || ''));
    const v = await askForm({ title: e ? 'Modifier l’équipe' : 'Nouvelle équipe', values: e ? { ...e, siteId: e.siteId || '', inactive: false } : { siteId: '' }, fields: [
      { name: 'nom', label: 'Nom', type: 'text', required: true },
      { name: 'chefId', label: 'Chef d’équipe', type: 'select', options: actifsM.map(m => [m.id, m.nom]), empty: '— Aucun —' },
      { name: 'membreIds', label: 'Membres', type: 'chipsMulti', options: Object.fromEntries(actifsM.map(m => [m.id, m.nom])) },
      ...(mesSites().length > 1 ? [{ name: 'siteId', label: 'Site', type: 'chips', options: { '': 'Tous les sites', ...Object.fromEntries(mesSites().map(s => [s.id, s.nom])) } }] : []),
      ...(e ? [{ name: 'inactive', label: 'Supprimer l’équipe (les interventions passées gardent leur trace)', type: 'checkbox' }] : [])] });
    if (!v) return;
    const membreIds = [...new Set([...(v.membreIds || []), ...(v.chefId ? [v.chefId] : [])])];
    const fiche = { ...(e || { id: Store.uid() }), nom: v.nom, chefId: v.chefId, membreIds, siteId: v.siteId || null, actif: !v.inactive };
    await Store.save('equipes', fiche);
    location.hash = v.inactive ? '#/equipes' : '#/equipe/' + fiche.id;
    render();
  }
  A['eqp-new'] = () => gere() ? formEquipe() : toast('Réservé au responsable et à l’administrateur');
  A['eqp-edit'] = el => gere() && formEquipe(data.equipes.get(el.dataset.id));
  V.equipe = r => {
    const e = data.equipes.get(r.id);
    if (!e) return empty('Équipe introuvable.');
    const ms = (e.membreIds || []).map(id => data.personnes.get(id)).filter(Boolean);
    const ouverts = list('ots').filter(o => otOuvert(o) && o.equipeId === e.id).length;
    return `<h1>${esc(e.nom)}</h1>
      <div class="card"><div class="row"><span class="grow">${e.chefId ? 'Chef : <a href="#/membre/' + esc(e.chefId) + '">' + esc(nomMembre(e.chefId)) + '</a>' : 'Sans chef d’équipe'}${e.siteId ? ' · ' + esc(App.nomSite(e.siteId) || '') : ''}</span>
        ${gere() ? `<button class="btn sm" data-act="eqp-edit" data-id="${esc(e.id)}">Modifier</button>` : ''}</div></div>
      <h2>Membres (${ms.length})</h2>${ms.length ? ms.map(m => `<a class="card" href="#/membre/${esc(m.id)}"><div class="t">${esc(m.nom)}${m.id === e.chefId ? ' · chef' : ''}</div><div class="s">${esc(L.role[m.role] || '')}${m.telephone ? ' · ' + esc(m.telephone) : ''}</div></a>`).join('') : empty('Aucun membre.')}
      <h2>Travaux confiés</h2><div class="card"><div class="row"><span class="grow">${ouverts} ouvert(s)</span><a class="btn sm" href="#/ots?f=equipe&e=${encodeURIComponent(e.id)}">Voir</a></div></div>
      <div class="actions"><a class="btn ghost" href="#/equipes">← Équipes</a></div>`;
  };

  // ---------- sociétés (prestataires et fournisseurs : une seule fiche) ----------
  V.societes = r => {
    if (!gere()) return empty('Sociétés : réservé au responsable et à l’administrateur.');
    const f = r.q.get('f') || 'prestataire';
    const l = societes(f);
    return `<h1>Sociétés</h1>${seg([['#/societes', 'Prestataires', 'prestataire'], ['#/societes?f=fournisseur', 'Fournisseurs', 'fournisseur'], ['#/societes?f=tous', 'Toutes', 'tous']], f)}
      ${search('#lst', 'Chercher une société')}
      <div id="lst">${l.length ? l.map(s => `<a class="card" href="#/societe/${esc(s.id)}"><div class="row"><span class="t grow">${esc(s.nom)}</span>${contratEchu(s) ? badge('contrat échu', 'amber') : ''}</div>
        <div class="s">${[s.prestataire && 'prestataire', s.fournisseur && 'fournisseur'].filter(Boolean).join(' · ') || 'fournisseur'}${s.contact ? ' · ' + esc(s.contact) : ''}${s.telephone ? ' · ' + esc(s.telephone) : ''}</div></a>`).join('') : empty('Aucune société.')}</div>
      <div class="actions"><button class="btn primary" data-act="soc-new">+ Nouvelle société</button><a class="btn ghost" href="#/membres">← Membres</a></div>`;
  };
  async function formSociete(s = null) {
    const v = await askForm({ title: s ? 'Modifier la société' : 'Nouvelle société', values: s ? { ...s, inactive: false } : { prestataire: true }, fields: [
      { name: 'nom', label: 'Nom', type: 'text', required: true },
      { name: 'prestataire', label: 'Prestataire (intervient sur le parc)', type: 'checkbox' },
      { name: 'fournisseur', label: 'Fournisseur (pièces, achats)', type: 'checkbox' },
      { name: 'contact', label: 'Contact', type: 'text' },
      { name: 'telephone', label: 'Téléphone', type: 'tel' },
      { name: 'email', label: 'E-mail', type: 'email' },
      { name: 'contratRef', label: 'Référence du contrat', type: 'text' },
      { name: 'contratFin', label: 'Fin du contrat', type: 'date' },
      { name: 'remarques', label: 'Remarques', type: 'textarea' },
      ...(s ? [{ name: 'inactive', label: 'Société inactive (n’apparaît plus dans les choix)', type: 'checkbox' }] : [])] });
    if (!v) return;
    if (!v.prestataire && !v.fournisseur) v.fournisseur = true;
    const { inactive, ...champs } = v;
    const fiche = { ...(s || { id: Store.uid() }), ...champs, actif: !inactive };
    await Store.save('fournisseurs', fiche);
    location.hash = '#/societe/' + fiche.id;
    render();
  }
  A['soc-new'] = () => gere() ? formSociete() : toast('Réservé au responsable et à l’administrateur');
  A['soc-edit'] = el => gere() && formSociete(data.fournisseurs.get(el.dataset.id));
  V.societe = r => {
    const s = data.fournisseurs.get(r.id);
    if (!s) return empty('Société introuvable.');
    const ms = membres().filter(m => m.societeId === s.id && m.actif !== false);
    const ouverts = list('ots').filter(o => otOuvert(o) && o.societeId === s.id).length;
    return `<h1>${esc(s.nom)}</h1>
      <div class="card"><dl class="kv">
        <dt>Type</dt><dd>${[s.prestataire && 'Prestataire', s.fournisseur && 'Fournisseur'].filter(Boolean).join(' · ') || 'Fournisseur'}</dd>
        ${s.contact ? `<dt>Contact</dt><dd>${esc(s.contact)}</dd>` : ''}${s.telephone ? `<dt>Téléphone</dt><dd>${telLien(s.telephone)}</dd>` : ''}${s.email ? `<dt>E-mail</dt><dd>${esc(s.email)}</dd>` : ''}
        ${s.contratRef || s.contratFin ? `<dt>Contrat</dt><dd>${esc(s.contratRef || '')}${s.contratFin ? ` · fin ${esc(App.fmtY(s.contratFin))} ${contratEchu(s) ? badge('échu', 'amber') : ''}` : ''}</dd>` : ''}
        ${s.remarques ? `<dt>Remarques</dt><dd style="white-space:pre-wrap">${esc(s.remarques)}</dd>` : ''}</dl>
        ${gere() ? `<button class="btn sm" data-act="soc-edit" data-id="${esc(s.id)}">Modifier</button>` : ''}</div>
      ${s.prestataire ? `<h2>Membres (${ms.length})</h2>${ms.length ? ms.map(m => `<a class="card" href="#/membre/${esc(m.id)}"><div class="t">${esc(m.nom)}</div><div class="s">${esc(L.role[m.role] || '')}${m.telephone ? ' · ' + esc(m.telephone) : ''}</div></a>`).join('') : empty('Aucun membre rattaché.')}
        <h2>Travaux confiés</h2><div class="card"><div class="row"><span class="grow">${ouverts} ouvert(s)</span><a class="btn sm" href="#/ots?f=societe&s=${encodeURIComponent(s.id)}">Voir</a></div></div>` : ''}
      <div class="actions"><a class="btn ghost" href="#/societes">← Sociétés</a></div>`;
  };

  // ---------- pour les autres écrans ----------
  App.membres = {
    gere,
    equipes,
    societes,
    nomSociete,
    /** Équipes de l'utilisateur de l'appareil. */
    mesEquipes: () => Calculs.equipesDe(Store.currentUser()?.id, equipes()),
    /** Société de l'utilisateur (prestataire). */
    maSociete: () => Store.currentUser()?.societeId || null,
    /** Habilitations échues d'une personne (avertissement à l'affectation). */
    echues: id => Calculs.habilitationsEchues(data.personnes.get(id), jour()),
  };
})();
