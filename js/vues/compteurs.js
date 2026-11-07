/* GMAO terrain — compteurs et relevés sur le terrain (volet D, étape D3 ; V3 §19).
   Deux familles : compteurs de ressources (électricité, eau… : module energie) et compteurs d'équipement (heures,
   cycles… : module preventif, pour le préventif selon l'usage). Un relevé n'est jamais modifié : une erreur se corrige
   par un nouveau relevé lié (remplaceId) ; un remplacement ou une remise à zéro se déclare (relevé « rupture »).
   Contrôle immédiat à la saisie (Calculs.controleReleve). Script classique chargé après achats.js. */
(() => {
  const { V, A, AFTER, esc, badge, empty, askForm, askConfirm, askText, alertBox, toast, list, render, fmt, fmtY, today, aModule, autorise, adressePublique, eq, locPath, ajouterFichier } = App;
  const { data } = Store;

  const RESSOURCE = { electricite: 'Électricité', eau: 'Eau', gasoil: 'Gasoil', fuel: 'Fuel', gaz: 'Gaz', air_comprime: 'Air comprimé', froid: 'Froid', autre: 'Autre' };
  const MODE = { cumulatif: 'Cumulatif (index qui augmente)', periode: 'Non cumulatif (quantité consommée)', instantane: 'Valeur instantanée (°C, bar…)' };
  const ANOM = { valeur_invalide: 'valeur illisible', unite: 'unité différente de celle du compteur', date_future: 'date dans le futur', doublon: 'relevé en double (même heure que le précédent)',
    baisse_index: 'index plus bas que le relevé précédent', valeur_negative: 'quantité négative', date_incoherente: 'début de période après la date du relevé',
    chevauchement: 'période qui chevauche la précédente', variation: 'consommation inhabituelle par rapport aux relevés précédents' };
  const STATUT = { retenu: ['retenu', 'green'], suspect: ['à examiner', 'amber'], invalide: ['invalidé', 'red'], remplace: ['remplacé', ''], rupture: ['remplacement / remise à zéro', 'blue'] };
  const RUPTURE = { remplacement: 'Compteur remplacé', remise_zero: 'Remise à zéro', coefficient: 'Changement de coefficient' };

  const moduleDe = c => (c.usage === 'equipement' ? 'preventif' : 'energie');
  const visibles = () => list('compteurs').filter(c => c.actif !== false && aModule(moduleDe(c)));
  const relevesDe = id => [...data.releves.values()].filter(r => r.compteurId === id);
  const nf = n => (n == null || n === '' ? '—' : Number(n).toLocaleString('fr-FR', { maximumFractionDigits: 2 }));
  const lienReleve = c => `${adressePublique().replace(/#.*$/, '')}#/releve?cpt=${encodeURIComponent(c.code)}`;
  const parCode = code => [...data.compteurs.values()].find(c => (c.code || '').toLowerCase() === String(code || '').trim().toLowerCase());
  const analyse = c => Calculs.analyserReleves(c, relevesDe(c.id), { maintenant: Store.now() });
  const dernierRetenu = c => [...analyse(c).lignes].reverse().find(l => l.statut === 'retenu')?.releve || null;
  const dus = () => Calculs.relevesDus(visibles(), [...data.releves.values()], today());
  const peutRelever = () => autorise('releve-saisir');
  const nomCompteur = c => c.libelle || c.code;
  const quoi = c => (c.usage === 'equipement' ? (eq(c.equipementId)?.designation || 'équipement') : (RESSOURCE[c.ressource] || 'ressource'));

  // Utilisés par l'accueil, la fiche équipement, le préventif et la planche de QR (app.js).
  App.compteurs = { RESSOURCE, ANOM, visibles, dus, lienReleve, nomCompteur, quoi, dernierRetenu, relevesDe, parCode };

  function carteDu(x) {
    const c = x.compteur, der = dernierRetenu(c);
    return `<div class="card"><div class="row"><span class="t grow">${esc(nomCompteur(c))}</span>${badge(x.retardJours > 0 ? `en retard de ${x.retardJours} j` : 'à relever', x.retardJours > 0 ? 'red' : 'amber')}</div>
      <div class="s">${esc(c.code)} · ${esc(quoi(c))}${der ? ` · dernier : ${nf(der.valeur)} ${esc(c.unite)} le ${fmt(der.le)}` : ' · jamais relevé'}</div>
      ${peutRelever() ? `<div class="actions" style="margin-bottom:0"><a class="btn sm primary" href="#/releve?c=${c.id}">Relever</a></div>` : ''}</div>`;
  }
  App.carteReleveDu = carteDu;

  V.compteurs = () => {
    const l = visibles(), d = dus();
    const carte = c => {
      const a = analyse(c), der = [...a.lignes].reverse().find(x => x.statut === 'retenu')?.releve, sus = a.lignes.filter(x => x.statut === 'suspect').length, du = d.find(x => x.compteur.id === c.id);
      return `<a class="card" href="#/compteur/${c.id}"><div class="row"><span class="t grow">${esc(nomCompteur(c))}</span>${du ? badge(du.retardJours > 0 ? `en retard ${du.retardJours} j` : 'à relever', du.retardJours > 0 ? 'red' : 'amber') : ''}${sus ? ' ' + badge(`${sus} à examiner`, 'amber') : ''}</div>
        <div class="s">${esc(c.code)} · ${esc(quoi(c))} · ${esc(c.unite)}${c.frequenceJours ? ` · tous les ${c.frequenceJours} j` : ''}</div>
        <div class="s">${der ? `Dernier relevé : <b>${nf(der.valeur)} ${esc(c.unite)}</b> · ${fmt(der.le)}` : 'Jamais relevé'}</div></a>`;
    };
    const eqs = l.filter(c => c.usage === 'equipement'), res = l.filter(c => c.usage !== 'equipement');
    return `<h1>Compteurs</h1>
      ${d.length ? `<h2>Relevés à faire (${d.length})</h2>${d.map(carteDu).join('')}` : ''}
      ${eqs.length ? `<h2>Équipements (heures, cycles…)</h2>${eqs.map(carte).join('')}` : ''}
      ${res.length ? `<h2>Énergie et eau</h2>${res.map(carte).join('')}` : ''}
      ${l.length ? '' : empty('Aucun compteur.')}
      <div class="actions">${autorise('cpt-new') ? '<button class="btn" data-act="cpt-new">+ Compteur</button>' : ''}${l.length ? '<a class="btn ghost" href="#/qr?type=compteurs">QR des compteurs</a>' : ''}</div>`;
  };

  V.compteur = r => {
    const c = data.compteurs.get(r.id);
    if (!c) return empty('Compteur introuvable.');
    const a = analyse(c), lignes = [...a.lignes].reverse();
    const derLigne = lignes.find(l => l.releve.nature !== 'rupture' && l.statut !== 'remplace' && l.statut !== 'invalide');
    const progs = list('programmes').filter(p => p.compteurId === c.id && p.actif !== false);
    const parent = c.parentId ? data.compteurs.get(c.parentId) : null;
    const lien = lienReleve(c);
    return `<div class="row"><h1 class="grow">${esc(nomCompteur(c))}</h1>${badge(c.usage === 'equipement' ? 'Équipement' : 'Énergie / eau', 'blue')}</div>
      <div class="card"><dl class="kv"><dt>Code</dt><dd>${esc(c.code)}</dd>
        <dt>${c.usage === 'equipement' ? 'Équipement' : 'Ressource'}</dt><dd>${c.usage === 'equipement' && c.equipementId ? `<a href="#/eq/${c.equipementId}">${esc(quoi(c))}</a>` : esc(quoi(c))}</dd>
        <dt>Mesure</dt><dd>${esc(MODE[c.mode] || c.mode)} · ${esc(c.unite)}${Number(c.coefficient) && Number(c.coefficient) !== 1 ? ` · coefficient ${nf(c.coefficient)}` : ''}</dd>
        ${parent ? `<dt>Sous-compteur de</dt><dd><a href="#/compteur/${parent.id}">${esc(nomCompteur(parent))}</a></dd>` : ''}
        <dt>Relevé</dt><dd>${c.frequenceJours ? `tous les ${c.frequenceJours} jours` : 'sans fréquence fixée'}</dd></dl>
        <div class="row" style="margin-top:12px;align-items:flex-start">${QR.svg(lien, 96)}<p class="small muted grow" style="margin:0">Scanner ce code ouvre la saisie d’un relevé sur ce compteur.<br><a class="btn sm ghost" href="#/qr?type=compteurs&cpt=${c.id}">Imprimer</a></p></div></div>
      <div class="actions">${peutRelever() ? `<a class="btn primary" href="#/releve?c=${c.id}">Relever</a><button class="btn" data-act="cpt-rupture" data-id="${c.id}">Remplacement / remise à zéro</button>` : ''}
        ${autorise('cpt-edit') ? `<button class="btn ghost" data-act="cpt-edit" data-id="${c.id}">Modifier</button>` : ''}</div>
      ${progs.length ? `<h2>Préventif selon ce compteur</h2>${progs.map(p => App.progCard(p)).join('')}` : ''}
      <h2>Relevés</h2>
      <div class="card">${lignes.length ? `<ul class="lines">${lignes.slice(0, 40).map(l => {
        const x = l.releve, s = STATUT[l.statut] || [l.statut, ''];
        const valeur = x.nature === 'rupture' ? `${esc(RUPTURE[x.typeRupture] || 'Remplacement')}${x.indexFinal != null ? ` · ancien ${nf(x.indexFinal)}` : ''}${x.indexInitial != null ? ` · nouveau ${nf(x.indexInitial)}` : ''}${x.coefficient != null ? ` · coef. ${nf(x.coefficient)}` : ''}` : `<b>${nf(x.valeur)} ${esc(c.unite)}</b>${x.estime ? ' (estimé)' : ''}`;
        const qualif = l.statut === 'suspect' && autorise('releve-qualifier')
          ? `<span class="row" style="gap:6px">${l.confirmable ? `<button class="btn sm" data-act="releve-qualifier" data-id="${x.id}" data-decision="confirme">Confirmer</button>` : ''}<button class="btn sm ghost danger" data-act="releve-qualifier" data-id="${x.id}" data-decision="invalide">Invalider</button></span>` : '';
        const corriger = derLigne && derLigne.releve.id === x.id && peutRelever() ? `<a class="btn sm ghost" href="#/releve?c=${c.id}&remplace=${x.id}">Corriger</a>` : '';
        return `<li style="flex-wrap:wrap"><span class="grow">${valeur}<br><span class="small muted">${fmtY(x.le)} · ${esc(x.creePar || '')}${x.motif ? ' · ' + esc(x.motif) : ''}${x.motifDecision ? ' · décision : ' + esc(x.motifDecision) : ''}</span>
          ${l.anomalies?.length ? `<br><span class="small" style="color:var(--amber)">${l.anomalies.map(k => esc(ANOM[k] || k)).join(' ; ')}</span>` : ''}</span>${[...data.photos.values()].filter(ph => ph.parentId === x.id).map(ph => `<button type="button" class="btn sm ghost" data-act="photo-voir" data-id="${ph.id}" aria-label="Photo du relevé">📷</button>`).join('')}${badge(...s)}${qualif}${corriger}</li>`;
      }).join('')}</ul>` : '<p class="muted" style="margin:0">Aucun relevé.</p>'}
        <p class="small muted">Un relevé n’est jamais modifié : « Corriger » enregistre un nouveau relevé qui remplace l’ancien (l’historique reste visible). Un relevé « à examiner » n’entre pas dans les calculs tant que le responsable n’a pas décidé.</p></div>
      `;
  };

  // ---------- saisie d'un relevé ----------
  V.releve = r => {
    const c = r.q.get('c') ? data.compteurs.get(r.q.get('c')) : parCode(r.q.get('cpt'));
    if (!c) return r.q.get('cpt') ? `<p class="warn">Le QR désigne le compteur <b>${esc(r.q.get('cpt'))}</b>, inconnu sur cet appareil (autre site, ou données pas encore synchronisées).</p>` : empty('Compteur introuvable.');
    if (!peutRelever()) return `<p class="warn">Votre rôle ne permet pas de saisir des relevés.</p><a class="btn" href="#/compteur/${c.id}">Voir le compteur</a>`;
    const remplace = r.q.get('remplace') ? data.releves.get(r.q.get('remplace')) : null;
    const der = dernierRetenu(c);
    return `<p class="small" style="margin:0 0 6px"><a href="#/compteur/${c.id}">← ${esc(nomCompteur(c))}</a></p>
      <h1>${remplace ? 'Corriger un relevé' : 'Relevé'} · ${esc(nomCompteur(c))}</h1>
      ${remplace ? `<p class="info small">Remplace le relevé du ${fmtY(remplace.le)} (${nf(remplace.valeur)} ${esc(c.unite)}), qui reste visible dans l’historique.</p>` : ''}
      <form id="rel" class="card" novalidate>
        <p class="small muted" style="margin-top:0">${esc(c.code)} · ${esc(quoi(c))}${der ? ` · dernier relevé retenu : <b>${nf(der.valeur)} ${esc(c.unite)}</b> le ${fmtY(der.le)}` : ' · premier relevé'}</p>
        <label class="f" for="rel-v">${c.mode === 'periode' ? 'Quantité consommée' : c.mode === 'instantane' ? 'Valeur mesurée' : 'Index lu sur le compteur'} (${esc(c.unite)})</label>
        <input id="rel-v" name="valeur" type="number" step="any" inputmode="decimal" required style="font-size:1.6rem;font-weight:700" value="${remplace ? esc(remplace.valeur) : ''}">
        <div id="rel-ctl" class="small" style="min-height:1.4em;margin-top:6px"></div>
        <label class="check"><input type="checkbox" name="estime"> Valeur estimée (compteur illisible, estimation)</label>
        <label class="f">Heure du relevé</label>
        <div class="chips"><label class="chip"><input type="radio" name="quand" value="maintenant" checked><span>Maintenant</span></label><label class="chip"><input type="radio" name="quand" value="autre"><span>Autre heure</span></label></div>
        <input type="datetime-local" name="le" class="hidden" style="margin-top:8px" value="${esc(remplace ? remplace.le : Store.now())}">
        ${c.mode === 'periode' ? `<label class="f" for="rel-d">Début de la période <span class="opt">(facultatif : par défaut, le relevé précédent)</span></label><input id="rel-d" name="debut" type="datetime-local">` : ''}
        <label class="f">Photo du compteur <span class="opt">(facultatif)</span></label>
        <input type="file" id="rel-photo" accept="image/*" capture="environment" class="hidden"><button type="button" class="btn sm" id="rel-photo-btn">📷 Photo</button> <span id="rel-photo-ok" class="small muted"></span>
        <div class="sticky-save"><button class="btn primary block" type="submit">Enregistrer le relevé</button></div>
      </form>`;
  };

  AFTER.releve = r => {
    const f = document.querySelector('#rel');
    if (!f) return;
    const c = r.q.get('c') ? data.compteurs.get(r.q.get('c')) : parCode(r.q.get('cpt'));
    const remplaceId = r.q.get('remplace') || null;
    let photo = null;
    const autresReleves = () => relevesDe(c.id).filter(x => x.id !== remplaceId);
    const candidat = () => ({ le: f.quand.value === 'autre' && f.le.value ? f.le.value : Store.now(), valeur: f.valeur.value === '' ? null : Number(f.valeur.value), unite: c.unite, debut: f.debut?.value || undefined });
    const controle = () => {
      const box = document.querySelector('#rel-ctl');
      if (f.valeur.value === '') { box.innerHTML = ''; return null; }
      const k = Calculs.controleReleve(c, autresReleves(), candidat(), { maintenant: Store.now() });
      const p = k.precedent;
      if (!k.anomalies.length) {
        const ecart = p && c.mode === 'cumulatif' ? Number(f.valeur.value) - Number(p.valeur) : null;
        box.innerHTML = `<span style="color:var(--green)">✓ Cohérent${ecart != null ? ` : +${nf(ecart)} ${esc(c.unite)} depuis le ${fmt(p.le)}` : ''}</span>`;
      } else box.innerHTML = `<span style="color:var(--amber)">⚠ ${k.anomalies.map(a => esc(ANOM[a] || a)).join(' ; ')}${p && k.anomalies.includes('baisse_index') ? ` (précédent : ${nf(p.valeur)} ${esc(c.unite)})` : ''}</span>`;
      return k;
    };
    f.valeur.oninput = controle;
    f.addEventListener('change', () => { f.le.classList.toggle('hidden', f.quand.value !== 'autre'); controle(); });
    document.querySelector('#rel-photo-btn').onclick = () => document.querySelector('#rel-photo').click();
    document.querySelector('#rel-photo').onchange = ev => { photo = ev.target.files[0] || null; document.querySelector('#rel-photo-ok').textContent = photo ? '✓ photo prise' : ''; };
    if (!remplaceId) f.valeur.focus();
    controle();
    f.onsubmit = async ev => {
      ev.preventDefault();
      if (f.valeur.value === '' || !Number.isFinite(Number(f.valeur.value))) { toast('Saisissez la valeur lue'); return; }
      const k = controle(), cand = candidat();
      if (k.anomalies.includes('baisse_index')) {
        const v = await askForm({ title: 'Index plus bas que le précédent', ok: 'Continuer', values: { choix: 'erreur' }, fields: [
          { type: 'info', text: `Vous avez saisi ${nf(cand.valeur)} ${c.unite}, le relevé précédent était ${nf(k.precedent?.valeur)} ${c.unite}. Que s’est-il passé ?` },
          { name: 'choix', label: 'Choix', type: 'chips', required: true, options: { erreur: 'Je me suis trompé : je corrige', remplacement: 'Le compteur a été remplacé ou remis à zéro', garder: 'Enregistrer quand même (à examiner)' } }] });
        if (!v || v.choix === 'erreur') { f.valeur.focus(); return; }
        if (v.choix === 'remplacement') { if (!(await declarerRupture(c, { le: cand.le }))) return; }
      } else if (k.anomalies.length && !(await askConfirm('Relevé à vérifier', `${k.anomalies.map(a => ANOM[a] || a).join(' ; ')}. Vérifiez la valeur. L’enregistrer quand même ? Il sera examiné par le responsable avant d’entrer dans les calculs.`, 'Enregistrer'))) return;
      const id = Store.uid();
      const rel = { id, compteurId: c.id, le: cand.le, valeur: cand.valeur, unite: c.unite, estime: f.estime.checked, ...(cand.debut ? { debut: cand.debut } : {}), ...(remplaceId ? { remplaceId } : {}) };
      await Store.save('releves', rel, { action: remplaceId ? 'correction' : 'creation' });
      if (photo) { try { await ajouterFichier('releves', id, photo, `releve-${c.code}.jpg`); } catch (e) { toast('Photo non enregistrée : ' + e.message); } }
      toast(`Relevé enregistré : ${nf(cand.valeur)} ${c.unite}`);
      location.hash = dus().length ? '#/compteurs' : '#/compteur/' + c.id;
    };
  };

  async function declarerRupture(c, { indexInitialPropose = null, le = null } = {}) {
    const der = dernierRetenu(c);
    const v = await askForm({ title: `Remplacement ou remise à zéro · ${nomCompteur(c)}`, ok: 'Déclarer',
      values: { type: 'remplacement', indexFinal: der?.valeur ?? null, indexInitial: indexInitialPropose ?? 0 }, fields: [
        { name: 'type', label: 'Ce qui s’est passé', type: 'chips', options: RUPTURE, required: true },
        { name: 'indexFinal', label: `Dernier index de l’ancien compteur (${c.unite}), si connu`, type: 'number' },
        { name: 'indexInitial', label: `Index de départ du nouveau compteur (${c.unite})`, type: 'number' },
        { name: 'coefficient', label: 'Nouveau coefficient (si changé)', type: 'number' },
        { name: 'motif', label: 'Motif', type: 'text', required: true, placeholder: 'ex. compteur défectueux remplacé par le fournisseur' },
        { type: 'info', text: 'Les consommations sont calculées tronçon par tronçon : l’ancien et le nouveau compteur ne sont jamais soustraits l’un de l’autre.' }] });
    if (!v) return false;
    const t = le ? new Date(new Date(le).getTime() - 60000) : null;   // la rupture précède le premier relevé du nouveau compteur
    const leRupture = t ? `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}T${String(t.getHours()).padStart(2, '0')}:${String(t.getMinutes()).padStart(2, '0')}` : Store.now();
    await Store.save('releves', { id: Store.uid(), compteurId: c.id, nature: 'rupture', typeRupture: v.type, le: leRupture, indexFinal: v.indexFinal, indexInitial: v.indexInitial,
      ...(v.coefficient ? { coefficient: v.coefficient } : {}), motif: v.motif }, { action: 'rupture' });
    toast('Remplacement déclaré');
    return true;
  }
  A['cpt-rupture'] = async el => { if (await declarerRupture(data.compteurs.get(el.dataset.id))) render(); };

  A['releve-qualifier'] = async el => {
    const x = data.releves.get(el.dataset.id), d = el.dataset.decision;
    const m = await askText(d === 'confirme' ? 'Confirmer le relevé' : 'Invalider le relevé', d === 'confirme' ? 'Pourquoi cette valeur est juste (vérifiée sur place, arrêt, production…)' : 'Motif (erreur de lecture, autre compteur…)');
    if (!m) return;
    await Store.update('releves', x.id, { decision: d, motifDecision: m, decideLe: Store.now(), decidePar: Store.currentUserName() }, { action: d === 'confirme' ? 'confirmation' : 'invalidation', motif: m });
    toast(d === 'confirme' ? 'Relevé confirmé : il entre dans les calculs' : 'Relevé invalidé');
    render();
  };

  // ---------- création et modification d'un compteur (responsable) ----------
  function champsCompteur(c, verrouille) {
    const uniteOpts = [...new Set([...Calculs.UNITES, 'km', 't'])];
    return [
      { name: 'code', label: 'Code (imprimé dans le QR)', type: 'text', required: true, placeholder: 'ex. HRS-CMP01' },
      { name: 'libelle', label: 'Libellé', type: 'text', required: true, placeholder: 'ex. Heures de marche compresseur' },
      ...(verrouille ? [{ type: 'info', text: 'Compteur déjà relevé : usage, mesure, unité et coefficient sont figés (déclarez un remplacement pour les changer).' }] : [
        { name: 'usage', label: 'Usage', type: 'chips', required: true, options: { ...(aModule('energie') ? { ressource: 'Énergie / eau' } : {}), ...(aModule('preventif') ? { equipement: 'Équipement (heures, cycles…)' } : {}) } },
        { name: 'ressource', label: 'Ressource (énergie / eau)', type: 'select', options: Object.entries(RESSOURCE), empty: '—' },
        { name: 'unite', label: 'Unité', type: 'select', required: true, options: uniteOpts.map(u => [u, u]), empty: '— Choisir —' },
        { name: 'mode', label: 'Mesure', type: 'chips', required: true, options: MODE },
        { name: 'coefficient', label: 'Coefficient (1 par défaut)', type: 'number' }]),
      { name: 'equipementId', label: 'Équipement mesuré (obligatoire pour un compteur d’équipement)', type: 'select', options: list('equipements').filter(e => e.actif !== false).map(e => [e.id, `${e.designation} (${e.code})`]), empty: '—' },
      { name: 'parentId', label: 'Sous-compteur de (compteur principal, même unité)', type: 'select', options: list('compteurs').filter(x => x.id !== c?.id && x.usage !== 'equipement').map(x => [x.id, `${nomCompteur(x)} (${x.unite})`]), empty: '—' },
      { name: 'frequenceJours', label: 'Relever tous les … jours', type: 'number' },
      { name: 'toleranceVariation', label: 'Tolérance de variation (× la consommation habituelle, 3 par défaut)', type: 'number' }];
  }
  function verifier(v, c) {
    const usage = v.usage || c?.usage;
    if ([...data.compteurs.values()].some(x => x.id !== c?.id && (x.code || '').toLowerCase() === v.code.trim().toLowerCase())) return 'Ce code est déjà utilisé';
    if (usage === 'equipement' && !v.equipementId) return 'Choisissez l’équipement mesuré';
    if (usage === 'ressource' && !(v.ressource || c?.ressource)) return 'Choisissez la ressource';
    if (v.parentId && data.compteurs.get(v.parentId)?.unite !== (v.unite || c?.unite)) return 'Le compteur principal doit avoir la même unité';
    if (v.coefficient != null && v.coefficient <= 0) return 'Coefficient supérieur à 0';
    return null;
  }
  A['cpt-new'] = async () => {
    const v = await askForm({ title: 'Nouveau compteur', ok: 'Créer', values: { usage: aModule('energie') ? 'ressource' : 'equipement', mode: 'cumulatif', frequenceJours: 7 }, fields: champsCompteur(null, false) });
    if (!v) return;
    const err = verifier(v, null);
    if (err) { await alertBox('Compteur', [err]); return; }
    const c = { id: Store.uid(), ...v, code: v.code.trim().toUpperCase(), coefficient: v.coefficient || 1, ressource: v.usage === 'ressource' ? v.ressource : null, equipementId: v.equipementId || null, parentId: v.parentId || null, actif: true };
    await Store.save('compteurs', c);
    location.hash = '#/compteur/' + c.id;
  };
  A['cpt-edit'] = async el => {
    const c = data.compteurs.get(el.dataset.id);
    const verrouille = relevesDe(c.id).length > 0;
    const v = await askForm({ title: `Modifier · ${nomCompteur(c)}`, values: { ...c, inactif: c.actif === false }, fields: [...champsCompteur(c, verrouille), { name: 'inactif', label: 'Compteur retiré (n’apparaît plus dans les relevés à faire)', type: 'checkbox' }] });
    if (!v) return;
    const err = verifier(v, c);
    if (err) { await alertBox('Compteur', [err]); return; }
    const { inactif, ...p } = v;
    await App.edit('compteurs', c.id, { ...p, code: p.code.trim().toUpperCase(), actif: !inactif });
  };
})();
