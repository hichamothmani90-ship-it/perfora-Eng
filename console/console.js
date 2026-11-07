/* Centre de contrôle Perfora (CC1) : tableau de bord, clients, abonnements. Réservé à l'administrateur plateforme.
   Même adresse que l'appli : on réutilise sa connexion (stockage de l'appareil) ; chaque action est vérifiée par le
   serveur (fonctions pf_*). Aucune donnée n'est gardée hors ligne ici : tout est relu à chaque affichage. */
(() => {
  const K = CalculsConsole;
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const badge = (t, c = '') => `<span class="badge ${c}">${esc(t)}</span>`;
  const today = () => new Date(Date.now() - new Date().getTimezoneOffset() * 6e4).toISOString().slice(0, 10);
  const fmtD = s => (s ? String(s).slice(0, 10).split('-').reverse().join('/') : '—');
  const mad = n => (n == null ? '—' : `${Number(n).toLocaleString('fr-FR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })} MAD`);
  const depuis = s => { if (!s) return 'jamais'; const j = Math.round((Date.parse(today()) - Date.parse(String(s).slice(0, 10))) / 864e5); return j <= 0 ? 'aujourd’hui' : j === 1 ? 'hier' : `il y a ${j} j`; };
  function toast(m) { const t = $('#toast'); t.textContent = m; t.classList.add('show'); clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove('show'), 2400); }

  const ETAT = { actif: ['Actif', 'green'], essai: ['Essai', 'blue'], echu: ['Échu', 'red'], suspendu: ['Suspendu', 'red'], resilie: ['Résilié', ''], demo: ['Démo', 'amber'] };
  const etatBadge = c => { const [l, k] = ETAT[K.etat(c, today())]; return badge(l, k); };
  const PACKS = { essentiel: 'Essentiel', pro: 'Pro', entreprise: 'Entreprise' };
  const STATUTS = { essai: 'Essai', actif: 'Actif', suspendu: 'Suspendu', resilie: 'Résilié' };
  const SECTEURS = { agroalimentaire: 'Agroalimentaire', plasturgie: 'Plasturgie, emballage', textile: 'Textile', carrieres_btp: 'Carrières, BTP, matériaux',
    chimie: 'Chimie, pharmacie', automobile: 'Automobile, mécanique', energie_utilites: 'Énergie, eau, utilités', logistique: 'Logistique', tertiaire: 'Tertiaire, bâtiment', autre: 'Autre' };

  // ---------- fenêtre de saisie ----------
  function formulaire({ titre, ok = 'Enregistrer', champs, valeurs = {}, info = '' }) {
    return new Promise(resolve => {
      const d = document.createElement('dialog'); d.className = 'cc-dlg';
      const champ = f => {
        const v = valeurs[f.nom] ?? f.defaut ?? '';
        const lab = `<label class="f" for="cc_${f.nom}">${esc(f.label)}${f.requis ? '' : ' <span class="opt">(facultatif)</span>'}</label>`;
        const req = f.requis ? 'required' : '';
        const cls = f.plein ? 'plein' : '';
        if (f.type === 'select') return `<div class="${cls}">${lab}<select id="cc_${f.nom}" name="${f.nom}" ${req}>${f.vide !== undefined ? `<option value="">${esc(f.vide)}</option>` : ''}${Object.entries(f.options).map(([k, l]) => `<option value="${esc(k)}" ${String(v) === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>`;
        if (f.type === 'textarea') return `<div class="${cls}">${lab}<textarea id="cc_${f.nom}" name="${f.nom}" ${req}>${esc(v)}</textarea></div>`;
        if (f.type === 'checkbox') return `<div class="${cls}"><label class="check"><input type="checkbox" name="${f.nom}" ${v ? 'checked' : ''}> ${esc(f.label)}</label></div>`;
        return `<div class="${cls}">${lab}<input id="cc_${f.nom}" name="${f.nom}" type="${f.type || 'text'}" value="${esc(v)}" ${req} ${f.type === 'number' ? 'step="any"' : ''} placeholder="${esc(f.aide || '')}"></div>`;
      };
      d.innerHTML = `<form method="dialog"><h3>${esc(titre)}</h3>${info ? `<p class="small muted" style="margin-top:0">${info}</p>` : ''}<div class="cc-champs">${champs.map(champ).join('')}</div>
        <div class="actions"><button class="btn" value="annuler" formnovalidate>Annuler</button><button class="btn primary" value="ok">${esc(ok)}</button></div></form>`;
      document.body.append(d);
      let out = null;
      d.querySelector('form').addEventListener('submit', ev => {
        if (ev.submitter?.value !== 'ok') return;
        const f = ev.target; out = {};
        for (const c of champs) {
          const el = f.elements[c.nom];
          out[c.nom] = c.type === 'checkbox' ? el.checked : c.type === 'number' ? (el.value === '' ? null : Number(el.value)) : (el.value.trim() || null);
        }
      });
      d.addEventListener('close', () => { d.remove(); resolve(out); });
      d.showModal();
    });
  }
  const confirmer = async (titre, texte, ok = 'Confirmer') => !!(await formulaire({ titre, ok, champs: [], info: esc(texte) }));
  const erreur = e => toast('Refusé : ' + (e?.message || e));

  // ---------- données ----------
  let clients = [], tarifs = [];
  async function charger() { [clients, tarifs] = await Promise.all([Sync.pf.clients(), Sync.pf.tarifs()]); }
  const client = id => clients.find(c => c.id === id);
  const tarifDe = pack => tarifs.find(t => t.pack === pack) || {};

  // ---------- vues ----------
  const V = {};

  V.tableau = () => {
    const t = today(), s = K.synthese(clients, t), al = K.alertes(clients, t);
    const NIV = { 1: ['Urgent', 'red'], 2: ['À suivre', 'amber'], 3: ['Info', ''] };
    return `<h1>Tableau de bord <span class="muted small" style="font-weight:400">${fmtD(t)}</span></h1>
      <div class="tiles">
        <a class="tile green" href="#/clients"><b>${s.parEtat.actif}</b><span>Clients actifs</span></a>
        <a class="tile blue" href="#/clients"><b>${s.parEtat.essai}</b><span>En essai</span></a>
        <a class="tile" href="#/abonnements"><b>${mad(s.mrr)}</b><span>Revenu mensuel HT${s.sansPrix ? ` · ${s.sansPrix} sans prix` : ''}</span></a>
        <a class="tile" href="#/abonnements"><b>${mad(s.arr)}</b><span>Revenu annuel HT (projection)</span></a>
        <a class="tile ${s.echeances30 ? 'amber' : ''}" href="#/abonnements"><b>${s.echeances30}</b><span>Échéances sous 30 jours</span></a>
        <a class="tile ${s.parEtat.echu ? 'red' : ''}" href="#/abonnements"><b>${s.parEtat.echu}</b><span>Échus (lecture seule)</span></a>
        <a class="tile ${s.inactifs ? 'amber' : ''}" href="#/clients"><b>${s.inactifs}</b><span>Inactifs depuis 7 jours</span></a>
      </div>
      <h2>À traiter</h2>
      <div class="card" style="padding:0">${al.length ? al.map(a => `<div class="cc-alerte">${badge(...NIV[a.niveau])}<a href="#/client/${a.client.id}"><b>${esc(a.client.nom)}</b></a><span class="grow">${esc(a.texte)}</span></div>`).join('')
        : '<p class="muted" style="margin:0;padding:14px">Rien à traiter.</p>'}</div>
      <p class="small muted">Revenu : prix convenus HT, remises déduites, abonnements annuels ramenés au mois ; un prix inconnu n’est jamais compté comme 0. Les démonstrations sont exclues. « Inactif » : aucune saisie du client (hors import) depuis 7 jours.</p>`;
  };

  V.clients = r => {
    const q = (r.q.get('q') || '').toLowerCase();
    const liste = clients.filter(c => !q || `${c.nom} ${c.code} ${c.fiche?.raisonSociale || ''} ${c.fiche?.ville || ''}`.toLowerCase().includes(q));
    return `<h1>Clients</h1>
      <div class="cc-outils"><input type="search" id="cc-q" placeholder="Rechercher (nom, code, ville)" value="${esc(q)}"><span class="grow"></span><button class="btn primary sm" id="cc-nouveau">+ Nouveau client</button></div>
      <table class="cc-table"><thead><tr><th>Client</th><th>État</th><th>Pack</th><th class="num">Utilisateurs</th><th class="num">Sites</th><th>Dernière saisie</th><th class="num">Revenu mensuel</th><th>Mise en service</th></tr></thead>
      <tbody>${liste.map(c => {
        const a = c.abonnement || {}, faites = K.ETAPES_MES.filter(k => (c.miseEnService || {})[k]).length;
        return `<tr class="lien" data-id="${c.id}"><td><b>${esc(c.nom)}</b><br><span class="small muted">${esc(c.code)}${c.fiche?.ville ? ' · ' + esc(c.fiche.ville) : ''}</span></td><td>${etatBadge(c)}</td>
          <td>${esc(a.packNom || a.pack || '—')}</td><td class="num">${c.actifs}${a.maxUtilisateursTotal != null ? ' / ' + a.maxUtilisateursTotal : ''}</td><td class="num">${(c.sites || []).filter(s => s.actif).length}</td>
          <td>${esc(depuis(c.derniereActivite))}</td><td class="num">${c.demo ? '—' : mad(K.mensuel(a))}</td><td>${c.demo ? '—' : `${faites} / ${K.ETAPES_MES.length}`}</td></tr>`;
      }).join('') || '<tr><td colspan="8" class="muted">Aucun client.</td></tr>'}</tbody></table>`;
  };

  V.client = r => {
    const c = client(r.id);
    if (!c) return `<p class="muted">Client introuvable. <a href="#/clients">Retour</a></p>`;
    const a = c.abonnement || {}, f = c.fiche || {}, contacts = f.contacts || [];
    const faites = K.ETAPES_MES.filter(k => (c.miseEnService || {})[k]).length;
    const champ = (nom, label, type = 'text', aide = '') => `<div><label class="f" for="f_${nom}">${label}</label><input id="f_${nom}" name="${nom}" type="${type}" value="${esc(f[nom])}" placeholder="${esc(aide)}"></div>`;
    return `<p class="small" style="margin:0 0 6px"><a href="#/clients">← Clients</a></p>
      <div class="row"><h1 class="grow">${esc(c.nom)} <span class="muted small" style="font-weight:400">${esc(c.code)}</span></h1>${etatBadge(c)}</div>
      <div class="cc-deux">
        <div>
          <h2 style="margin-top:0">Identité et contacts</h2>
          <form class="card" id="cc-fiche">
            <div class="cc-champs">
              <div class="plein"><label class="f" for="f_raisonSociale">Raison sociale</label><input id="f_raisonSociale" name="raisonSociale" type="text" value="${esc(f.raisonSociale)}" placeholder="${esc(c.nom)}"></div>
              ${champ('ice', 'ICE', 'text', '15 chiffres')}${champ('rc', 'Registre de commerce')}
              ${champ('identifiantFiscal', 'Identifiant fiscal')}${champ('ville', 'Ville')}
              <div class="plein"><label class="f" for="f_adresse">Adresse de facturation</label><input id="f_adresse" name="adresse" type="text" value="${esc(f.adresse)}"></div>
              <div><label class="f" for="f_secteur">Secteur</label><select id="f_secteur" name="secteur"><option value="">—</option>${Object.entries(SECTEURS).map(([k, l]) => `<option value="${k}" ${f.secteur === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>
              ${champ('siteWeb', 'Site web', 'url')}
              <div class="plein"><label class="f" for="f_notes">Notes internes (jamais visibles du client)</label><textarea id="f_notes" name="notes">${esc(f.notes)}</textarea></div>
            </div>
            <h3 style="margin:14px 0 6px;font-size:1rem">Contacts</h3>
            <div style="overflow-x:auto"><table class="cc-table" id="cc-contacts"><thead><tr><th>Nom</th><th>Fonction</th><th>Téléphone</th><th>E-mail</th><th></th></tr></thead><tbody>
              ${[...contacts, {}].map((p, i) => `<tr data-i="${i}"><td><input type="text" name="c_nom" value="${esc(p.nom)}" placeholder="${i === contacts.length ? 'Nouveau contact' : ''}"></td><td><input type="text" name="c_fonction" value="${esc(p.fonction)}" placeholder="Directeur maintenance…"></td>
                <td><input type="tel" name="c_telephone" value="${esc(p.telephone)}" placeholder="+212…">${p.telephone ? ` <a class="small" target="_blank" rel="noopener" href="https://wa.me/${esc(String(p.telephone).replace(/[^0-9]/g, ''))}">WhatsApp</a>` : ''}</td><td><input name="c_email" type="email" value="${esc(p.email)}"></td>
                <td>${i < contacts.length ? `<button type="button" class="btn sm ghost danger" data-retirer="${i}">Retirer</button>` : ''}</td></tr>`).join('')}
            </tbody></table></div>
            <div class="actions" style="margin-bottom:0"><button class="btn primary" type="submit">Enregistrer la fiche</button></div>
          </form>
        </div>
        <div>
          <h2 style="margin-top:0">Abonnement</h2>
          <div class="card"><dl class="kv">
            <dt>Pack</dt><dd>${esc(a.packNom || a.pack || '—')}</dd><dt>Statut</dt><dd>${esc(STATUTS[a.statutAbonnement] || a.statutAbonnement || '—')}</dd>
            <dt>Période</dt><dd>du ${fmtD(a.debut)} au ${a.fin ? fmtD(a.fin) : '— (sans fin)'}</dd>
            <dt>Prix convenu</dt><dd>${a.prix == null ? '<span class="muted">non fixé</span>' : `${mad(a.prix)} HT / ${a.periodicite === 'annuel' ? 'an' : 'mois'}${Number(a.remisePct) ? ` · remise ${a.remisePct} %` : ''}`}</dd>
            <dt>Revenu mensuel</dt><dd>${c.demo ? '— (démo)' : mad(K.mensuel(a))}</dd>
            ${a.conditions ? `<dt>Conditions</dt><dd style="white-space:pre-wrap">${esc(a.conditions)}</dd>` : ''}
          </dl><div class="actions" style="margin-bottom:0"><button class="btn sm primary" data-abo="${c.id}">Modifier</button><button class="btn sm" data-prolonger="${c.id}" data-duree="mensuel">+ 1 mois</button><button class="btn sm" data-prolonger="${c.id}" data-duree="annuel">+ 1 an</button></div></div>
          <h2>Utilisation</h2>
          <div class="card"><dl class="kv">
            <dt>Utilisateurs actifs</dt><dd>${c.actifs}${a.maxUtilisateursTotal != null ? ' / ' + a.maxUtilisateursTotal : ''}</dd>
            <dt>Responsables</dt><dd>${esc((c.responsables || []).join(', ') || 'aucun')}</dd>
            <dt>Sites</dt><dd>${(c.sites || []).map(s => `${esc(s.code)} ${esc(s.nom)}${s.actif ? '' : ' (inactif)'}`).join('<br>') || '—'}</dd>
            <dt>Fiches</dt><dd>${c.fiches} · ${c.activite7j} saisie(s) sur 7 jours</dd>
            <dt>Dernière saisie</dt><dd>${esc(depuis(c.derniereActivite))}</dd>
            <dt>Mise en service</dt><dd>${faites} / ${K.ETAPES_MES.length} étapes</dd>
          </dl><div class="actions" style="margin-bottom:0"><a class="btn sm" href="../#/miseenservice/${c.id}">Mise en service</a><a class="btn sm ghost" href="../#/plateforme">Console de l’appli</a></div></div>
        </div>
      </div>`;
  };

  V.abonnements = () => {
    const t = today();
    const lignes = clients.filter(c => !c.demo).map(c => {
      const a = c.abonnement || {}, reste = a.fin ? Math.round((Date.parse(a.fin) - Date.parse(t)) / 864e5) : null;
      return `<tr><td><a href="#/client/${c.id}"><b>${esc(c.nom)}</b></a></td><td>${etatBadge(c)}</td><td>${esc(a.packNom || a.pack || '—')}</td><td>${fmtD(a.debut)}</td>
        <td>${a.fin ? `${fmtD(a.fin)}<br><span class="small ${reste < 0 ? 'warn' : 'muted'}" style="padding:0;background:none">${reste < 0 ? `dépassée de ${-reste} j` : `dans ${reste} j`}</span>` : '<span class="muted">sans fin</span>'}</td>
        <td class="num">${a.prix == null ? '<span class="muted">—</span>' : `${mad(a.prix)} / ${a.periodicite === 'annuel' ? 'an' : 'mois'}`}${Number(a.remisePct) ? `<br><span class="small muted">−${a.remisePct} %</span>` : ''}</td><td class="num">${mad(K.mensuel(a))}</td>
        <td style="white-space:nowrap"><button class="btn sm" data-abo="${c.id}">Modifier</button> <button class="btn sm ghost" data-prolonger="${c.id}" data-duree="mensuel">+1 mois</button> <button class="btn sm ghost" data-prolonger="${c.id}" data-duree="annuel">+1 an</button></td></tr>`;
    }).join('');
    return `<h1>Abonnements</h1>
      <table class="cc-table"><thead><tr><th>Client</th><th>État</th><th>Pack</th><th>Début</th><th>Fin</th><th class="num">Prix convenu HT</th><th class="num">Revenu mensuel</th><th></th></tr></thead>
      <tbody>${lignes || '<tr><td colspan="8" class="muted">Aucun client (hors démonstrations).</td></tr>'}</tbody></table>
      <p class="small muted">À la date de fin dépassée, le client passe automatiquement en lecture seule (ses données restent consultables et exportables). « +1 mois / +1 an » prolonge depuis la fin (ou depuis aujourd’hui si elle est dépassée) et passe l’abonnement en actif.</p>
      <h2>Grille tarifaire (prix publics HT)</h2>
      <table class="cc-table"><thead><tr><th>Pack</th><th>Modules</th><th>Limites</th><th class="num">Prix mensuel</th><th class="num">Prix annuel</th><th>Note</th><th></th></tr></thead>
      <tbody>${tarifs.map(p => `<tr><td><b>${esc(p.packNom)}</b></td><td class="small">${esc((p.modules || []).join(', '))}</td>
        <td class="small">${p.maxSites == null ? 'sites illimités' : p.maxSites + ' site(s)'} · ${p.maxUtilisateursTotal == null ? 'utilisateurs illimités' : p.maxUtilisateursTotal + ' utilisateurs'}</td>
        <td class="num">${mad(p.prixMensuel)}</td><td class="num">${mad(p.prixAnnuel)}</td><td class="small">${esc(p.note || '')}</td><td><button class="btn sm" data-tarif="${esc(p.pack)}">Modifier</button></td></tr>`).join('')}</tbody></table>
      <p class="small muted">La grille sert de proposition par défaut ; le prix réellement facturé est le prix convenu de chaque abonnement.</p>`;
  };

  // ---------- actions ----------
  async function modifierAbonnement(id) {
    const c = client(id), a = c.abonnement || {}, d = a.derogations || {}, t = tarifDe(a.pack);
    const v = await formulaire({ titre: `Abonnement — ${c.nom}`, valeurs: { pack: a.pack, statut: a.statutAbonnement, debut: a.debut, fin: a.fin, prix: a.prix, periodicite: a.periodicite || 'mensuel', remisePct: Number(a.remisePct) || 0, conditions: a.conditions, ...d },
      info: t.prixMensuel != null || t.prixAnnuel != null ? `Grille ${esc(a.packNom || a.pack)} : ${mad(t.prixMensuel)} / mois · ${mad(t.prixAnnuel)} / an.` : 'Grille tarifaire non renseignée (onglet Abonnements).',
      champs: [
        { nom: 'pack', label: 'Pack', type: 'select', options: PACKS, requis: true }, { nom: 'statut', label: 'Statut', type: 'select', options: STATUTS, requis: true },
        { nom: 'debut', label: 'Début', type: 'date' }, { nom: 'fin', label: 'Fin (payé jusqu’au)', type: 'date' },
        { nom: 'prix', label: 'Prix convenu HT (MAD)', type: 'number', aide: 'vide = non fixé' }, { nom: 'periodicite', label: 'Par', type: 'select', options: { mensuel: 'mois', annuel: 'an' }, requis: true },
        { nom: 'remisePct', label: 'Remise (%)', type: 'number' }, { nom: 'maxSites', label: 'Dérogation : sites max', type: 'number', aide: 'vide = limite du pack' },
        { nom: 'maxUtilisateursSite', label: 'Dérogation : utilisateurs par site', type: 'number' }, { nom: 'maxUtilisateursTotal', label: 'Dérogation : utilisateurs au total', type: 'number' },
        { nom: 'conditions', label: 'Conditions (notes contractuelles)', type: 'textarea', plein: true }] });
    if (!v) return;
    try {
      await Sync.pf.abonnement(id, { pack: v.pack, statut: v.statut, fin: v.fin, maxSites: v.maxSites, maxUtilisateursSite: v.maxUtilisateursSite, maxUtilisateursTotal: v.maxUtilisateursTotal });
      await Sync.pf.conditions(id, v);
      toast('Abonnement enregistré');
    } catch (e) { erreur(e); }
    await afficher(true);
  }
  async function prolonger(id, duree) {
    const c = client(id), a = c.abonnement || {}, d = a.derogations || {}, fin = K.prolonger(a.fin, today(), duree);
    if (!(await confirmer('Prolonger l’abonnement', `${c.nom} : actif jusqu’au ${fmtD(fin)} (au lieu de ${a.fin ? fmtD(a.fin) : 'sans fin'}). À faire après réception du paiement.`, 'Prolonger'))) return;
    try { await Sync.pf.abonnement(id, { pack: a.pack, statut: 'actif', fin, ...d }); toast(`Actif jusqu’au ${fmtD(fin)}`); } catch (e) { erreur(e); }
    await afficher(true);
  }
  async function modifierTarif(pack) {
    const t = tarifDe(pack);
    const v = await formulaire({ titre: `Grille — ${t.packNom}`, valeurs: { prixMensuel: t.prixMensuel, prixAnnuel: t.prixAnnuel, note: t.note },
      champs: [{ nom: 'prixMensuel', label: 'Prix mensuel HT (MAD)', type: 'number' }, { nom: 'prixAnnuel', label: 'Prix annuel HT (MAD)', type: 'number' }, { nom: 'note', label: 'Note (unité, conditions)', type: 'text', plein: true, aide: 'ex. par site et par mois' }] });
    if (!v) return;
    try { await Sync.pf.tarifMaj(pack, v); toast('Grille enregistrée'); } catch (e) { erreur(e); }
    await afficher(true);
  }
  async function nouveauClient() {
    const v = await formulaire({ titre: 'Nouveau client', ok: 'Créer', valeurs: { pack: 'essentiel', statut: 'essai', siteCode: 'S1' }, champs: [
      { nom: 'nom', label: 'Nom de l’entreprise', requis: true }, { nom: 'code', label: 'Code (majuscules, ex. ACME)', requis: true },
      { nom: 'pack', label: 'Pack', type: 'select', options: PACKS, requis: true }, { nom: 'statut', label: 'Statut', type: 'select', options: { essai: 'Essai', actif: 'Actif' }, requis: true },
      { nom: 'siteNom', label: 'Premier site', requis: true, aide: 'ex. Usine de Tanger' }, { nom: 'siteCode', label: 'Code du site', requis: true },
      { nom: 'demo', label: 'Entreprise de démonstration (réinitialisable)', type: 'checkbox', plein: true }] });
    if (!v) return;
    try { const r = await Sync.pf.creer(v); toast('Client créé'); await afficher(true); location.hash = '#/client/' + r.entrepriseId; } catch (e) { erreur(e); }
  }
  async function enregistrerFiche(id, form) {
    const g = n => form.elements[n].value.trim() || null;
    const contacts = [...form.querySelectorAll('#cc-contacts tbody tr')].map(tr => ({
      nom: tr.querySelector('[name=c_nom]').value.trim(), fonction: tr.querySelector('[name=c_fonction]').value.trim() || null,
      telephone: tr.querySelector('[name=c_telephone]').value.trim() || null, email: tr.querySelector('[name=c_email]').value.trim() || null })).filter(p => p.nom);
    const data = { raisonSociale: g('raisonSociale'), ice: g('ice'), rc: g('rc'), identifiantFiscal: g('identifiantFiscal'), adresse: g('adresse'), ville: g('ville'),
      secteur: g('secteur'), siteWeb: g('siteWeb'), notes: g('notes'), contacts };
    if (!K.iceValide(data.ice)) { toast('ICE : 15 chiffres'); return; }
    try { await Sync.pf.clientMaj(id, data); toast('Fiche enregistrée'); } catch (e) { erreur(e); }
    await afficher(true);
  }

  // ---------- routeur ----------
  function route() {
    const h = location.hash.replace(/^#\/?/, '') || 'tableau';
    const [chemin, qs] = h.split('?');
    const [nom, id] = chemin.split('/');
    return { nom: V[nom] ? nom : 'tableau', id: id ? decodeURIComponent(id) : null, q: new URLSearchParams(qs || '') };
  }
  async function afficher(recharger = false) {
    const r = route(), vue = $('#cc-vue');
    try { if (recharger || !clients.length) await charger(); }
    catch (e) { vue.innerHTML = `<p class="warn">Données indisponibles : ${esc(e.message)}</p>`; return; }
    vue.innerHTML = V[r.nom](r);
    lier(r);
  }
  function lier(r) {
    const vue = $('#cc-vue');
    const onglet = r.nom === 'client' ? 'clients' : r.nom;
    document.querySelectorAll('.cc-onglets a').forEach(a => a.classList.toggle('on', a.dataset.onglet === onglet));
    vue.querySelectorAll('[data-abo]').forEach(b => b.onclick = () => modifierAbonnement(b.dataset.abo));
    vue.querySelectorAll('[data-prolonger]').forEach(b => b.onclick = () => prolonger(b.dataset.prolonger, b.dataset.duree));
    vue.querySelectorAll('[data-tarif]').forEach(b => b.onclick = () => modifierTarif(b.dataset.tarif));
    vue.querySelectorAll('tr.lien').forEach(tr => tr.onclick = () => { location.hash = '#/client/' + tr.dataset.id; });
    const nouv = $('#cc-nouveau'); if (nouv) nouv.onclick = nouveauClient;
    const q = $('#cc-q');
    if (q) q.oninput = () => {
      history.replaceState(null, '', '#/clients' + (q.value ? '?q=' + encodeURIComponent(q.value) : ''));
      const pos = q.selectionStart, r2 = route();
      vue.innerHTML = V.clients(r2); lier(r2);
      const q2 = $('#cc-q'); q2.focus(); q2.setSelectionRange(pos, pos);
    };
    const fiche = $('#cc-fiche');
    if (fiche) {
      fiche.onsubmit = ev => { ev.preventDefault(); enregistrerFiche(r.id, fiche); };
      fiche.querySelectorAll('[data-retirer]').forEach(b => b.onclick = () => b.closest('tr').remove());
    }
  }

  async function demarrer() {
    const vue = $('#cc-vue');
    try { await Store.open(); } catch (e) { vue.innerHTML = `<p class="warn">Stockage indisponible : ${esc(e.message)}</p>`; return; }
    if (!Sync.etatCourant().connecte) { vue.innerHTML = `<div class="card"><p style="margin-top:0"><b>Connectez-vous d’abord dans l’appli</b> avec le compte administrateur de la plateforme, puis revenez ici.</p><a class="btn primary" href="../#/reglages">Ouvrir l’appli</a></div>`; return; }
    try { await Sync.chargerProfil(); } catch { /* profil en mémoire */ }
    const p = Sync.profil();
    if (!p?.adminPlateforme) { vue.innerHTML = '<p class="warn">Réservé à l’administrateur de la plateforme.</p>'; return; }
    $('#cc-moi').textContent = p.nom || p.email;
    window.addEventListener('hashchange', () => afficher());
    afficher(true);
  }
  demarrer();
})();
