/* GMAO terrain — écran Énergie et eau (volet D, étape D4 ; V3 §20, §21).
   Consommations par période avec couverture (totaux par ressource et unité, sur les compteurs principaux seulement),
   relevés et écarts à examiner, factures d'énergie (PDF joint, montants en lecture restreinte) et rapprochement
   facturé / mesuré sur les dates exactes de la facture ; « créer une demande » depuis un écart.
   Chiffres honnêtes : jamais d'addition entre unités, jamais de valeur inventée, un écart n'est pas une preuve.
   Script classique chargé après compteurs.js. */
(() => {
  const { V, A, AFTER, esc, badge, empty, seg, alertBox, toast, list, render, fmt, fmtY, today, aModule, autorise, role, ajouterFichier, eq } = App;
  const { data } = Store;
  const CPT = App.compteurs;
  const { RESSOURCE, ANOM } = CPT;

  const voitEnergie = () => aModule('energie') && (!role() || ['responsable', 'pilote', 'achats'].includes(role()));
  const voitFactures = () => voitEnergie() && !!App.voitCouts?.();
  const peutFacturer = () => autorise('fact-saisir');
  const nf = n => (n == null || n === '' ? '—' : Number(n).toLocaleString('fr-FR', { maximumFractionDigits: 2 }));
  const qte = (n, u) => (n == null ? '<span class="muted">non mesuré</span>' : `<b>${nf(n)}</b> ${esc(u || '')}`);
  const nomMois = ym => new Date(ym + '-15T12:00').toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' });
  const tousReleves = () => [...data.releves.values()];
  const compteursEnergie = () => list('compteurs').filter(c => c.usage !== 'equipement');
  const factures = () => list('factures_energie').sort((a, b) => (b.au || '').localeCompare(a.au || '') || (b.creeLe || '').localeCompare(a.creeLe || ''));
  const piecesDe = f => [...data.photos.values()].filter(p => p.parentType === 'factures_energie' && p.parentId === f.id);
  const rapprocher = f => Calculs.rapprochementFacture(f, list('compteurs'), tousReleves(), { maintenant: Store.now() });

  /** Période affichée : un mois ; le mois en cours s'arrête à aujourd'hui (rien n'est compté dans le futur). */
  function periode(r) {
    const cur = today().slice(0, 7), ym = /^\d{4}-\d{2}$/.test(r.q.get('m') || '') ? r.q.get('m') : cur;
    const b = Calculs.bornesMois(ym);
    return { ym, cur, du: b.du, au: ym === cur ? today().slice(0, 10) : b.au, enCours: ym === cur };
  }

  const STATUT_RAPP = { concordant: ['concordant', 'green'], ecart: ['écart', 'red'], incomplet: ['rapprochement incomplet', 'amber'], unites_differentes: ['unités différentes', 'amber'] };
  const MANQUE = { unite: 'unité du compteur différente de celle de la facture', debut: 'aucun relevé retenu à ±1 jour du début de la facture',
    fin: 'aucun relevé retenu à ±1 jour de la fin de la facture', continuite: 'relevés manquants ou à examiner au milieu de la période' };
  const RESIDU = { faible: ['résidu faible', 'green'], a_expliquer: ['à expliquer', 'amber'], incoherent: ['incohérent : sous-compteurs > principal', 'red'],
    non_comparable: ['non comparable', ''] };
  const badgeRapp = x => { const [l, k] = STATUT_RAPP[x.statut] || [x.statut, '']; return badge(x.statut === 'ecart' && x.ecartPct != null ? `écart ${x.ecartPct > 0 ? '+' : ''}${nf(x.ecartPct)} %` : l, k); };

  // ---------- éléments « à examiner » (aussi pour l'accueil) ----------
  function relevesAExaminer() {
    const out = [];
    for (const c of CPT.visibles()) {
      const a = Calculs.analyserReleves(c, CPT.relevesDe(c.id), { maintenant: Store.now() });
      for (const l of a.lignes) if (l.statut === 'suspect') out.push({ compteur: c, ligne: l });
    }
    return out.sort((x, y) => (y.ligne.releve.le || '').localeCompare(x.ligne.releve.le || ''));
  }
  const facturesEnEcart = () => (voitFactures() ? factures().map(f => ({ f, x: rapprocher(f) })).filter(o => o.x.statut === 'ecart') : []);
  App.energie = { voitEnergie, aExaminer: () => (voitEnergie() ? relevesAExaminer().length + facturesEnEcart().length : 0) };

  // ---------- page ----------
  const ONGLETS = [['conso', 'Consommations'], ['examiner', 'À examiner'], ['factures', 'Factures']];
  V.energie = r => {
    if (!aModule('energie')) return empty('Module « énergie » non inclus dans votre abonnement.');
    if (!voitEnergie()) return empty('Énergie et eau : réservé au responsable, au pilote et aux achats. Les relevés se font depuis « Compteurs ».');
    const onglet = ONGLETS.some(([k]) => k === r.q.get('o')) ? r.q.get('o') : 'conso';
    const p = periode(r);
    const lien = (o, m = p.ym) => `#/energie?o=${o}&m=${m}`;
    const onglets = ONGLETS.filter(([k]) => k !== 'factures' || voitFactures()).map(([k, l]) => [lien(k), l, k]);
    const navMois = `<div class="row" style="margin:6px 0 12px"><a class="btn sm ghost" href="${lien(onglet, Calculs.moisDecale(p.ym, -1))}" aria-label="Mois précédent">‹</a>
      <b class="grow" style="text-align:center;text-transform:capitalize">${esc(nomMois(p.ym))}${p.enCours ? ' <span class="small muted" style="text-transform:none">(jusqu’à aujourd’hui)</span>' : ''}</b>
      ${p.ym < p.cur ? `<a class="btn sm ghost" href="${lien(onglet, Calculs.moisDecale(p.ym, 1))}" aria-label="Mois suivant">›</a>` : '<span class="btn sm ghost" style="visibility:hidden">›</span>'}</div>`;
    const corps = onglet === 'examiner' ? ongletExaminer(p) : onglet === 'factures' && voitFactures() ? ongletFactures(p) : ongletConso(p);
    return `<h1>Énergie et eau</h1>${seg(onglets, onglet)}${onglet === 'factures' ? '' : navMois}${corps}`;
  };

  function ongletConso(p) {
    const cs = compteursEnergie();
    if (!cs.length) return `${empty('Aucun compteur d’énergie ou d’eau.')}<div class="actions"><a class="btn" href="#/compteurs">Compteurs</a></div>`;
    const t = Calculs.tableauEnergie(cs, tousReleves(), p.du, p.au, { maintenant: Store.now() });
    const tuiles = t.totaux.map(x => `<div class="tile"><b>${x.quantite == null ? '—' : nf(x.quantite)}</b><span>${esc(x.unite)} · ${esc(RESSOURCE[x.ressource] || x.ressource)}${x.nonMesures ? `<br><span class="small">${x.nonMesures} compteur(s) non mesuré(s)</span>` : ''}</span></div>`).join('');
    const ligne = l => {
      const c = l.compteur, k = l.conso;
      const valeur = k.mode === 'instantane'
        ? (k.nb ? `dernière <b>${nf(k.derniere)}</b> ${esc(c.unite)} · min ${nf(k.min)} · max ${nf(k.max)}` : '<span class="muted">aucune mesure</span>')
        : qte(k.quantite, c.unite);
      const couv = k.mode === 'instantane' ? '' : badge(`${nf(k.couvertureJours)} j sur ${nf(k.periodeJours)}`, k.complet ? 'green' : k.couvertureJours ? 'amber' : '');
      return `<li style="padding-left:${l.niveau * 18}px;flex-wrap:wrap"><a class="grow" href="#/compteur/${c.id}">${l.niveau ? '↳ ' : ''}<b>${esc(CPT.nomCompteur(c))}</b>
        <br><span class="small muted">${esc(c.code)} · ${esc(RESSOURCE[c.ressource] || 'autre')}${l.niveau ? ' · sous-compteur (non ajouté au total)' : ''}</span></a>
        <span style="text-align:right">${valeur}<br>${couv}${k.estime ? ' ' + badge('estimé', 'blue') : ''}${k.suspects ? ' ' + badge(`${k.suspects} à examiner`, 'amber') : ''}</span></li>`;
    };
    const sc = t.sousComptages.map(s => {
      const [l, k] = RESIDU[s.statut] || [s.statut, ''];
      const somme = s.sous.reduce((x, y) => x + (y.conso?.quantite || 0), 0);
      const pourquoi = s.statut === 'non_comparable' ? (s.horsUnite.length ? 'un sous-compteur n’a pas la même unité' : 'relevés manquants ou couvertures différentes : comparaison impossible sans inventer') : '';
      return `<div class="card"><div class="row"><span class="t grow">${esc(CPT.nomCompteur(s.compteur))}</span>${badge(l, k)}</div>
        <div class="s">Principal ${qte(s.principal.quantite, s.compteur.unite)} · sous-compteurs ${s.statut === 'non_comparable' ? '—' : `<b>${nf(somme)}</b> ${esc(s.compteur.unite)}`}
          ${s.residu != null ? ` · résidu <b>${nf(s.residu)} ${esc(s.compteur.unite)}</b> (${nf(s.residuPct)} %)` : ''}</div>
        ${pourquoi ? `<div class="small muted">${esc(pourquoi)}</div>` : ''}
        ${['a_expliquer', 'incoherent'].includes(s.statut) ? boutonDemande(s.compteur, `Résidu de sous-comptage ${nf(s.residu)} ${s.compteur.unite} (${nf(s.residuPct)} %) sur ${CPT.nomCompteur(s.compteur)}, ${nomMois(p.ym)} : à expliquer (fuite, usage non compté, compteur à vérifier).`) : ''}</div>`;
    }).join('');
    return `<div class="tiles">${tuiles || '<p class="muted">Aucune consommation mesurée sur la période.</p>'}</div>
      <p class="small muted">Totaux par ressource et par unité, sur les compteurs principaux seulement. Seule la partie couverte par des relevés retenus est comptée (« 27 j sur 30 ») : aucune valeur n’est inventée pour les jours manquants.</p>
      <h2>Par compteur</h2><div class="card"><ul class="lines">${t.lignes.map(ligne).join('')}</ul></div>
      ${sc ? `<h2>Sous-comptages</h2>${sc}<p class="small muted">Résidu = principal − somme des sous-compteurs, sur la même période. Un résidu est « à expliquer » : ce n’est pas une fuite prouvée.</p>` : ''}
      ${t.suspects ? `<p class="warn">${t.suspects} relevé(s) à examiner sur la période : ils sont exclus des calculs. <a href="#/energie?o=examiner&m=${p.ym}">Les examiner</a></p>` : ''}`;
  }

  function boutonDemande(c, texte) {
    if (!autorise('signaler')) return '';
    return `<div class="actions" style="margin-bottom:0"><button class="btn sm" data-act="energie-demande" data-cpt="${c.id}" data-texte="${esc(texte)}">Créer une demande</button></div>`;
  }

  function ongletExaminer(p) {
    const rel = relevesAExaminer();
    const ecarts = facturesEnEcart();
    const cs = compteursEnergie();
    const t = cs.length ? Calculs.tableauEnergie(cs, tousReleves(), p.du, p.au, { maintenant: Store.now() }) : { sousComptages: [] };
    const residus = t.sousComptages.filter(s => ['a_expliquer', 'incoherent'].includes(s.statut));
    const dus = CPT.dus().filter(x => x.retardJours > 0 && x.compteur.usage !== 'equipement');
    const carteRel = ({ compteur: c, ligne: l }) => {
      const x = l.releve;
      return `<div class="card"><div class="row"><a class="t grow" href="#/compteur/${c.id}">${esc(CPT.nomCompteur(c))}</a>${badge('à examiner', 'amber')}</div>
        <div class="s"><b>${nf(x.valeur)} ${esc(c.unite)}</b>${x.estime ? ' (estimé)' : ''} · ${fmtY(x.le)} · ${esc(x.creePar || '')}</div>
        <div class="small" style="color:var(--amber)">${l.anomalies.map(k => esc(ANOM[k] || k)).join(' ; ')}</div>
        ${autorise('releve-qualifier') ? `<div class="actions" style="margin-bottom:0">${l.confirmable ? `<button class="btn sm" data-act="releve-qualifier" data-id="${x.id}" data-decision="confirme">Confirmer</button>` : ''}<button class="btn sm ghost danger" data-act="releve-qualifier" data-id="${x.id}" data-decision="invalide">Invalider</button>
          ${!l.confirmable ? `<a class="btn sm ghost" href="#/compteur/${c.id}">Corriger ou déclarer un remplacement</a>` : ''}</div>` : ''}</div>`;
    };
    const carteEcart = ({ f, x }) => {
      const c = data.compteurs.get((f.compteurIds || [])[0]);
      return `<div class="card"><div class="row"><a class="t grow" href="#/facture/${f.id}">${esc(RESSOURCE[f.ressource] || '')} · ${esc(f.fournisseur || '')} ${esc(f.reference || '')}</a>${badgeRapp(x)}</div>
        <div class="s">Du ${fmt(f.du)} au ${fmt(f.au)} · facturé <b>${nf(x.facture)} ${esc(f.unite)}</b> · mesuré <b>${nf(x.mesure)} ${esc(f.unite)}</b> · écart ${nf(x.ecart)} ${esc(f.unite)}</div>
        ${c ? boutonDemande(c, `Écart facture / mesure ${f.fournisseur || ''} ${f.reference || ''} du ${f.du} au ${f.au} : facturé ${nf(x.facture)} ${f.unite}, mesuré ${nf(x.mesure)} ${f.unite} (${nf(x.ecartPct)} %). Vérifier le compteur et la facture.`) : ''}</div>`;
    };
    const vide = !rel.length && !ecarts.length && !residus.length && !dus.length;
    return `${vide ? empty('Rien à examiner.') : ''}
      ${rel.length ? `<h2>Relevés à examiner (${rel.length})</h2><p class="small muted">Gardés mais exclus des calculs jusqu’à votre décision. Seule une consommation inhabituelle peut être confirmée ; les autres anomalies se corrigent (nouveau relevé ou remplacement déclaré).</p>${rel.map(carteRel).join('')}` : ''}
      ${ecarts.length ? `<h2>Écarts facture / mesure (${ecarts.length})</h2>${ecarts.map(carteEcart).join('')}` : ''}
      ${residus.length ? `<h2>Sous-comptages à expliquer · ${esc(nomMois(p.ym))}</h2>${residus.map(s => `<div class="card"><div class="row"><a class="t grow" href="#/compteur/${s.compteur.id}">${esc(CPT.nomCompteur(s.compteur))}</a>${badge(...RESIDU[s.statut])}</div>
        <div class="s">Résidu <b>${nf(s.residu)} ${esc(s.compteur.unite)}</b> (${nf(s.residuPct)} % du principal)</div>
        ${boutonDemande(s.compteur, `Résidu de sous-comptage ${nf(s.residu)} ${s.compteur.unite} (${nf(s.residuPct)} %) sur ${CPT.nomCompteur(s.compteur)}, ${nomMois(p.ym)} : à expliquer (fuite, usage non compté, compteur à vérifier).`)}</div>`).join('')}` : ''}
      ${dus.length ? `<h2>Relevés en retard (${dus.length})</h2><div class="card"><ul class="lines">${dus.map(x => `<li><a class="grow" href="#/compteur/${x.compteur.id}">${esc(CPT.nomCompteur(x.compteur))}</a>${badge(`en retard de ${x.retardJours} j`, 'red')}</li>`).join('')}</ul>
        <p class="small muted" style="margin-bottom:0">Sans relevé, la consommation de ces compteurs n’est pas couverte : les totaux restent partiels.</p></div>` : ''}`;
  }

  function carteFacture(f) {
    const x = rapprocher(f), pj = piecesDe(f).length;
    return `<a class="card" href="#/facture/${f.id}"><div class="row"><span class="t grow">${esc(RESSOURCE[f.ressource] || 'Énergie')} · ${esc(f.fournisseur || 'fournisseur ?')}${f.reference ? ' · ' + esc(f.reference) : ''}</span>${badgeRapp(x)}</div>
      <div class="s">Du ${fmt(f.du)} au ${fmt(f.au)} · ${f.quantite != null ? `${nf(f.quantite)} ${esc(f.unite)}` : 'quantité non saisie'} · ${f.montantHT != null ? `<b>${nf(f.montantHT)} ${esc(f.devise || 'MAD')} HT</b>` : 'montant non saisi'}${pj ? ' · 📄' : ''}</div></a>`;
  }

  function ongletFactures(p) {
    const l = factures(), an = p.cur.slice(0, 4);
    const tot = Calculs.totalFactures(l.filter(f => (f.au || '').startsWith(an)));
    const totaux = Object.entries(tot.parDevise).map(([d, m]) => `<b>${nf(m)} ${esc(d)} HT</b>`).join(' · ');
    return `${l.length ? `<p class="small">Factures se terminant en ${an} : ${totaux || '—'}${tot.sansMontant ? ` <span class="muted">(${tot.sansMontant} sans montant, non comptée(s))</span>` : ''}</p>` : ''}
      <div class="actions">${peutFacturer() ? '<a class="btn primary" href="#/facture-saisie">+ Facture</a>' : ''}</div>
      ${l.length ? l.map(carteFacture).join('') : empty('Aucune facture d’énergie.')}
      <p class="small muted">Le rapprochement compare la quantité facturée à la consommation mesurée sur les dates exactes de la facture (du 15 au 15 n’est pas un mois civil). Sans relevé à ±1 jour des deux dates, il reste « incomplet » : ce n’est jamais un écart certain.</p>`;
  }

  // ---------- fiche facture ----------
  V.facture = r => {
    const f = data.factures_energie.get(r.id);
    if (!voitFactures()) return empty('Factures : réservées au responsable, au magasin, aux achats et au pilote.');
    if (!f) return empty('Facture introuvable.');
    const x = rapprocher(f), pj = piecesDe(f);
    const cs = (f.compteurIds || []).map(id => data.compteurs.get(id)).filter(Boolean);
    const det = x.details.map(d => {
      const c = data.compteurs.get(d.compteurId);
      return `<li style="flex-wrap:wrap"><a class="grow" href="#/compteur/${d.compteurId}"><b>${esc(c ? CPT.nomCompteur(c) : d.compteurId)}</b><br><span class="small muted">${d.debut && d.fin ? `mesuré du ${fmtY(d.debut)} au ${fmtY(d.fin)}` : ''}${d.manque ? `${d.debut && d.fin ? ' · ' : ''}${esc(MANQUE[d.manque] || d.manque)}` : ''}</span></a>
        <span>${d.mesure == null ? '<span class="muted">—</span>' : `<b>${nf(d.mesure)}</b> ${esc(c?.unite || '')}`}${d.estime ? ' ' + badge('estimé', 'blue') : ''}</span></li>`;
    }).join('');
    const c0 = cs[0];
    return `<p class="small" style="margin:0 0 6px"><a href="#/energie?o=factures">← Factures</a></p>
      <div class="row"><h1 class="grow">${esc(f.fournisseur || 'Facture')}${f.reference ? ' · ' + esc(f.reference) : ''}</h1>${badgeRapp(x)}</div>
      <div class="card"><dl class="kv">
        <dt>Ressource</dt><dd>${esc(RESSOURCE[f.ressource] || '—')}</dd>
        <dt>Période</dt><dd>du ${fmtY(f.du)} au ${fmtY(f.au)} (${Calculs.daysBetween(f.du, f.au)} j)</dd>
        <dt>Quantité facturée</dt><dd>${f.quantite != null ? `${nf(f.quantite)} ${esc(f.unite)}` : '—'}</dd>
        <dt>Montant HT</dt><dd>${f.montantHT != null ? `${nf(f.montantHT)} ${esc(f.devise || 'MAD')}` : '<span class="muted">non saisi</span>'}</dd>
        ${f.montantTTC != null ? `<dt>Montant TTC</dt><dd>${nf(f.montantTTC)} ${esc(f.devise || 'MAD')}</dd>` : ''}
        ${f.note ? `<dt>Note</dt><dd>${esc(f.note)}</dd>` : ''}
        <dt>Saisie</dt><dd>${fmtY(f.creeLe)} par ${esc(f.creePar || '')}</dd></dl></div>
      <h2>Rapprochement facturé / mesuré</h2>
      <div class="card">${cs.length ? `<p style="margin-top:0">Facturé ${f.quantite != null ? `<b>${nf(f.quantite)} ${esc(f.unite)}</b>` : '—'} · mesuré ${x.mesure != null ? `<b>${nf(x.mesure)} ${esc(f.unite)}</b>` : '—'}${x.ecart != null ? ` · écart <b>${nf(x.ecart)} ${esc(f.unite)}</b> (${nf(x.ecartPct)} %)` : ''}</p>
        <ul class="lines">${det}</ul>
        <p class="small muted" style="margin-bottom:0">${x.statut === 'concordant' ? 'Écart dans la tolérance (±2 %).' : x.statut === 'ecart' ? 'Écart = facturé − mesuré. À vérifier (relevé, compteur, facture) : ce n’est pas une preuve d’erreur ou de fuite.' : x.statut === 'unites_differentes' ? 'Un compteur n’a pas la même unité que la facture : aucune conversion n’est faite.' : 'Rapprochement incomplet : relevez les compteurs aux dates de la facture (±1 jour), ou saisissez la quantité facturée.'}</p>
        ${x.statut === 'ecart' && c0 ? boutonDemande(c0, `Écart facture / mesure ${f.fournisseur || ''} ${f.reference || ''} du ${f.du} au ${f.au} : facturé ${nf(x.facture)} ${f.unite}, mesuré ${nf(x.mesure)} ${f.unite} (${nf(x.ecartPct)} %). Vérifier le compteur et la facture.`) : ''}`
        : '<p class="muted" style="margin:0">Aucun compteur rattaché : indiquez les compteurs concernés pour comparer.</p>'}</div>
      <h2>Facture (PDF ou photo)</h2>
      <div class="card">${pj.length ? `<ul class="lines">${pj.map(ph => `<li><span class="grow">📄 ${esc(ph.nom || 'document')}<br><span class="small muted">${fmtY(ph.le)} · ${Math.max(1, Math.round((ph.taille || 0) / 1024))} Ko</span></span><button class="btn sm" data-act="photo-voir" data-id="${ph.id}">Ouvrir</button></li>`).join('')}</ul>` : '<p class="muted" style="margin-top:0">Aucun fichier joint.</p>'}
        ${peutFacturer() ? `<button class="btn sm" data-act="photo-ajout" data-type="factures_energie" data-id="${f.id}">Joindre un fichier</button>` : ''}</div>
      ${peutFacturer() ? `<div class="actions"><a class="btn ghost" href="#/facture-saisie?id=${f.id}">Modifier</a></div>` : ''}`;
  };

  // ---------- saisie / modification d'une facture (page : le PDF se joint dans le même geste) ----------
  const DEVISES = ['MAD', 'EUR', 'USD'];
  function champsFacture() {
    const cs = compteursEnergie();
    return [
      { name: 'ressource', label: 'Ressource', type: 'select', required: true, options: Object.entries(RESSOURCE), empty: '— Choisir —' },
      { name: 'fournisseur', label: 'Fournisseur', type: 'text', required: true, placeholder: 'ex. ONEE, Lydec, Amendis, Redal, distributeur de gasoil' },
      { name: 'reference', label: 'Numéro de facture', type: 'text' },
      { name: 'du', label: 'Période facturée : du', type: 'date', required: true },
      { name: 'au', label: 'au', type: 'date', required: true },
      { name: 'quantite', label: 'Quantité facturée (sert au rapprochement)', type: 'number' },
      { name: 'unite', label: 'Unité', type: 'select', required: true, options: Calculs.UNITES.map(u => [u, u]), empty: '— Choisir —' },
      { name: 'montantHT', label: 'Montant HT (vide = inconnu, jamais 0)', type: 'number' },
      { name: 'montantTTC', label: 'Montant TTC', type: 'number' },
      { name: 'devise', label: 'Devise', type: 'select', options: DEVISES.map(d => [d, d]) },
      ...(cs.length ? [{ name: 'compteurIds', label: 'Compteurs concernés (facturés par cette facture)', type: 'chipsMulti', options: Object.fromEntries(cs.map(c => [c.id, `${CPT.nomCompteur(c)} (${c.unite})`])) }] : []),
      { name: 'note', label: 'Note', type: 'textarea' }];
  }
  function lireChamps(form, fields) {
    const v = {};
    for (const f of fields) {
      if (f.type === 'info') continue;
      const el = form.elements[f.name];
      if (f.type === 'chipsMulti') v[f.name] = [...form.querySelectorAll(`input[name="${f.name}"]:checked`)].map(i => i.value);
      else if (f.type === 'number') v[f.name] = el.value === '' ? null : Number(el.value);
      else v[f.name] = (el.value || '').trim() || null;
    }
    return v;
  }
  V['facture-saisie'] = r => {
    if (!voitFactures() || !peutFacturer()) return empty('Saisie des factures : réservée au responsable et aux achats.');
    const f = r.q.get('id') ? data.factures_energie.get(r.q.get('id')) : null;
    const valeurs = f || { devise: 'MAD', unite: 'kWh' };
    return `<p class="small" style="margin:0 0 6px"><a href="${f ? `#/facture/${f.id}` : '#/energie?o=factures'}">← ${f ? 'Facture' : 'Factures'}</a></p>
      <h1>${f ? 'Modifier la facture' : 'Nouvelle facture d’énergie'}</h1>
      <form id="fac" class="card" novalidate>${champsFacture().map(x => App.fieldHtml(x, valeurs[x.name])).join('')}
        ${f ? '' : `<label class="f" for="fac-pj">Facture (PDF ou photo) <span class="opt">(facultatif, 5 Mo max.)</span></label><input id="fac-pj" type="file" accept="application/pdf,image/*">`}
        <p class="small muted">Montants visibles seulement du responsable, du magasin, des achats et du pilote.</p>
        <div class="sticky-save"><button class="btn primary block" type="submit">Enregistrer la facture</button></div></form>`;
  };
  AFTER['facture-saisie'] = r => {
    const form = document.querySelector('#fac');
    if (!form) return;
    const f = r.q.get('id') ? data.factures_energie.get(r.q.get('id')) : null;
    const fields = champsFacture();
    // Unité proposée selon la ressource (électricité → kWh, eau → m³…).
    form.ressource.onchange = () => { const u = Calculs.UNITES_RESSOURCE[form.ressource.value]; if (u && u.length < Calculs.UNITES.length && !u.includes(form.unite.value)) form.unite.value = u[0]; };
    form.onsubmit = async ev => {
      ev.preventDefault();
      if (!form.reportValidity()) return;
      const v = lireChamps(form, fields);
      const err = [];
      if (v.du && v.au && v.au <= v.du) err.push('La fin de la période doit être après son début.');
      if (v.montantHT != null && v.montantHT < 0) err.push('Montant HT négatif (un avoir se saisit à part).');
      for (const id of v.compteurIds || []) { const c = data.compteurs.get(id); if (c && c.unite !== v.unite) err.push(`${CPT.nomCompteur(c)} est en ${c.unite}, la facture en ${v.unite} : aucune conversion n’est faite.`); }
      if (err.length) { await alertBox('Facture', err); return; }
      const fichier = form.querySelector('#fac-pj')?.files[0] || null;
      const obj = { ...v, compteurIds: v.compteurIds || [], devise: v.devise || 'MAD' };
      let id = f?.id;
      if (f) await App.edit('factures_energie', f.id, obj, { render: false });
      else { id = Store.uid(); await Store.save('factures_energie', { id, ...obj }); }
      if (fichier) { try { await ajouterFichier('factures_energie', id, fichier, fichier.name); } catch (e) { toast('Fichier non joint : ' + e.message); } }
      toast('Facture enregistrée');
      location.hash = '#/facture/' + id;
    };
  };

  // ---------- créer une demande depuis un écart (fuite d'air, dérive, compteur à vérifier…) ----------
  A['energie-demande'] = el => {
    const c = data.compteurs.get(el.dataset.cpt);
    const e = c?.equipementId ? eq(c.equipementId) : null;
    const q = new URLSearchParams({ cpt: c?.id || '', constat: el.dataset.texte || '' });
    if (e) q.set('eq', e.code);
    location.hash = '#/signaler?' + q.toString();
  };
})();
