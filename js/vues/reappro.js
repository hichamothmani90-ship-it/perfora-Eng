/* GMAO terrain — définition des stocks et réapprovisionnement (volet C, V3 §14, §17).
   Seuils par article et site : le magasinier propose, le responsable valide (auteur et motif conservés).
   « À réapprovisionner » propose des quantités ; l'appli ne commande rien (aide pour l'acheteur, export CSV).
   Les prix ne figurent jamais ici : ils vivent dans les fiches achats / valorisations (lecture restreinte).
   Script classique chargé après magasin.js ; la demande d'achat elle-même est dans achats.js. */
(() => {
  const { V, A, esc, badge, empty, askForm, askConfirm, askText, toast, list, render, fmtY, role, autorise, aModule, siteActif, nomSite, mesSites, exportCsv } = App;
  const { data } = Store;

  const D = () => ({ articles: list('articles'), seuils: list('seuils'), besoins: list('besoins'), mouvements: list('mouvements'), achats: list('achats') });
  const siteCalc = () => { const s = siteActif(); return s && s !== 'tous' ? s : undefined; };
  const q = n => Number.isInteger(n) ? n : Math.round(n * 10) / 10;
  const aujourdhui = () => Store.now().slice(0, 10);

  /** Récapitulatif du site affiché ; en « tous les sites », un récapitulatif par site (le stock est tenu par site). */
  function reappro() {
    const d = D();
    if (siteActif() === 'tous') return mesSites().flatMap(s => Calculs.aReapprovisionner(d, s.id).map(x => ({ ...x, siteId: s.id })));
    return Calculs.aReapprovisionner(d, siteCalc()).map(x => ({ ...x, siteId: siteCalc() }));
  }
  App.reappro = reappro;
  App.situation = a => siteActif() === 'tous' ? null : Calculs.situationArticle(D(), a, siteCalc());

  // ---------- À réapprovisionner ----------
  const peutDA = () => aModule('achats') && autorise('achat-new');
  function carteReappro(x, i) {
    const a = x.article, s = x.seuil, u = esc(a.unite || '');
    return `<div class="card"><div class="row">${peutDA() ? `<input type="checkbox" name="ra" value="${i}" checked style="width:22px;height:22px;margin-right:8px">` : ''}
        <a class="t grow" href="#/article/${a.id}">${esc(a.designation)}</a>${x.rupture ? badge('Rupture', 'red') : ''}${s.critique ? badge('Critique', 'red') : ''}${s.provisoire ? badge('Seuil provisoire', 'amber') : ''}</div>
      <div class="s">${esc(a.ref)}${siteActif() === 'tous' && x.siteId ? ' · ' + esc(nomSite(x.siteId)) : ''} · disponible ${q(x.disponible)} − demandes non couvertes ${q(x.nonCouverts)} + en commande ${q(x.enCommande)} = <b>${q(x.couverture)}</b></div>
      <div class="s">Point de commande ${q(s.pointCommande)} · cible ${q(s.cible)}${s.delaiJours ? ` · délai ${esc(s.delaiJours)} j` : ''}${x.isole ? ` · ${q(x.isole)} isolée(s)` : ''}</div>
      <div class="row" style="margin-top:6px"><span class="grow small muted">Quantité proposée</span><b style="font-size:1.15rem">${q(x.proposee)} ${u}</b></div></div>`;
  }
  V.reappro = () => {
    const l = reappro();
    return `${App.enteteMagasin('reappro')}
      <p class="small muted">Alerte quand disponible − demandes non couvertes + en commande passe sous le point de commande. Quantité proposée = cible − couverture. L’appli ne commande rien.</p>
      ${l.length ? l.map(carteReappro).join('') : empty('Rien à réapprovisionner. Les articles sans seuil validé ni stock mini ne sont pas suivis.')}
      <div class="actions">${l.length ? `<button class="btn" data-act="reappro-csv">Exporter (CSV Excel)</button>` : ''}${l.length && peutDA() ? '<button class="btn primary" data-act="achat-new">Créer la demande d’achat</button>' : ''}</div>
      ${l.length && !aModule('achats') ? '<p class="small muted">Demandes d’achat et valorisation : module « achats » (pack Entreprise). L’export CSV reste disponible.</p>' : ''}
      ${list('achats').length && App.carteAchat ? `<h2>Demandes d’achat <a class="small" href="#/achats" style="font-weight:400">tout voir</a></h2>${list('achats').sort((x, y) => (y.creeLe || '').localeCompare(x.creeLe || '')).slice(0, 10).map(App.carteAchat).join('')}` : ''}`;
  };
  A['reappro-csv'] = () => {
    const head = ['Site', 'Référence', 'Désignation', 'Unité', 'Physique', 'Réservé', 'Disponible', 'Demandes non couvertes', 'En commande', 'Couverture', 'Point de commande', 'Cible', 'Délai (j)', 'Critique', 'Seuil', 'Quantité proposée'];
    const rows = reappro().map(x => [nomSite(x.siteId) || '', x.article.ref, x.article.designation, x.article.unite, x.physique, x.reserve, x.disponible, x.nonCouverts, x.enCommande, x.couverture,
      Number(x.seuil.pointCommande) || 0, Number(x.seuil.cible) || 0, x.seuil.delaiJours ? Number(x.seuil.delaiJours) : '', x.seuil.critique ? 'oui' : 'non', x.seuil.provisoire ? 'provisoire (stock mini)' : 'validé', x.proposee]);
    exportCsv(head, rows, `gmao-a-reapprovisionner-${aujourdhui()}.csv`);
  };
  /** Demande d'achat en brouillon à partir des lignes cochées (une par site). Aucun prix ici : l'acheteur les renseigne. */
  A['achat-new'] = async () => {
    const l = reappro(), coches = [...document.querySelectorAll('input[name=ra]:checked')].map(i => l[Number(i.value)]).filter(Boolean);
    if (!coches.length) { toast('Cochez au moins un article'); return; }
    const parSite = new Map();
    for (const x of coches) { const k = x.siteId || ''; if (!parSite.has(k)) parSite.set(k, []); parSite.get(k).push(x); }
    let premier = null;
    for (const [siteId, xs] of parSite) {
      const da = { id: Store.uid(), ref: await Store.nextRef('DA'), statut: 'brouillon', origine: 'reapprovisionnement', ...(siteId ? { siteId } : {}),
        redigePar: Store.currentUserName(), redigeLe: Store.now(),
        lignes: xs.map(x => ({ id: Store.uid(), articleId: x.article.id, qte: x.proposee, unite: x.article.unite || null,
          motif: `Couverture ${q(x.couverture)} < point de commande ${q(x.seuil.pointCommande)}${x.rupture ? ' (rupture)' : ''}` })) };
      await Store.save('achats', da, { action: 'demande_achat' });
      premier = premier || da;
    }
    toast(parSite.size > 1 ? `${parSite.size} demandes d’achat créées (une par site)` : 'Demande d’achat créée (brouillon)');
    location.hash = '#/achat/' + premier.id;
  };

  // ---------- seuils d'un article (bloc de la fiche article) ----------
  App.blocSeuils = a => {
    const s = siteCalc();
    if (siteActif() === 'tous') return `<h2>Seuils</h2><p class="info">Les seuils sont définis par site : choisissez un site (📍 en haut).</p>`;
    const tous = list('seuils').filter(x => x.articleId === a.id && (!s || x.siteId === s)).sort((x, y) => (y.creeLe || '').localeCompare(x.creeLe || ''));
    const actif = Calculs.seuilActif(list('seuils'), a, s), prop = tous.filter(x => x.statut === 'propose');
    const conso = Calculs.consommationHebdo(list('mouvements'), a.id, s, aujourdhui());
    const ligne = x => `sécurité ${q(Number(x.securite) || 0)} · point de commande <b>${q(Number(x.pointCommande) || 0)}</b> · cible <b>${q(Number(x.cible) || 0)}</b>${x.delaiJours ? ` · délai ${esc(x.delaiJours)} j` : ''}${x.critique ? ' · ' + badge('Critique', 'red') : ''}`;
    const histo = tous.filter(x => x.statut !== 'propose' && x.id !== actif?.id);
    return `<h2>Seuils${s ? ' · ' + esc(nomSite(s)) : ''}</h2><div class="card">
      ${actif && !actif.provisoire ? `<div>${ligne(actif)}</div><div class="s">Validé le ${esc(fmtY(actif.valideLe))} par ${esc(actif.validePar)}${actif.justification ? ' · « ' + esc(actif.justification) + ' »' : ''}</div>`
        : actif ? `<p class="warn" style="margin:0">Repère provisoire : stock mini ${q(actif.pointCommande)} (non validé). Proposez des seuils.</p>` : '<p class="muted" style="margin:0">Aucun seuil : l’article n’est pas suivi par « À réapprovisionner ».</p>'}
      ${prop.map(x => `<div class="info" style="margin-top:10px"><b>Proposition</b> de ${esc(x.proposePar || x.creePar)} (${esc(fmtY(x.creeLe))}) : ${ligne(x)}${x.justification ? `<br>« ${esc(x.justification)} »` : ''}
        <div class="actions" style="margin:8px 0 0"><button class="btn sm primary" data-act="seuil-valider" data-id="${x.id}">Valider</button><button class="btn sm ghost" data-act="seuil-refuser" data-id="${x.id}">Refuser</button></div></div>`).join('')}
      <p class="small muted" style="margin-bottom:0">Consommation : ${q(conso)} ${esc(a.unite || '')} / semaine (90 derniers jours, retours déduits). Repère V3 : consommation × délai + sécurité ; insuffisant pour une pièce critique rarement consommée.</p>
      <div class="actions" style="margin-bottom:0"><button class="btn sm" data-act="seuil-proposer" data-id="${a.id}">${role() && role() !== 'responsable' ? 'Proposer des seuils' : 'Définir les seuils'}</button></div>
      ${histo.length ? `<details class="more"><summary>Historique (${histo.length})</summary>${histo.map(x => `<div class="journal-item">${badge(x.statut === 'valide' ? 'Ancienne version' : 'Refusée', x.statut === 'valide' ? '' : 'red')} ${ligne(x)}<br><span class="muted">${esc(fmtY(x.valideLe || x.refuseLe || x.creeLe))} · ${esc(x.validePar || x.refusePar || x.creePar)}${x.motifRefus ? ' · ' + esc(x.motifRefus) : ''}</span></div>`).join('')}</details>` : ''}
    </div>`;
  };
  A['seuil-proposer'] = async el => {
    const a = data.articles.get(el.dataset.id), s = siteCalc();
    const actif = Calculs.seuilActif(list('seuils'), a, s), conso = Calculs.consommationHebdo(list('mouvements'), a.id, s, aujourdhui());
    const resp = !role() || role() === 'responsable';
    const base = actif && !actif.provisoire ? actif : { securite: 0, delaiJours: 14 };
    const indicatif = Calculs.seuilIndicatif(conso, base.delaiJours, base.securite);
    const v = await askForm({ title: resp ? 'Seuils de l’article' : 'Proposer des seuils', ok: resp ? 'Enregistrer' : 'Proposer',
      values: { securite: base.securite, pointCommande: actif && !actif.provisoire ? actif.pointCommande : indicatif, cible: actif && !actif.provisoire ? actif.cible : null, delaiJours: base.delaiJours, critique: !!base.critique, valider: true },
      fields: [
        { type: 'info', text: `${a.designation}${s ? ' · ' + nomSite(s) : ''} — consommation ${q(conso)} / semaine ; seuil indicatif ${indicatif} (consommation × délai + sécurité).` },
        { name: 'securite', label: 'Stock de sécurité', type: 'number', required: true },
        { name: 'pointCommande', label: 'Point de commande (seuil de réapprovisionnement)', type: 'number', required: true },
        { name: 'cible', label: 'Stock cible (maxi)', type: 'number', required: true },
        { name: 'delaiJours', label: 'Délai de réapprovisionnement de référence (jours)', type: 'number' },
        { name: 'critique', label: 'Article critique (équipement critique, sans secours)', type: 'checkbox' },
        { name: 'justification', label: 'Justification (motif de la révision)', type: 'textarea', required: true },
        ...(resp ? [{ name: 'valider', label: 'Valider maintenant (responsable)', type: 'checkbox' }] : [])] });
    if (!v) return;
    if (!(v.securite >= 0) || !(v.pointCommande >= v.securite) || !(v.cible >= v.pointCommande)) { toast('Il faut : sécurité ≤ point de commande ≤ cible'); return; }
    const now = Store.now(), qui = Store.currentUserName();
    const sv = { id: Store.uid(), articleId: a.id, ...(s ? { siteId: s } : {}), securite: v.securite, pointCommande: v.pointCommande, cible: v.cible, delaiJours: v.delaiJours,
      critique: !!v.critique, justification: v.justification, proposePar: qui, proposeLe: now, statut: 'propose',
      ...(resp && v.valider ? { statut: 'valide', valideLe: now, validePar: qui } : {}) };
    await Store.save('seuils', sv, { action: sv.statut === 'valide' ? 'seuil_valide' : 'seuil_propose', motif: v.justification });
    toast(sv.statut === 'valide' ? 'Seuils validés' : 'Proposition envoyée au responsable'); render();
  };
  A['seuil-valider'] = async el => {
    const x = data.seuils.get(el.dataset.id);
    if (!(await askConfirm('Valider les seuils', `Point de commande ${x.pointCommande}, cible ${x.cible}, sécurité ${x.securite}. Ils remplacent la version en vigueur (conservée dans l’historique).`, 'Valider'))) return;
    await Store.update('seuils', x.id, { statut: 'valide', valideLe: Store.now(), validePar: Store.currentUserName() }, { action: 'seuil_valide' });
    toast('Seuils validés'); render();
  };
  A['seuil-refuser'] = async el => {
    const m = await askText('Refuser la proposition', 'Motif (visible par le magasinier)');
    if (!m) return;
    await Store.update('seuils', el.dataset.id, { statut: 'refuse', refuseLe: Store.now(), refusePar: Store.currentUserName(), motifRefus: m }, { action: 'seuil_refuse', motif: m });
    render();
  };
})();
