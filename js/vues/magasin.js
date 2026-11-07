/* GMAO terrain — écrans du magasin (volet B, V3 §6, §15, §16, §35).
   Cinq faits distincts : besoin, réservation, remise (ou retrait urgent), utilisation, retour.
   Le stock est par site : physique = somme des mouvements ; disponible = physique − réservé.
   Script classique chargé après app.js : il utilise les aides exposées sur window.App. */
(() => {
  const { V, A, L, esc, badge, empty, seg, search, askForm, askConfirm, toast, list, render, fmtY, refDe, role, siteActif, nomSite, desigBesoin, CLS_BESOIN, aModule, autorise } = App;
  const { data } = Store;

  // Site de calcul : le site affiché (« tous » = tous les sites additionnés).
  const siteCalc = () => { const s = siteActif(); return s && s !== 'tous' ? s : undefined; };
  const mvts = () => list('mouvements');
  const physique = (id, s = siteCalc()) => Calculs.stockPhysique(mvts(), id, s);
  const reserve = (id, s = siteCalc()) => Calculs.qteReservee(list('besoins'), mvts(), id, s);
  const sousMini = a => physique(a.id) <= (Number(a.stockMin) || 0);
  const articles = () => list('articles').filter(a => a.actif !== false).sort((a, b) => a.designation.localeCompare(b.designation));
  const aServir = () => Calculs.besoinsAServir(list('besoins'), mvts());
  const aVerifier = () => Calculs.retraitsAVerifier(mvts()).sort((a, b) => (a.le || '').localeCompare(b.le || ''));
  const otDe = b => data.ots.get(b.otId);
  const eqDe = b => data.equipements.get(b.equipementId || otDe(b)?.equipementId);

  // ---------- cartes ----------
  function carteBesoin({ b, etat }) {
    const r = Calculs.rapprochementBesoin(b, mvts(), otDe(b)?.pieces), reste = Math.max(0, Number(b.qte) - r.remis);
    const k = `data-id="${b.id}"`;
    const stockTxt = b.articleId ? `stock ${Calculs.stockPhysique(mvts(), b.articleId, b.siteId)} · disponible ${Calculs.stockDisponible(list('besoins'), mvts(), b.articleId, b.siteId)}` : 'hors catalogue';
    const btn = b.articleId
      ? [etat !== 'reserve' && etat !== 'partiellement_remis' ? `<button class="btn sm" data-act="mag-reserver" ${k}>Réserver</button>` : '',
        `<button class="btn sm primary" data-act="mag-remettre" ${k}>Remettre</button>`,
        etat !== 'indisponible' ? `<button class="btn sm ghost" data-act="mag-indispo" ${k}>Indisponible</button>` : ''].join('')
      : `<button class="btn sm primary" data-act="mag-rattacher" ${k}>Rattacher à un article</button><button class="btn sm ghost" data-act="mag-indispo" ${k}>Indisponible</button>`;
    // R5 : pièce manquante → demande d'achat liée (ou suivi « commandée » sans module Achats).
    const manque = etat === 'indisponible' || !b.articleId || (etat === 'demande' && Calculs.stockDisponible(list('besoins'), mvts(), b.articleId, b.siteId) < reste);
    const lien = Calculs.achatDuBesoin(b, list('achats')), sansStock = ['demande', 'indisponible'].includes(etat) && manque && !lien && !b.commande;
    const daOuverte = sansStock ? daOuvertes(b)[0] : null;
    const btnAchat = !sansStock ? '' : aModule('achats') && autorise('mag-achat')
      ? `<button class="btn sm" data-act="mag-achat" ${k}>Demander l’achat</button>${daOuverte ? `<button class="btn sm ghost" data-act="mag-achat-ajout" ${k} data-sub="${daOuverte.id}">Ajouter à ${esc(daOuverte.ref)}</button>` : ''}`
      : !aModule('achats') && b.articleId ? `<button class="btn sm" data-act="mag-commandee" ${k}>Commandée</button>` : '';
    const o = otDe(b), e = eqDe(b);
    return `<div class="card"><div class="row"><span class="t grow">${esc(reste || b.qte)} × ${esc(desigBesoin(b))}</span>${b.urgent ? badge('Urgent', 'red') : ''}${badge(L.etatBesoin[etat], CLS_BESOIN[etat] || '')}</div>
      <div class="s">${o ? `<a href="#/ot/${o.id}">${esc(o.ref)}</a>` : ''}${e ? ' · ' + esc(e.designation) : ''}${siteActif() === 'tous' && b.siteId ? ' · ' + esc(nomSite(b.siteId)) : ''}</div>
      <div class="s">Demandée ${esc(fmtY(b.demandeLe || b.creeLe))} par ${esc(b.demandeur || b.creePar)} · ${esc(stockTxt)}${b.qteReservee ? ` · réservé ${esc(b.qteReservee)}` : ''}${r.remis ? ` · remis ${r.remis}` : ''}${b.delai ? ` · délai ${esc(fmtY(b.delai))}` : ''}</div>
      ${b.note ? `<div class="s">« ${esc(b.note)} »</div>` : ''}
      ${lien || b.commande ? App.frisePiece(b) : ''}
      <div class="actions" style="margin:8px 0 0">${btn}${btnAchat}</div></div>`;
  }
  function carteRetrait(m) {
    const a = data.articles.get(m.articleId);
    return `<div class="card"><div class="row"><span class="t grow">${esc(Math.abs(m.qte))} × ${esc(a?.designation || 'Article')}</span>${badge('À vérifier', 'amber')}</div>
      <div class="s">Retrait urgent par ${esc(m.creePar)} le ${esc(fmtY(m.le))}${m.otId ? ` · <a href="#/ot/${m.otId}">${esc(refDe('ots', m.otId))}</a>` : ''}</div>
      <div class="actions" style="margin:8px 0 0"><button class="btn sm primary" data-act="mag-verifier" data-id="${m.id}">Vérifié</button>${a ? `<a class="btn sm ghost" href="#/article/${a.id}">Voir l’article</a>` : ''}</div></div>`;
  }
  function carteArticle(a) {
    const p = physique(a.id), r = reserve(a.id), sit = App.situation ? App.situation(a) : null;
    const alerte = sit ? (sit.alerte ? badge(sit.rupture ? 'Rupture' : 'À réapprovisionner', sit.rupture ? 'red' : 'amber') : '') : sousMini(a) ? badge('Sous le mini', 'red') : '';
    return `<a class="card" href="#/article/${a.id}"><div class="row"><span class="t grow">${esc(a.designation)}</span>${alerte}<b>${p - r} ${esc(a.unite)}</b></div>
      <div class="s">${esc(a.ref)} · physique ${p} · réservé ${r} · disponible ${p - r} · mini ${esc(a.stockMin || 0)}</div></a>`;
  }

  // ---------- écrans ----------
  /** En-tête commun aux onglets du magasin (le récapitulatif « À réapprovisionner » vient de reappro.js). */
  function enteteMagasin(t, nServ = aServir().length, nVerif = aVerifier().length) {
    const s = siteActif(), nRea = App.reappro ? App.reappro().length : null;
    return `<h1>Magasin${s === 'tous' ? ' <span class="muted small" style="font-weight:400">· tous les sites</span>' : s ? ` <span class="muted small" style="font-weight:400">· ${esc(nomSite(s))}</span>` : ''}</h1>
      ${seg([['#/magasin?t=servir', `À servir (${nServ})`, 'servir'], ['#/magasin?t=verifier', `À vérifier (${nVerif})`, 'verifier'],
        ...(nRea === null ? [] : [['#/reappro', `À réapprovisionner (${nRea})`, 'reappro']]), ['#/magasin?t=stock', 'Stock', 'stock']], t)}`;
  }
  App.enteteMagasin = enteteMagasin;
  V.magasin = r => {
    const serv = aServir(), verif = aVerifier();
    const t = r.q.get('t') || (serv.length ? 'servir' : verif.length ? 'verifier' : 'stock');
    const entete = enteteMagasin(t, serv.length, verif.length);
    if (t === 'servir') return entete + `<p class="small muted">Une demande ne retire rien du stock. Réserver bloque la quantité ; Remettre la sort du magasin.</p>
      ${serv.length ? serv.map(carteBesoin).join('') : empty('Aucune demande de pièce en attente.')}`;
    if (t === 'verifier') return entete + `<p class="small muted">Pièces prises en urgence par les techniciens : le stock est déjà débité. En cas d’écart, faites un inventaire de l’article.</p>
      ${verif.length ? verif.map(carteRetrait).join('') : empty('Aucun retrait urgent à vérifier.')}`;
    const arts = articles();
    return entete + `${search('#lst', 'Rechercher un article')}<div id="lst">${arts.length ? arts.map(carteArticle).join('') : empty('Aucun article.')}</div>
      <div class="actions"><button class="btn" data-act="art-new">+ Article</button></div>`;
  };

  V.article = r => {
    const a = data.articles.get(r.id);
    if (!a) return empty('Article introuvable.');
    const mv = mvts().filter(m => m.articleId === a.id).sort((x, y) => (y.le || '').localeCompare(x.le || ''));
    const p = physique(a.id), res = reserve(a.id);
    return `<h1>${esc(a.designation)}</h1><div class="card"><dl class="kv"><dt>Référence</dt><dd>${esc(a.ref)}</dd><dt>Stock physique</dt><dd><b>${p} ${esc(a.unite)}</b></dd>
        <dt>Réservé</dt><dd>${res}</dd><dt>Disponible</dt><dd><b>${p - res}</b></dd><dt>Mini</dt><dd>${esc(a.stockMin || 0)}</dd>${siteActif() === 'tous' ? '<dt>Site</dt><dd>tous les sites</dd>' : ''}</dl></div>
      <div class="actions"><button class="btn primary" data-act="mvt" data-id="${a.id}" data-sub="entree">Réception</button><button class="btn" data-act="mvt" data-id="${a.id}" data-sub="sortie">Sortie hors OT</button><button class="btn" data-act="mvt" data-id="${a.id}" data-sub="ajustement">Inventaire</button></div>
      <p class="small muted">Les mouvements ne sont jamais modifiés : une erreur se corrige par un mouvement inverse.</p>
      ${App.blocSeuils ? App.blocSeuils(a) : ''}
      <h2>Mouvements</h2><div class="card"><ul class="lines">${mv.map(m => `<li><span class="grow">${esc(L.mvt[m.type] || m.type)}${m.urgent ? ' ' + badge(m.verifieLe ? 'Vérifié' : 'À vérifier', m.verifieLe ? 'green' : 'amber') : ''}${m.otId ? ` · <a href="#/ot/${m.otId}">${esc(refDe('ots', m.otId))}</a>` : ''}${m.motif ? ' · ' + esc(m.motif) : ''}<br><span class="small muted">${fmtY(m.le)} · ${esc(m.creePar)}${siteActif() === 'tous' && m.siteId ? ' · ' + esc(nomSite(m.siteId)) : ''}</span></span><b>${m.qte > 0 ? '+' : ''}${m.qte}</b></li>`).join('') || '<li class="muted">Aucun mouvement.</li>'}</ul></div>`;
  };

  /** Accueil du magasinier : ce qui demande une action aujourd'hui. */
  V.accueilMagasin = () => {
    const serv = aServir(), verif = aVerifier(), mini = App.reappro ? App.reappro().map(x => x.article) : articles().filter(sousMini);
    const urg = serv.filter(x => x.b.urgent && x.etat !== 'indisponible');
    const aCommander = aModule('achats') && App.parametres()?.quiCommande === 'magasinier' ? list('achats').filter(d => ['validee', 'transmise'].includes(d.statut) || (d.statut === 'soumise' && d.urgent)) : [];
    return `<h1>Magasin <span class="muted small" style="font-weight:400">${esc(fmtY(Store.now().slice(0, 10)))}</span></h1>
      <div class="tiles">
        <a class="tile red" href="#/magasin?t=servir"><b>${urg.length}</b><span>Demandes urgentes</span></a>
        <a class="tile amber" href="#/magasin?t=servir"><b>${serv.length}</b><span>Demandes à servir</span></a>
        <a class="tile blue" href="#/magasin?t=verifier"><b>${verif.length}</b><span>Retraits à vérifier</span></a>
        ${aCommander.length ? `<a class="tile blue" href="#/achats?f=commander"><b>${aCommander.length}</b><span>Achats à commander</span></a>` : ''}
        <a class="tile" href="${App.reappro ? '#/reappro' : '#/magasin?t=stock'}"><b>${mini.length}</b><span>${App.reappro ? 'À réapprovisionner' : 'Articles sous le mini'}</span></a>
      </div>
      <h2>À servir</h2>${serv.length ? serv.slice(0, 6).map(carteBesoin).join('') + (serv.length > 6 ? `<a class="btn ghost" href="#/magasin?t=servir">Voir les ${serv.length}</a>` : '') : empty('Aucune demande en attente.')}
      ${verif.length ? `<h2>Retraits à vérifier</h2>${verif.slice(0, 4).map(carteRetrait).join('')}` : ''}
      ${mini.length ? `<h2>${App.reappro ? 'À réapprovisionner' : 'Sous le mini'}</h2>${mini.slice(0, 6).map(carteArticle).join('')}` : ''}`;
  };

  // ---------- actions ----------
  const qteRemise = b => Calculs.qteRemise(mvts(), b.id);
  /** Demandes d'achat encore modifiables du même site (on y ajoute la pièce plutôt que d'en créer une autre). */
  function daOuvertes(b) {
    return list('achats').filter(d => ['brouillon', 'soumise', 'a_completer'].includes(d.statut) && (d.siteId || null) === (b.siteId || null) && !d.urgent === !b.urgent)
      .sort((x, y) => (y.creeLe || '').localeCompare(x.creeLe || ''));
  }
  const ligneDe = (b, qte) => {
    const o = otDe(b), e = eqDe(b);
    return { id: Store.uid(), articleId: b.articleId || null, ...(b.articleId ? {} : { description: desigBesoin(b) }), qte, unite: data.articles.get(b.articleId)?.unite || null,
      besoinId: b.id, otId: b.otId || null, motif: `Pour ${o?.ref || 'intervention'}${e ? ' · ' + e.designation : ''}` };
  };
  const resteBesoin = b => Math.max(0, Number(b.qte) - qteRemise(b) - Math.max(0, (Number(b.qteReservee) || 0) - qteRemise(b)));
  /** R5 : « Demander l'achat » — demande d'achat pré-remplie, liée à la pièce et à l'intervention, soumise au responsable. */
  A['mag-achat'] = async el => {
    const b = data.besoins.get(el.dataset.id), o = otDe(b), e = eqDe(b);
    const v = await askForm({ title: 'Demander l’achat', ok: 'Créer la demande d’achat', values: { qte: resteBesoin(b) || Number(b.qte), urgent: !!b.urgent }, fields: [
      { type: 'info', text: `${desigBesoin(b)} pour ${o?.ref || 'l’intervention'}${e ? ' · ' + e.designation : ''}. La demande part au responsable ; la pièce affichera chaque étape au technicien.` },
      { name: 'qte', label: 'Quantité', type: 'number', required: true },
      { name: 'urgent', label: 'Urgent : commande possible avant la validation (le responsable valide ensuite)', type: 'checkbox' },
      { name: 'motifUrgence', label: 'Motif de l’urgence (si urgent)', type: 'text', placeholder: 'ex. presse à l’arrêt' }] });
    if (!v || !(v.qte > 0)) return;
    if (v.urgent && !v.motifUrgence) { toast('Indiquez le motif de l’urgence'); return; }
    const ligne = ligneDe(b, v.qte), now = Store.now(), qui = Store.currentUserName();
    const da = { id: Store.uid(), ref: await Store.nextRef('DA'), statut: 'soumise', origine: 'besoin', ...(b.siteId ? { siteId: b.siteId } : {}),
      redigePar: qui, redigeLe: now, soumiseLe: now, soumisePar: qui, ...(v.urgent ? { urgent: true, motifUrgence: v.motifUrgence } : {}), lignes: [ligne] };
    await Store.save('achats', da, { action: 'demande_achat' });
    await Store.update('besoins', b.id, { statut: 'indisponible', achatId: da.id, ligneId: ligne.id }, { action: 'achat_demande' });
    toast(v.urgent ? `${da.ref} créée (urgente) : à commander tout de suite` : `${da.ref} créée et soumise au responsable`);
    render();
  };
  A['mag-achat-ajout'] = async el => {
    const b = data.besoins.get(el.dataset.id), da = data.achats.get(el.dataset.sub);
    if (!da || !['brouillon', 'soumise', 'a_completer'].includes(da.statut)) { toast('Cette demande d’achat n’est plus modifiable'); render(); return; }
    const v = await askForm({ title: 'Ajouter à ' + da.ref, ok: 'Ajouter', values: { qte: resteBesoin(b) || Number(b.qte) }, fields: [
      { type: 'info', text: `${desigBesoin(b)} : une ligne de plus sur ${da.ref} (${(da.lignes || []).length} ligne(s)).` },
      { name: 'qte', label: 'Quantité', type: 'number', required: true }] });
    if (!v || !(v.qte > 0)) return;
    const ligne = ligneDe(b, v.qte);
    await Store.update('achats', da.id, { lignes: [...(da.lignes || []), ligne] }, { action: 'ajout_ligne' });
    await Store.update('besoins', b.id, { statut: 'indisponible', achatId: da.id, ligneId: ligne.id }, { action: 'achat_demande' });
    toast('Ajouté à ' + da.ref); render();
  };
  /** Sans module Achats (pack Pro) : la commande passée est notée sur la pièce. */
  const fournisseursOpts = () => list('fournisseurs').filter(f => f.actif !== false && !(f.prestataire && !f.fournisseur)).sort((a, b) => (a.nom || '').localeCompare(b.nom || '')).map(f => [f.id, f.nom]);
  App.fournisseursOpts = fournisseursOpts;
  A['mag-commandee'] = async el => {
    const b = data.besoins.get(el.dataset.id);
    const v = await askForm({ title: 'Pièce commandée', values: { le: Store.now().slice(0, 10) }, fields: [
      { name: 'fournisseurId', label: 'Fournisseur', type: 'select', options: fournisseursOpts(), empty: '— Autre (à écrire) —' },
      { name: 'fournisseur', label: 'Autre fournisseur', type: 'text' },
      { name: 'le', label: 'Date de commande', type: 'date', required: true },
      { name: 'livraisonPrevue', label: 'Livraison prévue', type: 'date' }] });
    if (!v) return;
    const f = v.fournisseurId ? data.fournisseurs.get(v.fournisseurId) : null;
    const livraison = v.livraisonPrevue || (f?.delaiJours ? Calculs.addDays(v.le, Number(f.delaiJours)).slice(0, 10) : null);
    await Store.update('besoins', b.id, { statut: 'indisponible', delai: livraison, commande: { fournisseurId: f?.id || null, fournisseur: f?.nom || v.fournisseur || null, le: v.le, livraisonPrevue: livraison } }, { action: 'commande_notee' });
    toast('Commande notée sur la pièce'); render();
  };
  /** Réserve n pièces de plus pour un besoin (réception, entrée en stock). */
  async function reserverBesoin(b, n) {
    const cur = data.besoins.get(b.id) || b;
    await Store.update('besoins', cur.id, { qteReservee: Math.max(Number(cur.qteReservee) || 0, qteRemise(cur)) + n, statut: 'reserve', delai: null, reserveLe: Store.now(), reservePar: Store.currentUserName() }, { action: 'reservation' });
  }
  App.reserverBesoin = reserverBesoin;
  /** R5 : à toute entrée en stock, proposer de réserver pour les pièces en attente de l'article (urgentes, puis plus anciennes). */
  async function proposerReservations(articleId, siteId, { exclure = [] } = {}) {
    const dispo = Calculs.stockDisponible(list('besoins'), mvts(), articleId, siteId);
    const att = Calculs.besoinsEnAttenteArticle(list('besoins'), mvts(), articleId, siteId).filter(x => !exclure.includes(x.b.id)).slice(0, 8);
    if (!att.length || dispo <= 0) return;
    const a = data.articles.get(articleId), values = {};
    let reste = dispo;
    const fields = [{ type: 'info', text: `${a?.designation || 'Article'} : ${dispo} ${a?.unite || ''} disponible(s). Pièces en attente de cet article :` }];
    for (const x of att) {
      const n = Math.min(x.reste, Math.max(0, reste)); reste -= n;
      values['r_' + x.b.id] = n > 0;
      const o = otDe(x.b), e = eqDe(x.b);
      fields.push({ name: 'r_' + x.b.id, type: 'checkbox', label: `Réserver ${Math.min(x.reste, dispo)} pour ${o?.ref || '—'}${e ? ' · ' + e.designation : ''}${x.b.urgent ? ' (urgent)' : ''}` });
    }
    const v = await askForm({ title: 'Réserver pour les pièces en attente ?', ok: 'Réserver', cancel: 'Plus tard', values, fields });
    if (!v) return;
    let d = dispo, n = 0;
    for (const x of att) { if (!v['r_' + x.b.id] || d <= 0) continue; const q = Math.min(x.reste, d); d -= q; await reserverBesoin(x.b, q); n++; }
    if (n) toast(`${n} pièce(s) réservée(s) : les techniciens les voient « prêtes au magasin »`);
  }
  App.proposerReservations = proposerReservations;
  A['mag-reserver'] = async el => {
    const b = data.besoins.get(el.dataset.id);
    const dispo = Calculs.stockDisponible(list('besoins'), mvts(), b.articleId, b.siteId) + Math.max(0, (Number(b.qteReservee) || 0) - qteRemise(b));
    const reste = Math.max(0, Number(b.qte) - qteRemise(b));
    const v = await askForm({ title: 'Réserver', ok: 'Réserver', values: { qte: Math.max(0, Math.min(reste, dispo)) || reste }, fields: [
      { type: 'info', text: `${desigBesoin(b)} · demandé ${reste} · disponible ${dispo}` },
      { name: 'qte', label: 'Quantité réservée', type: 'number', required: true }] });
    if (!v || !(v.qte > 0)) return;
    if (v.qte > dispo && !(await askConfirm('Réserver plus que le disponible ?', `Disponible : ${dispo}. Une réservation au-delà rendra le disponible négatif.`, 'Réserver quand même'))) return;
    await Store.update('besoins', b.id, { qteReservee: qteRemise(b) + v.qte, statut: 'reserve', delai: null, reserveLe: Store.now(), reservePar: Store.currentUserName() }, { action: 'reservation' });
    toast('Réservé'); render();
  };
  A['mag-remettre'] = async el => {
    const b = data.besoins.get(el.dataset.id);
    const reste = Math.max(0, Number(b.qte) - qteRemise(b)), phys = Calculs.stockPhysique(mvts(), b.articleId, b.siteId);
    const o = otDe(b);
    const v = await askForm({ title: 'Remettre au technicien', ok: 'Remettre', values: { qte: reste || 1 }, fields: [
      { type: 'info', text: `${desigBesoin(b)} · reste à remettre ${reste} · stock ${phys}${o ? ' · ' + o.ref : ''}` },
      { name: 'qte', label: 'Quantité remise', type: 'number', required: true },
      { name: 'a', label: 'Remise à', type: 'text', placeholder: b.demandeur || '' }] });
    if (!v || !(v.qte > 0)) return;
    if (v.qte > phys && !(await askConfirm('Stock insuffisant ?', `Stock enregistré : ${phys}. Remettre ${v.qte} rendra le stock négatif : faites ensuite un inventaire.`, 'Remettre quand même'))) return;
    await Store.save('mouvements', { id: Store.uid(), articleId: b.articleId, type: 'remise', qte: -v.qte, besoinId: b.id, otId: b.otId || null, siteId: b.siteId, le: Store.now(), motif: 'Remise magasin' + (v.a ? ' à ' + v.a : '') }, { action: 'remise' });
    toast('Remise enregistrée');
    await App.leverAttentesPieces(); // responsable ou usage local : l'attente se lève tout de suite
    render();
  };
  A['mag-indispo'] = async el => {
    const b = data.besoins.get(el.dataset.id);
    const v = await askForm({ title: 'Pièce indisponible', ok: 'Enregistrer', values: { delai: b.delai }, fields: [
      { type: 'info', text: `${desigBesoin(b)} : le technicien verra « Indisponible » et le délai annoncé.` },
      { name: 'delai', label: 'Délai annoncé (date prévue)', type: 'date' },
      { name: 'motif', label: 'Précision', type: 'text', placeholder: 'ex. commandé chez le fournisseur' }] });
    if (!v) return;
    await Store.update('besoins', b.id, { statut: 'indisponible', delai: v.delai, motifIndispo: v.motif }, { action: 'indisponible', motif: v.motif });
    toast('Indisponibilité signalée'); render();
  };
  A['mag-rattacher'] = async el => {
    const b = data.besoins.get(el.dataset.id);
    const v = await askForm({ title: 'Rattacher à un article', ok: 'Rattacher', fields: [
      { type: 'info', text: `Demande : « ${b.description} »` },
      { name: 'articleId', label: 'Article', type: 'select', required: true, empty: '— Choisir —', options: articles().map(a => [a.id, `${a.designation} (${a.ref}) · stock ${Calculs.stockPhysique(mvts(), a.id, b.siteId)}`]) }] });
    if (!v?.articleId) return;
    await Store.update('besoins', b.id, { articleId: v.articleId, unite: data.articles.get(v.articleId)?.unite || null }, { action: 'rattachement' });
    render();
  };
  A['mag-verifier'] = async el => {
    const m = data.mouvements.get(el.dataset.id);
    if (!(await askConfirm('Retrait vérifié', `${Math.abs(m.qte)} × ${data.articles.get(m.articleId)?.designation || ''} pris par ${m.creePar}. La quantité n’est pas modifiée ; en cas d’écart, faites un inventaire.`, 'Vérifié'))) return;
    await Store.save('mouvements', { ...m, aVerifier: false, verifieLe: Store.now(), verifiePar: Store.currentUserName() }, { action: 'verification' });
    toast('Retrait vérifié'); render();
  };

  A['art-new'] = async () => {
    const v = await askForm({ title: 'Nouvel article', values: { unite: 'u', stockMin: 0 }, fields: [
      { name: 'ref', label: 'Référence', type: 'text', required: true }, { name: 'designation', label: 'Désignation', type: 'text', required: true },
      { name: 'unite', label: 'Unité', type: 'text', required: true }, { name: 'stockMin', label: 'Stock mini', type: 'number' }] });
    if (!v) return;
    if (list('articles').some(a => a.ref.toLowerCase() === v.ref.toLowerCase())) { toast('Référence déjà utilisée'); return; }
    await Store.save('articles', { id: Store.uid(), ...v, actif: true }); render();
  };
  /** Réception, sortie hors intervention, inventaire : toujours sur un site précis (stock par site). */
  A.mvt = async el => {
    if (siteActif() === 'tous') { toast('Choisissez d’abord un site (📍 en haut) : le stock est tenu par site'); return; }
    const a = data.articles.get(el.dataset.id), type = el.dataset.sub, p = physique(a.id);
    const v = await askForm({ title: L.mvt[type], fields: type === 'ajustement'
      ? [{ type: 'info', text: `Stock enregistré : ${p} ${a.unite}` }, { name: 'compte', label: 'Quantité comptée', type: 'number', required: true }, { name: 'motif', label: 'Motif', type: 'text', required: true }]
      : [{ name: 'qte', label: 'Quantité', type: 'number', required: true }, { name: 'motif', label: type === 'entree' ? 'Bon de livraison / fournisseur' : 'Motif', type: 'text', required: type !== 'entree' },
        ...(type === 'entree' && App.aModule('achats') && App.voitCouts?.() ? [{ name: 'prix', label: 'Prix unitaire HT en MAD (facultatif : vide = inconnu, jamais 0)', type: 'number' }] : [])] });
    if (!v) return;
    const qte = type === 'ajustement' ? v.compte - p : type === 'sortie' ? -Math.abs(v.qte) : Math.abs(v.qte);
    if (!qte) { toast('Aucun écart'); return; }
    const m = { id: Store.uid(), articleId: a.id, type, qte, otId: null, le: Store.now(), motif: v.motif };
    await Store.save('mouvements', m);
    if (type === 'entree' && v.prix != null) await Store.save('valorisations', { id: Store.uid(), mouvementId: m.id, ...(m.siteId ? { siteId: m.siteId } : {}), prixUnitaire: v.prix, devise: 'MAD', statut: 'connu' }, { action: 'prix_reception' });
    if (type === 'entree') await proposerReservations(a.id, m.siteId || siteCalc());
    render();
  };
})();
