/* GMAO terrain — circuit achats, réception partielle, pièces isolées, valeur du stock (volet C, V3 §16, §17, §18).
   Perfora n'envoie aucune commande : on suit le besoin, sa validation, la commande passée ailleurs et la réception.
   Montants visibles seulement pour responsable, magasinier, achats et pilote (le serveur ne les envoie pas aux autres).
   Script classique chargé après reappro.js. */
(() => {
  const { V, A, esc, badge, empty, seg, askForm, askConfirm, askText, toast, list, render, fmtY, role, autorise, aModule, siteActif, nomSite, mesSites } = App;
  const { data } = Store;

  const STATUT = { brouillon: 'Brouillon', soumise: 'Soumise', a_completer: 'À compléter', validee: 'Validée', refusee: 'Refusée', transmise: 'Transmise aux achats',
    commandee: 'Commandée', partiellement_recue: 'Partiellement reçue', recue: 'Reçue', close: 'Close', annulee: 'Annulée' };
  const CLS = { soumise: 'blue', a_completer: 'amber', validee: 'blue', transmise: 'blue', refusee: 'red', commandee: 'blue', partiellement_recue: 'amber', recue: 'green', close: 'green' };
  const DECISION = { liberer: 'Libérer (utilisable)', retour_fournisseur: 'Retour fournisseur', rebut: 'Rebut', reparation: 'Réparation' };
  const voitCouts = () => !role() || ['responsable', 'magasinier', 'achats', 'pilote'].includes(role());
  App.voitCouts = voitCouts;
  const mvts = () => list('mouvements');
  const etat = da => Calculs.etatAchat(da, mvts());
  const q = n => Number.isInteger(n) ? n : Math.round(n * 100) / 100;
  const mad = n => n == null ? '—' : `${(Math.round(n * 100) / 100).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} MAD`;
  const nomArt = l => data.articles.get(l.articleId)?.designation || l.description || 'Article';
  const today = () => Store.now().slice(0, 10);
  const enRetard = da => ['commandee', 'partiellement_recue'].includes(etat(da)) && da.livraisonPrevue && da.livraisonPrevue < today();

  // ---------- listes ----------
  function carteAchat(da) {
    const e = etat(da), m = voitCouts() && da.lignes?.some(l => l.prixUnitaire != null) ? Calculs.montantCommande(da) : null;
    return `<a class="card" href="#/achat/${da.id}"><div class="row"><span class="t grow">${esc(da.ref)}${da.fournisseur ? ' · ' + esc(da.fournisseur) : ''}</span>${da.urgent ? badge('Urgent', 'red') : ''}${Calculs.urgentsAValider([da]).length ? badge('À valider après coup', 'amber') : ''}${enRetard(da) ? badge('En retard', 'red') : ''}${badge(STATUT[e] || e, CLS[e] || '')}</div>
      <div class="s">${(da.lignes || []).map(l => `${q(Number(l.qteCommandee ?? l.qte) || 0)} × ${esc(nomArt(l))}`).slice(0, 3).join(' · ')}${(da.lignes || []).length > 3 ? ' …' : ''}</div>
      <div class="s">${esc(fmtY(da.redigeLe || da.creeLe))} par ${esc(da.redigePar || da.creePar)}${da.livraisonPrevue ? ' · livraison prévue ' + esc(fmtY(da.livraisonPrevue)) : ''}${m ? ' · ' + mad(m.montant) + (m.complet ? '' : ' (prix incomplets)') : ''}${siteActif() === 'tous' && da.siteId ? ' · ' + esc(nomSite(da.siteId)) : ''}</div></a>`;
  }
  App.carteAchat = carteAchat;
  App.STATUT_ACHAT = STATUT;

  const GROUPES = [
    ['valider', 'À valider (responsable)', e => e === 'soumise'],
    ['commander', 'À commander', (e, d) => ['validee', 'transmise'].includes(e) || (e === 'soumise' && d.urgent)],
    ['receptionner', 'À réceptionner', e => ['commandee', 'partiellement_recue'].includes(e)],
    ['preparer', 'Brouillons et à compléter', e => ['brouillon', 'a_completer'].includes(e)],
    ['terminees', 'Terminées', e => ['recue', 'close', 'refusee', 'annulee'].includes(e)],
  ];
  V.achats = r => {
    if (!voitCouts()) return empty('Achats : réservé au responsable, au magasin, aux achats et au pilote.');
    if (!aModule('achats')) return empty('Module « achats » non inclus dans votre abonnement (pack Entreprise).');
    const das = list('achats').sort((a, b) => (b.creeLe || '').localeCompare(a.creeLe || ''));
    const f = r.q.get('f') || 'encours';
    const iso = Calculs.isolementsEnAttente(mvts());
    const groupes = GROUPES.map(([k, lab, ok]) => [k, lab, das.filter(d => ok(etat(d), d))]);
    const vus = f === 'encours' ? groupes.filter(([k, , l]) => k !== 'terminees' && l.length) : groupes.filter(([k]) => k === f);
    return `<h1>Achats</h1>
      ${seg([['#/achats', 'En cours', 'encours'], ...groupes.map(([k, lab, l]) => [`#/achats?f=${k}`, `${lab.split(' (')[0]} (${l.length})`, k])], f)}
      ${vus.length && vus.some(([, , l]) => l.length) ? vus.map(([, lab, l]) => `<h2>${esc(lab)}</h2>${l.length ? l.map(carteAchat).join('') : empty('Rien.')}`).join('') : empty('Aucune demande d’achat ici. Elles se créent depuis Magasin → À réapprovisionner.')}
      ${iso.length && f === 'encours' ? `<h2>Pièces isolées en attente de décision</h2>${iso.map(carteIsole).join('')}` : ''}
      <div class="actions"><a class="btn" href="#/reappro">À réapprovisionner</a><a class="btn" href="#/valeur">Valeur du stock</a></div>`;
  };
  function carteIsole({ m, reste }) {
    const a = data.articles.get(m.articleId), da = m.achatId ? data.achats.get(m.achatId) : null;
    return `<div class="card"><div class="row"><span class="t grow">${q(reste)} × ${esc(a?.designation || 'Article')}</span>${badge('Isolée', 'amber')}</div>
      <div class="s">Reçue le ${esc(fmtY(m.le))}${da ? ` · <a href="#/achat/${da.id}">${esc(da.ref)}</a>` : ''}${m.motif ? ' · « ' + esc(m.motif) + ' »' : ''}</div>
      <div class="actions" style="margin:8px 0 0"><button class="btn sm primary" data-act="iso-decider" data-id="${m.id}">Décider</button></div></div>`;
  }

  // ---------- détail d'une demande ----------
  V.achat = r => {
    const da = data.achats.get(r.id);
    if (!da) return empty('Demande d’achat introuvable (ou non visible avec votre rôle).');
    const e = etat(da), commandee = ['commandee', 'partiellement_recue', 'recue', 'close'].includes(e) || da.statut === 'close';
    const k = `data-id="${da.id}"`, modifiable = ['brouillon', 'a_completer'].includes(da.statut);
    const lignes = (da.lignes || []).map(l => {
      const a = data.articles.get(l.articleId), rc = Calculs.receptionLigne(da, l, mvts()), p = Calculs.prixMAD(l);
      return `<li style="display:block"><div class="row"><span class="grow">${esc(nomArt(l))} <span class="small muted">${esc(a?.ref || '')}</span></span><b>${q(Number(l.qteCommandee ?? l.qte) || 0)} ${esc(l.unite || a?.unite || '')}</b>${modifiable ? `<button class="btn sm ghost" data-act="achat-qte" ${k} data-sub="${l.id}">Modifier</button>` : ''}</div>
        <div class="small muted">${l.otId && data.ots.get(l.otId) ? `<a href="#/ot/${l.otId}">${esc(data.ots.get(l.otId).ref)}</a> · ` : ''}${l.motif ? esc(l.motif) : ''}${l.qteCommandee != null && Number(l.qteCommandee) !== Number(l.qte) ? ` · demandé ${q(Number(l.qte))}` : ''}${voitCouts() && l.prixUnitaire != null ? ` · ${p == null ? esc(l.prixUnitaire + ' ' + (l.devise || '')) + ' (sans conversion)' : mad(p)} / u` : ''}${commandee ? ` · reçu ${q(rc.recu)} (utilisable ${q(rc.utilisable)}${rc.isole ? `, isolé ${q(rc.isole)}` : ''}) · <b>reste ${q(rc.reliquat)}</b>` : ''}</div></li>`;
    }).join('');
    const m = voitCouts() ? Calculs.montantCommande(da) : null;
    const reliquat = (da.lignes || []).reduce((s, l) => s + Calculs.receptionLigne(da, l, mvts()).reliquat, 0);
    const act = [];
    if (modifiable) act.push(`<button class="btn primary" data-act="achat-soumettre" ${k}>Soumettre au responsable</button>`);
    if (da.statut === 'soumise') act.push(`<button class="btn primary" data-act="achat-valider" ${k}>Valider</button><button class="btn" data-act="achat-completer" ${k}>À compléter</button><button class="btn ghost danger" data-act="achat-refuser" ${k}>Refuser</button>`);
    if (['validee', 'transmise'].includes(da.statut) || (da.statut === 'soumise' && da.urgent)) act.push(`<button class="btn ${da.statut === 'soumise' ? '' : 'primary'}" data-act="achat-commande" ${k}>Renseigner la commande${da.statut === 'soumise' ? ' (urgent, avant validation)' : ''}</button>`);
    if (Calculs.urgentsAValider([da]).length && da.statut !== 'soumise') act.push(`<button class="btn primary" data-act="achat-valider-apres" ${k}>Valider après coup</button><button class="btn ghost danger" data-act="achat-refuser-apres" ${k}>Refuser après coup</button>`);
    if (['commandee', 'partiellement_recue'].includes(e)) act.push(`<button class="btn primary" data-act="achat-recevoir" ${k}>Réceptionner</button>`);
    if (['commandee', 'partiellement_recue', 'recue'].includes(e) && da.statut !== 'close') act.push(`<button class="btn ghost" data-act="achat-clore" ${k}>Clore</button>`);
    if (['brouillon', 'soumise', 'a_completer'].includes(da.statut)) act.push(`<button class="btn ghost danger" data-act="achat-annuler" ${k}>Annuler</button>`);
    const jal = [
      da.soumiseLe && `Soumise le ${fmtY(da.soumiseLe)} par ${da.soumisePar}`,
      da.urgent && `Urgente : « ${da.motifUrgence || ''} »`,
      da.valideLe && `Validée${da.valideApresCoup ? ' après coup' : ''} le ${fmtY(da.valideLe)} par ${da.validePar}`,
      da.refusApresCoup && `Refusée après coup le ${fmtY(da.refuseApresCoupLe)} par ${da.refuseApresCoupPar} : « ${da.refusApresCoup} »`,
      da.motifCompletion && da.statut === 'a_completer' && `À compléter : « ${da.motifCompletion} »`,
      da.motifRefus && `Refusée : « ${da.motifRefus} »`,
      da.commandeLe && `Commande saisie le ${fmtY(da.commandeLe)} par ${da.commandePar}`,
      da.closLe && `Close le ${fmtY(da.closLe)} par ${da.closPar}${da.motifCloture ? ' — « ' + da.motifCloture + ' »' : ''}`].filter(Boolean);
    return `<div class="row"><h1 class="grow">${esc(da.ref)}</h1>${enRetard(da) ? badge('En retard', 'red') : ''}${badge(STATUT[e] || e, CLS[e] || '')}</div>
      <div class="card"><div class="s">Rédigée par ${esc(da.redigePar || da.creePar)} le ${esc(fmtY(da.redigeLe || da.creeLe))}${da.siteId ? ' · ' + esc(nomSite(da.siteId)) : ''}${da.origine === 'reapprovisionnement' ? ' · depuis « À réapprovisionner »' : ''}</div>
        ${jal.map(t => `<div class="s">${esc(t)}</div>`).join('')}
        ${da.fournisseur || da.refCommande ? `<dl class="kv" style="margin-top:8px"><dt>Fournisseur</dt><dd>${esc(da.fournisseur || '—')}</dd><dt>Commande</dt><dd>${esc(da.refCommande || '—')}${da.dateCommande ? ' du ' + esc(fmtY(da.dateCommande)) : ''}</dd><dt>Livraison prévue</dt><dd>${esc(fmtY(da.livraisonPrevue))}</dd></dl>` : ''}</div>
      <h2>Lignes</h2><div class="card"><ul class="lines">${lignes || '<li class="muted">Aucune ligne.</li>'}</ul>
        ${m && (da.lignes || []).some(l => l.prixUnitaire != null) ? `<p class="small" style="margin:8px 0 0">Montant commandé : <b>${mad(m.montant)}</b> HT${m.complet ? '' : ` · ${m.sansPrix} ligne(s) sans prix (non comptées, jamais à zéro)`}</p>` : ''}
        ${commandee && reliquat > 0 ? `<p class="small muted" style="margin:4px 0 0">Reliquat attendu : ${q(reliquat)}. Une commande peut être livrée sans être entièrement acceptée.</p>` : ''}</div>
      <div class="actions">${act.join('')}</div>
      <p class="small muted">Perfora n’envoie aucune commande : la validation du besoin n’engage pas le fournisseur.</p>`;
  };

  // ---------- actions : préparation ----------
  const maj = (id, patch, opts) => Store.update('achats', id, patch, opts).then(render);
  A['achat-qte'] = async el => {
    const da = data.achats.get(el.dataset.id), l = da.lignes.find(x => x.id === el.dataset.sub);
    const v = await askForm({ title: 'Quantité demandée', values: { qte: l.qte }, fields: [{ name: 'qte', label: nomArt(l), type: 'number', required: true }] });
    if (!v || !(v.qte > 0)) return;
    await maj(da.id, { lignes: da.lignes.map(x => x.id === l.id ? { ...x, qte: v.qte } : x) }, { action: 'modification_ligne' });
  };
  A['achat-soumettre'] = async el => { await maj(el.dataset.id, { statut: 'soumise', soumiseLe: Store.now(), soumisePar: Store.currentUserName() }, { action: 'soumission' }); toast('Demande soumise au responsable'); };
  A['achat-annuler'] = async el => {
    const m = await askText('Annuler la demande d’achat', 'Motif (conservé dans le journal)');
    if (m) await maj(el.dataset.id, { statut: 'annulee', motifAnnulation: m }, { action: 'annulation', motif: m });
  };
  // ---------- actions : responsable ----------
  A['achat-valider'] = async el => {
    const da = data.achats.get(el.dataset.id);
    if (!(await askConfirm('Valider la demande d’achat', `${da.ref} : ${(da.lignes || []).length} ligne(s). La validation du besoin n’envoie aucune commande ; les achats renseigneront la commande passée.`, 'Valider'))) return;
    await maj(da.id, { statut: 'validee', valideLe: Store.now(), validePar: Store.currentUserName() }, { action: 'validation' });
    toast('Demande validée : à commander');
  };
  /** R5 : achat urgent commandé avant validation — le responsable valide (ou refuse) après coup ; tout reste au journal. */
  A['achat-valider-apres'] = async el => {
    const da = data.achats.get(el.dataset.id);
    if (!(await askConfirm('Valider après coup', `${da.ref} a été commandée en urgence (« ${da.motifUrgence || ''} »). La valider ?`, 'Valider'))) return;
    await maj(da.id, { valideLe: Store.now(), validePar: Store.currentUserName(), valideApresCoup: true }, { action: 'validation_apres_coup' });
    toast('Achat urgent validé');
  };
  A['achat-refuser-apres'] = async el => {
    const m = await askText('Refuser après coup', 'Motif (la commande reste tracée)');
    if (m) await maj(el.dataset.id, { refusApresCoup: m, refuseApresCoupLe: Store.now(), refuseApresCoupPar: Store.currentUserName() }, { action: 'refus_apres_coup', motif: m });
  };
  A['achat-completer'] = async el => {
    const m = await askText('Demande à compléter', 'Ce qu’il faut préciser (visible par le magasin)');
    if (m) await maj(el.dataset.id, { statut: 'a_completer', motifCompletion: m }, { action: 'a_completer', motif: m });
  };
  A['achat-refuser'] = async el => {
    const m = await askText('Refuser la demande d’achat', 'Motif du refus');
    if (m) await maj(el.dataset.id, { statut: 'refusee', motifRefus: m, refuseeLe: Store.now(), refuseePar: Store.currentUserName() }, { action: 'refus', motif: m });
  };
  // ---------- actions : achats (commande passée ailleurs) ----------
  A['achat-commande'] = async el => {
    const da = data.achats.get(el.dataset.id);
    const fields = [
      { name: 'fournisseurId', label: 'Fournisseur', type: 'select', options: App.fournisseursOpts ? App.fournisseursOpts() : [], empty: '— Autre (à écrire) —' },
      { name: 'fournisseur', label: 'Autre fournisseur (si absent de la liste)', type: 'text' },
      { name: 'refCommande', label: 'Référence de la commande', type: 'text', required: true },
      { name: 'dateCommande', label: 'Date de commande', type: 'date', required: true },
      { name: 'livraisonPrevue', label: 'Livraison prévue (vide : délai habituel du fournisseur)', type: 'date' },
      { name: 'devise', label: 'Devise des prix', type: 'chips', options: { MAD: 'MAD', EUR: 'EUR', USD: 'USD' }, required: true },
      { type: 'info', text: 'Quantité commandée et prix unitaire HT par ligne. Prix inconnu : laisser vide (jamais 0).' },
      ...da.lignes.flatMap(l => [
        { name: 'q_' + l.id, label: `${nomArt(l)} — quantité commandée`, type: 'number', required: true },
        { name: 'p_' + l.id, label: `${nomArt(l)} — prix unitaire HT`, type: 'number' }])];
    const values = { fournisseurId: da.fournisseurId || '', fournisseur: da.fournisseurId ? '' : da.fournisseur, refCommande: da.refCommande, dateCommande: da.dateCommande || today(), livraisonPrevue: da.livraisonPrevue, devise: da.devise || 'MAD' };
    for (const l of da.lignes) { values['q_' + l.id] = l.qteCommandee ?? l.qte; values['p_' + l.id] = l.prixUnitaire; }
    const v = await askForm({ title: 'Commande passée chez le fournisseur', ok: 'Enregistrer', values, fields });
    if (!v) return;
    const fo = v.fournisseurId ? data.fournisseurs.get(v.fournisseurId) : null;
    if (!fo && !v.fournisseur) { toast('Choisissez ou écrivez le fournisseur'); return; }
    v.fournisseur = fo?.nom || v.fournisseur;
    if (!v.livraisonPrevue && fo?.delaiJours) v.livraisonPrevue = Calculs.addDays(v.dateCommande, Number(fo.delaiJours)).slice(0, 10);
    let taux = null;
    if (v.devise !== 'MAD') {
      const t = await askForm({ title: 'Conversion en MAD', values: { taux: da.taux }, fields: [{ type: 'info', text: `Prix en ${v.devise}. Sans taux, les prix restent « non valorisés » (V3 §18 : conversion explicite).` }, { name: 'taux', label: `1 ${v.devise} = ? MAD`, type: 'number' }] });
      taux = t?.taux || null;
    }
    const lignes = da.lignes.map(l => { const p = v['p_' + l.id];
      return { ...l, qteCommandee: v['q_' + l.id], prixUnitaire: p, devise: v.devise, prixUnitaireMAD: p != null && v.devise !== 'MAD' && taux ? Math.round(p * taux * 100) / 100 : null }; });
    await maj(da.id, { statut: 'commandee', fournisseurId: fo?.id || null, fournisseur: v.fournisseur, refCommande: v.refCommande, dateCommande: v.dateCommande, livraisonPrevue: v.livraisonPrevue, devise: v.devise, taux,
      lignes, commandeLe: Store.now(), commandePar: Store.currentUserName() }, { action: 'commande_externe' });
    toast('Commande enregistrée : à réceptionner');
  };
  // ---------- actions : réception partielle (V3 §16) ----------
  A['achat-recevoir'] = async el => {
    const da = data.achats.get(el.dataset.id);
    const ouvertes = da.lignes.map(l => ({ l, rc: Calculs.receptionLigne(da, l, mvts()) })).filter(x => x.rc.reliquat > 0);
    if (!ouvertes.length) { toast('Tout est reçu'); return; }
    const values = { bl: '' };
    for (const { l, rc } of ouvertes) { values['r_' + l.id] = rc.reliquat; values['i_' + l.id] = 0; values['res_' + l.id] = true; }
    const v = await askForm({ title: 'Réception ' + da.ref, ok: 'Enregistrer la réception', values, fields: [
      { name: 'bl', label: 'Bon de livraison', type: 'text' },
      { type: 'info', text: 'Quantité reçue par ligne, dont isolée (douteuse, endommagée) : l’isolé n’entre pas dans le stock utilisable.' },
      ...ouvertes.flatMap(({ l, rc }) => [
        { name: 'r_' + l.id, label: `${nomArt(l)} — reçu (reste ${q(rc.reliquat)})`, type: 'number', required: true },
        { name: 'i_' + l.id, label: `${nomArt(l)} — dont isolé`, type: 'number' },
        ...(besoinOuvert(l) ? [{ name: 'res_' + l.id, type: 'checkbox', label: `Réserver pour ${data.ots.get(besoinOuvert(l).otId)?.ref || 'l’intervention'} (pièce attendue)` }] : [])]),
      { name: 'motifIso', label: 'Motif de l’isolement (si isolé)', type: 'text' }] });
    if (!v) return;
    for (const { l, rc } of ouvertes) {
      const r = Number(v['r_' + l.id]) || 0, i = Number(v['i_' + l.id]) || 0;
      if (r < 0 || i < 0 || i > r) { toast('L’isolé ne peut pas dépasser le reçu'); return; }
      if (r > rc.reliquat) { toast(`${nomArt(l)} : au plus ${q(rc.reliquat)} (reste attendu)`); return; }
      if (i > 0 && !v.motifIso) { toast('Indiquez le motif de l’isolement'); return; }
    }
    const le = Store.now(), motif = 'Réception ' + da.ref + (v.bl ? ' · BL ' + v.bl : '');
    let n = 0;
    for (const { l } of ouvertes) {
      const r = Number(v['r_' + l.id]) || 0, i = Number(v['i_' + l.id]) || 0;
      if (!r) continue;
      const base = { articleId: l.articleId, achatId: da.id, ligneId: l.id, le, ...(da.siteId ? { siteId: da.siteId } : {}) };
      const prix = l.prixUnitaire != null ? { prixUnitaire: l.prixUnitaire, devise: l.devise || 'MAD', ...(l.prixUnitaireMAD != null ? { prixUnitaireMAD: l.prixUnitaireMAD } : {}), statut: 'connu' } : null;
      for (const [type, extra] of [['entree', { qte: r - i, motif }], ['isolement', { qte: 0, quantite: i, motif: v.motifIso }]]) {
        if ((type === 'entree' ? r - i : i) <= 0) continue;
        const m = { id: Store.uid(), type, ...base, ...extra };
        await Store.save('mouvements', m, { action: type === 'entree' ? 'reception' : 'isolement' });
        if (prix) await Store.save('valorisations', { id: Store.uid(), mouvementId: m.id, ...(da.siteId ? { siteId: da.siteId } : {}), ...prix }, { action: 'prix_reception' });
      }
      n++;
    }
    // R5 : la pièce attendue par une intervention est réservée pour elle (jamais au-delà du reçu utilisable).
    const reservees = [];
    for (const { l } of ouvertes) {
      const b = besoinOuvert(l), utilisable = (Number(v['r_' + l.id]) || 0) - (Number(v['i_' + l.id]) || 0);
      if (!b || !v['res_' + l.id] || utilisable <= 0 || !App.reserverBesoin) continue;
      const reste = Calculs.besoinsEnAttenteArticle([b], mvts(), b.articleId, null)[0]?.reste ?? Math.max(0, Number(b.qte) - (Number(b.qteReservee) || 0));
      if (reste > 0) { await App.reserverBesoin(b, Math.min(reste, utilisable)); reservees.push(b.id); }
    }
    toast(n ? `Réception enregistrée${reservees.length ? ` · ${reservees.length} pièce(s) réservée(s) pour leur intervention` : ''}` : 'Rien de reçu');
    // Reste du stock reçu : proposer aux autres pièces en attente de ces articles.
    if (App.proposerReservations) for (const art of new Set(ouvertes.map(x => x.l.articleId).filter(Boolean))) await App.proposerReservations(art, da.siteId, { exclure: reservees });
    render();
  };
  /** Pièce (besoin) encore attendue liée à une ligne de commande. */
  function besoinOuvert(l) {
    const b = l.besoinId ? data.besoins.get(l.besoinId) : null;
    return b && b.articleId && ['demande', 'indisponible', 'reserve', 'partiellement_remis'].includes(Calculs.etatBesoin(b, mvts())) ? b : null;
  }
  A['achat-clore'] = async el => {
    const da = data.achats.get(el.dataset.id);
    const reliquat = (da.lignes || []).reduce((s, l) => s + Calculs.receptionLigne(da, l, mvts()).reliquat, 0);
    let motif = null;
    if (reliquat > 0) { motif = await askText('Clore avec un reliquat', `${q(reliquat)} encore attendu(s). Motif (annulé chez le fournisseur, abandonné…)`); if (!motif) return; }
    else if (!(await askConfirm('Clore la demande', 'Tout est reçu. Clore la demande d’achat ?', 'Clore'))) return;
    await maj(da.id, { statut: 'close', closLe: Store.now(), closPar: Store.currentUserName(), ...(motif ? { motifCloture: motif } : {}) }, { action: 'cloture', motif });
  };
  // ---------- pièces isolées (V3 §16 : décision tracée) ----------
  A['iso-decider'] = async el => {
    const x = Calculs.isolementsEnAttente(mvts()).find(y => y.m.id === el.dataset.id);
    if (!x) return;
    const a = data.articles.get(x.m.articleId);
    const v = await askForm({ title: 'Décision sur pièce isolée', ok: 'Enregistrer', values: { decision: 'liberer', qte: x.reste }, fields: [
      { type: 'info', text: `${q(x.reste)} × ${a?.designation || 'Article'} isolée(s)${x.m.motif ? ' — « ' + x.m.motif + ' »' : ''}` },
      { name: 'decision', label: 'Décision', type: 'chips', options: DECISION, required: true },
      { name: 'qte', label: 'Quantité', type: 'number', required: true },
      { name: 'motif', label: 'Motif / preuve', type: 'text', required: true }] });
    if (!v || !(v.qte > 0)) return;
    if (v.qte > x.reste) { toast(`Au plus ${q(x.reste)}`); return; }
    const base = { id: Store.uid(), articleId: x.m.articleId, isolementId: x.m.id, achatId: x.m.achatId || null, le: Store.now(), motif: v.motif, ...(x.m.siteId ? { siteId: x.m.siteId } : {}) };
    await Store.save('mouvements', v.decision === 'liberer' ? { ...base, type: 'liberation', qte: v.qte } : { ...base, type: 'disposition', qte: 0, quantite: v.qte, decision: v.decision },
      { action: v.decision === 'liberer' ? 'liberation' : 'disposition', motif: v.motif });
    toast(v.decision === 'liberer' ? 'Libérée : entrée dans le stock utilisable' : 'Décision enregistrée'); render();
  };

  // ---------- valeur du stock (CUMP par article et site, V3 §18) ----------
  V.valeur = () => {
    if (!voitCouts()) return empty('Valeur du stock : réservée au responsable, au magasin, aux achats et au pilote.');
    if (!aModule('achats')) return empty('Module « achats » non inclus dans votre abonnement (pack Entreprise).');
    const sites = siteActif() === 'tous' ? mesSites().map(s => s.id) : [siteActif() && siteActif() !== 'tous' ? siteActif() : undefined];
    const lignes = [];
    for (const s of sites) for (const a of list('articles').filter(x => x.actif !== false)) {
      const v = Calculs.valorisation(mvts(), list('valorisations'), a.id, s);
      if (v.quantite || v.quantiteNonValorisee) lignes.push({ a, s, v });
    }
    lignes.sort((x, y) => y.v.valeur - x.v.valeur);
    const total = lignes.reduce((t, x) => t + x.v.valeur, 0), incomplets = lignes.filter(x => x.v.incomplet);
    return `<h1>Valeur du stock</h1>
      <div class="tiles"><div class="tile"><b style="font-size:1.2rem">${mad(total)}</b><span>Stock utilisable valorisé (HT)</span></div><div class="tile ${incomplets.length ? 'amber' : ''}"><b>${incomplets.length}</b><span>Article(s) avec quantités sans prix</span></div></div>
      <p class="small muted">Coût moyen pondéré (CUMP) par article et site, rejoué dans l’ordre des dates. Une quantité sans prix n’est jamais comptée à zéro : elle est montrée à part. Pilotage maintenance, pas une tenue comptable.</p>
      ${lignes.length ? lignes.map(({ a, s, v }) => `<a class="card" href="#/article/${a.id}"><div class="row"><span class="t grow">${esc(a.designation)}</span>${v.provisoire ? badge('Prix provisoire', 'amber') : ''}${v.incomplet ? badge('Incomplet', 'amber') : ''}<b>${v.quantiteValorisee ? mad(v.valeur) : 'non valorisé'}</b></div>
        <div class="s">${esc(a.ref)}${s && siteActif() === 'tous' ? ' · ' + esc(nomSite(s)) : ''} · ${q(v.quantiteValorisee)} ${esc(a.unite || '')} à ${v.cump == null ? '—' : mad(v.cump)}${v.quantiteNonValorisee ? ` · <b>${q(v.quantiteNonValorisee)} sans prix</b>` : ''}</div></a>`).join('') : empty('Aucun stock.')}`;
  };

  // ---------- accueil du rôle achats ----------
  V.accueilAchats = () => {
    const das = list('achats'), aCommander = das.filter(d => ['validee', 'transmise'].includes(etat(d)) || (d.statut === 'soumise' && d.urgent)), enCours = das.filter(d => ['commandee', 'partiellement_recue'].includes(etat(d)));
    const retard = enCours.filter(enRetard);
    return `<h1>Achats <span class="muted small" style="font-weight:400">${esc(fmtY(today()))}</span></h1>
      <div class="tiles"><a class="tile blue" href="#/achats?f=commander"><b>${aCommander.length}</b><span>À commander</span></a><a class="tile" href="#/achats?f=receptionner"><b>${enCours.length}</b><span>Commandes en cours</span></a><a class="tile red" href="#/achats?f=receptionner"><b>${retard.length}</b><span>Livraisons en retard</span></a></div>
      <h2>À commander</h2>${aCommander.length ? aCommander.map(carteAchat).join('') : empty('Aucune demande validée en attente.')}
      ${retard.length ? `<h2>En retard</h2>${retard.map(carteAchat).join('')}` : ''}`;
  };
})();
