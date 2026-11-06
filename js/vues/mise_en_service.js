/* Console plateforme — mise en service d'un client : étapes de démarrage, import du kit Excel, lots, invitations.
   Réservé à l'administrateur plateforme (vérifié par le serveur : fonctions pf_*). Lecture Excel (js/xlsx.js) et
   conversion (js/kit.js) chargées seulement sur cette page. Script classique chargé après achats.js. */
(() => {
  const { V, AFTER, esc, badge, empty, askConfirm, alertBox, toast, fmtY, adressePublique } = App;

  const ETAPES = [
    ['kit_envoye', 'Kit de démarrage envoyé'], ['kit_recu', 'Kit rempli reçu'], ['import', 'Données importées'],
    ['responsable_invite', 'Responsable invité'], ['qr_imprimes', 'Étiquettes QR imprimées'], ['equipe_invitee', 'Équipe invitée'], ['mise_en_service', 'Mise en service'],
  ];
  const TYPES = { localisations: 'Lieux', equipements: 'Équipements', compteurs: 'Compteurs', releves: 'Index de départ', fournisseurs: 'Fournisseurs',
    articles: 'Articles', mouvements: 'Stocks de départ', valorisations: 'Prix de départ', programmes: 'Programmes préventifs', personnes: 'Personnes' };
  const ROLES = { responsable: 'Responsable', technicien: 'Technicien', prestataire: 'Prestataire', magasinier: 'Magasinier', achats: 'Achats', exploitation: 'Exploitation', pilote: 'Pilote' };
  let etat = null; // dernière vérification : { entId, lot, fichier, conv, serveur }

  const charger = src => new Promise((ok, ko) => {
    if (document.querySelector(`script[data-src="${src}"]`)) return ok();
    const s = document.createElement('script'); s.src = src; s.dataset.src = src; s.onload = ok; s.onerror = () => ko(new Error('Chargement impossible : ' + src));
    document.head.append(s);
  });
  const nouveauLot = () => 'lot-' + new Date().toISOString().slice(0, 10).replace(/-/g, '') + '-' + Math.random().toString(36).slice(2, 10);
  const tuiles = resume => `<div class="tiles">${Object.entries(TYPES).filter(([k]) => resume[k]).map(([k, l]) => `<div class="tile"><b>${resume[k]}</b><span>${esc(l)}</span></div>`).join('') || '<p class="muted small">Rien à importer.</p>'}</div>`;
  const tableau = (lignes, max = 200) => `<div style="overflow-x:auto"><table class="small" style="width:100%;border-collapse:collapse">
      <thead><tr>${['Onglet', 'Ligne', 'Colonne', 'Problème'].map(h => `<th style="text-align:left;padding:4px 6px;border-bottom:1px solid var(--line,#e4e2dc)">${h}</th>`).join('')}</tr></thead>
      <tbody>${lignes.slice(0, max).map(e => `<tr>${[e.onglet, e.ligne, e.champ, e.message].map(v => `<td style="padding:4px 6px;border-bottom:1px solid var(--line,#e4e2dc);vertical-align:top">${esc(v)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>
    ${lignes.length > max ? `<p class="small muted">… et ${lignes.length - max} autre(s).</p>` : ''}`;

  V.miseenservice = r => Sync.profil()?.adminPlateforme
    ? `<p class="small" style="margin:0 0 6px"><a href="#/plateforme">← Console plateforme</a></p><h1 id="mes-titre">Mise en service</h1>
       <div id="mes" data-ent="${esc(r.id || '')}"><p class="muted">Chargement…</p></div>`
    : empty('Réservé à l’administrateur plateforme.');

  AFTER.miseenservice = async r => {
    const box = document.querySelector('#mes');
    if (!box) return;
    const ent = r.id;
    try {
      const [liste, mes] = await Promise.all([Sync.pf.entreprises(), Sync.pf.mesLire(ent)]);
      const e = liste.find(x => x.id === ent);
      if (!e) { box.innerHTML = empty('Entreprise introuvable.'); return; }
      document.querySelector('#mes-titre').textContent = `Mise en service · ${e.nom}`;
      const faits = mes.etapes || {};
      const nbFaits = ETAPES.filter(([k]) => faits[k]).length;
      box.innerHTML = `
        <p class="small muted" style="margin-top:0">${esc(e.code)} · ${badge(e.abonnement?.packNom || '—', 'blue')} · sites : ${(e.sites || []).map(s => `<b>${esc(s.code)}</b> ${esc(s.nom)}`).join(', ') || '—'} · ${e.fiches} fiche(s) sur le serveur</p>
        <h2>Étapes <span class="muted small">${nbFaits} / ${ETAPES.length}</span></h2>
        <div class="card"><ul class="lines">${ETAPES.map(([k, l]) => `<li><label class="check grow" style="margin:0"><input type="checkbox" data-etape="${k}" ${faits[k] ? 'checked' : ''}> ${esc(l)}</label>${faits[k] ? `<span class="small muted">${esc(fmtY(String(faits[k]).slice(0, 16)))}</span>` : ''}</li>`).join('')}</ul></div>
        <h2>Kit de démarrage</h2>
        <div class="card"><p class="small" style="margin-top:0">Un seul fichier Excel : lieux, équipements, compteurs, articles et stock, préventif, fournisseurs, personnes. À envoyer au client, ou à remplir avec lui à partir de ses listes existantes.</p>
          <div class="actions" style="margin-bottom:0"><a class="btn" href="kit/Kit_demarrage_Perfora.xlsx" download>Télécharger le kit vide</a></div></div>
        <h2>Importer un kit rempli</h2>
        <div class="card"><p class="small" style="margin-top:0">1. Choisir le fichier : l’appli le lit et le vérifie, <b>rien n’est enregistré</b>. 2. Corriger l’Excel tant qu’il reste des erreurs. 3. Importer : tout ou rien, annulable tant que le client n’a rien saisi.</p>
          <input type="file" id="mes-fichier" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet">
          <div id="mes-rapport"></div></div>
        <h2>Lots importés</h2>
        <div class="card">${(mes.lots || []).length ? `<ul class="lines">${mes.lots.map(l => `<li style="flex-wrap:wrap"><span class="grow"><b>${esc(fmtY(String(l.creeLe).slice(0, 16)))}</b> · ${esc(l.fichier || '')}<br><span class="small muted">${Object.entries(l.resume || {}).map(([k, n]) => `${n} ${esc((TYPES[k] || k).toLowerCase())}`).join(' · ')}</span></span>
            ${l.annuleLe ? badge('annulé', 'red') : `<button class="btn sm ghost danger" data-annuler="${esc(l.id)}">Annuler le lot</button>`}</li>`).join('')}</ul>` : '<p class="muted small" style="margin:0">Aucun import pour ce client.</p>'}</div>
        <div id="mes-invit"></div>`;

      box.querySelectorAll('[data-etape]').forEach(c => c.onchange = async () => {
        try { await Sync.pf.mesEtape(ent, c.dataset.etape, c.checked); toast(c.checked ? 'Étape cochée' : 'Étape décochée'); }
        catch (err) { toast('Échec : ' + err.message); }
        AFTER.miseenservice(r);
      });
      box.querySelectorAll('[data-annuler]').forEach(b => b.onclick = async () => {
        if (!(await askConfirm('Annuler le lot', 'Toutes les fiches de ce lot seront supprimées du serveur. Impossible si le client a déjà saisi quelque chose depuis. Les appareils déjà synchronisés garderont leur copie : faites-le avant d’inviter l’équipe.', 'Annuler le lot'))) return;
        try { const x = await Sync.pf.annulerLot(ent, b.dataset.annuler); toast(`${x.supprimees} fiche(s) supprimée(s)`); }
        catch (err) { await alertBox('Annulation refusée', [err.message]); }
        AFTER.miseenservice(r);
      });
      box.querySelector('#mes-fichier').onchange = ev => verifier(ent, e, ev.target.files[0], r);
      if (etat?.entId === ent && etat.importe) afficherInvitations(ent, e);
    } catch (err) { box.innerHTML = `<p class="warn">Mise en service indisponible : ${esc(err.message)}</p>`; }
  };

  async function verifier(ent, e, fichier, r) {
    const out = document.querySelector('#mes-rapport');
    if (!fichier) return;
    out.innerHTML = '<p class="muted small">Lecture du fichier…</p>';
    try {
      await charger('js/xlsx.js');
      await charger('js/kit.js');
      const [cl, ref] = await Promise.all([Xlsx.lire(fichier), Sync.pf.referentiel(ent)]);
      const manquants = Kit.ONGLETS.filter(o => !cl[o]);
      if (manquants.length === Kit.ONGLETS.length) throw new Error('Ce fichier n’est pas un kit de démarrage Perfora (onglets introuvables).');
      const listes = cl['Listes'] || [];
      const colClasse = (listes.find(l => l.n === 1)?.cellules || []).indexOf('classe');
      const classes = colClasse < 0 ? [] : listes.filter(l => l.n > 1).map(l => l.cellules[colClasse]).filter(Boolean).map(v => String(v).split(' · ')[0].trim());
      const onglets = Object.fromEntries(Kit.ONGLETS.map(o => [o, Kit.objets(cl[o] || [])]));
      const lot = nouveauLot();
      const conv = Kit.convertir(onglets, { sites: ref.sites, existants: ref, classes, aujourdhui: Store.now().slice(0, 10), lot, uid: Store.uid, par: 'Reprise Perfora' });
      // Données hors du pack du client : importées quand même, mais inutilisables tant que le pack n'est pas changé.
      const modules = e.abonnement?.modules || [];
      const NOM_MOD = { magasin: 'Magasin', achats: 'Achats', preventif: 'Préventif', energie: 'Énergie et eau' };
      const usageCpt = new Map(conv.fiches.filter(f => f.type === 'compteurs').map(f => [f.id, f.data.usage]));
      const moduleDe = f => ({ articles: 'magasin', mouvements: 'magasin', fournisseurs: 'magasin', valorisations: 'achats', programmes: 'preventif',
        compteurs: f.data.usage === 'equipement' ? 'preventif' : 'energie', releves: usageCpt.get(f.data.compteurId) === 'equipement' ? 'preventif' : 'energie' })[f.type];
      const horsPack = {};
      for (const f of conv.fiches) { const m = moduleDe(f); if (m && !modules.includes(m)) horsPack[m] = (horsPack[m] || 0) + 1; }
      let serveur = null;
      if (!conv.erreurs.length && conv.fiches.length) serveur = await Sync.pf.importer(ent, lot, fichier.name, conv.fiches, true);
      etat = { entId: ent, lot, fichier: fichier.name, conv, serveur, importe: false };
      const refus = serveur?.refus || [];
      const ok = !conv.erreurs.length && conv.fiches.length && !refus.length;
      out.innerHTML = `<h3 style="margin:14px 0 6px">${esc(fichier.name)}</h3>
        ${manquants.length ? `<p class="warn small">Onglet(s) absent(s), ignoré(s) : ${esc(manquants.join(', '))}.</p>` : ''}
        ${tuiles(conv.resume)}
        ${Object.keys(horsPack).length ? `<p class="warn small">Pack ${esc(e.abonnement?.packNom || '')} : ${Object.entries(horsPack).map(([m, n]) => `${n} fiche(s) du module « ${esc(NOM_MOD[m] || m)} »`).join(', ')} hors abonnement. Elles seront importées mais inutilisables tant que le pack n’est pas changé (ou retirez-les du kit).</p>` : ''}
        ${conv.erreurs.length ? `<p class="warn"><b>${conv.erreurs.length} erreur(s)</b> à corriger dans l’Excel, puis choisir à nouveau le fichier. Rien n’a été enregistré.</p>${tableau(conv.erreurs)}` : ''}
        ${refus.length ? `<p class="warn"><b>${refus.length} refus du serveur</b> (vérification à blanc) :</p><ul class="small">${refus.slice(0, 50).map(x => `<li>${esc(TYPES[x.type] || x.type)} : ${esc(x.motif)}</li>`).join('')}</ul>` : ''}
        ${conv.avertissements.length ? `<details class="more"${conv.erreurs.length ? '' : ' open'}><summary>${conv.avertissements.length} point(s) d’attention (n’empêchent pas l’import)</summary>${tableau(conv.avertissements)}</details>` : ''}
        ${ok ? `<p class="info">Vérification réussie, y compris sur le serveur : <b>${conv.fiches.length} fiche(s)</b> prêtes.${conv.invitations.length ? ` ${conv.invitations.length} personne(s) avec e-mail pourront être invitées après l’import.` : ''}</p>
          <div class="actions"><button class="btn primary" id="mes-importer">Importer ${conv.fiches.length} fiche(s)</button></div>` : ''}`;
      const b = document.querySelector('#mes-importer');
      if (b) b.onclick = () => importer(ent, e, r);
    } catch (err) { out.innerHTML = `<p class="warn">${esc(err.message)}</p>`; }
    finally { const f = document.querySelector('#mes-fichier'); if (f) f.value = ''; }
  }

  async function importer(ent, e, r) {
    const { conv, lot, fichier } = etat;
    if (!(await askConfirm('Importer le kit', `${conv.fiches.length} fiche(s) seront créées chez « ${e.nom} » (lot annulable tant que le client n’a rien saisi).`, 'Importer'))) return;
    try {
      const x = await Sync.pf.importer(ent, lot, fichier, conv.fiches, false);
      if (!x.importe) { await alertBox('Import refusé', (x.refus || []).slice(0, 20).map(y => `${TYPES[y.type] || y.type} : ${y.motif}`)); return; }
      etat.importe = true;
      await Sync.pf.mesEtape(ent, 'import', true).catch(() => {});
      toast(`${x.acceptes} fiche(s) importée(s)`);
    } catch (err) { await alertBox('Import impossible', [err.message]); }
    AFTER.miseenservice(r);
  }

  function afficherInvitations(ent, e) {
    const inv = etat.conv.invitations;
    const box = document.querySelector('#mes-invit');
    if (!box || !inv.length) return;
    box.innerHTML = `<h2>Invitations</h2><div class="card"><p class="small" style="margin-top:0">Personnes du kit ayant un e-mail. Chaque clic envoie un e-mail d’invitation (rôle et sites du kit). Invitez d’abord le responsable.</p>
      <ul class="lines">${inv.map((p, i) => `<li><span class="grow"><b>${esc(p.nom)}</b> · ${esc(ROLES[p.role] || p.role)}<br><span class="small muted">${esc(p.email)}</span></span>${p.envoye ? badge('invité', 'green') : `<button class="btn sm" data-inviter="${i}">Inviter</button>`}</li>`).join('')}</ul></div>`;
    box.querySelectorAll('[data-inviter]').forEach(b => b.onclick = async () => {
      const p = inv[Number(b.dataset.inviter)];
      if (!(await askConfirm('Envoyer l’invitation', `Un e-mail sera envoyé à ${p.email} (${ROLES[p.role] || p.role}, ${e.nom}).`, 'Envoyer'))) return;
      try {
        const x = await Sync.inviter({ email: p.email, nom: p.nom, role: p.role, sites: p.sites, entrepriseId: ent, redirectTo: adressePublique() });
        p.envoye = true;
        toast(x.emailEnvoye ? `E-mail envoyé à ${p.email}` : `${p.email} rattaché (compte existant)`);
        if (p.role === 'responsable') await Sync.pf.mesEtape(ent, 'responsable_invite', true).catch(() => {});
      } catch (err) { await alertBox('Invitation refusée', [err.message]); }
      afficherInvitations(ent, e);
    });
  }
})();
