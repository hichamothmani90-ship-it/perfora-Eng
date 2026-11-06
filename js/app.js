/* GMAO terrain — interface. Principe : traçabilité légère.
   Pas de chronomètre : on trace des faits et des dates-jalons.
   « Avec arrêt » = oui / non / inconnu ; début et fin facultatifs ;
   une durée n'est affichée que si les deux bornes existent. */
(() => {
  const { data } = Store;
  /** Version affichée dans Réglages : à incrémenter avec VERSION dans sw.js. */
  const APP_VERSION = 'v20';
  const $ = s => document.querySelector(s);
  // Multi-site : les listes de fiches de site ne montrent que le site actif (« tous » possible).
  // Les fiches sans site (anciennes ou pas encore synchronisées) restent visibles.
  const list = t => { const a = [...data[t].values()]; return Store.SITE_TYPES.includes(t) ? a.filter(dansSite) : a; };
  function dansSite(o) { const s = siteActif(); return !s || s === 'tous' || !o.siteId || o.siteId === s; }
  const mesSites = () => Sync.profil()?.sites || [];
  function siteActif() {
    const p = Sync.profil();
    if (!p) return null;
    const sites = p.sites || [], v = Store.device().siteActif;
    if (v === 'tous' && sites.length > 1) return 'tous';
    if (sites.some(x => x.id === v)) return v;
    return (sites.find(x => x.id === p.siteDefaut) || sites[0])?.id || null;
  }
  /** Site d'une nouvelle fiche : celui de son parent, sinon le site actif (ou le site par défaut si « tous »). */
  function siteCreation() {
    const s = siteActif();
    if (s && s !== 'tous') return s;
    const p = Sync.profil(), sites = p?.sites || [];
    return (sites.find(x => x.id === p?.siteDefaut) || sites[0])?.id || null;
  }
  const nomSite = id => mesSites().find(x => x.id === id)?.nom || '';
  Store.definirSite((t, o) => {
    if (!Sync.profil()) return null;
    const g = (tt, id) => id && data[tt]?.get(id)?.siteId;
    const parent =
      t === 'demandes' || t === 'ots' || t === 'programmes' ? g('equipements', o.equipementId) || g('demandes', (o.demandeIds || [])[0])
      : t === 'equipements' ? g('localisations', o.localisationId)
      : t === 'localisations' ? g('localisations', o.parentId)
      : t === 'photos' ? g(o.parentType, o.parentId)
      : t === 'mouvements' ? g('besoins', o.besoinId) || g('ots', o.otId)
      : t === 'besoins' ? g('ots', o.otId)
      : t === 'valorisations' ? g('mouvements', o.mouvementId)
      : null;
    return parent || siteCreation();
  });
  // Modules du pack et abonnement (sans compte cloud : tout est disponible).
  const aModule = m => { const mods = Sync.profil()?.abonnement?.modules; return !mods || mods.includes(m); };
  const ecritureOK = () => Sync.profil()?.abonnement?.ecriture !== false;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const trunc = (s, n) => { s = s || ''; return s.length > n ? s.slice(0, n - 1) + '…' : s; };

  // ---------- listes prédéfinies (V3, sections 32-33) ----------
  const L = {
    etat: { normal: 'Normal', anomalie: 'Anomalie', degrade: 'Dégradé', indisponible: 'Indisponible', inconnu: 'À confirmer' },
    besoin: { verifier: 'Vérifier une anomalie', corriger: 'Corriger un défaut', entretien: 'Entretien prévu', serie: 'Changement de série', demarrage: 'Aide au démarrage', derive: 'Dérive en production', travaux: 'Installer / modifier', autre: 'Autre' },
    impact: { aucun_constate: 'Aucun', reduit: 'Réduit', interrompu: 'Interrompu', a_confirmer: 'À confirmer' },
    origine: { observation: 'Constat personnel', tiers: 'Demande reçue' },
    precision: { exacte: 'Exacte', estimee: 'Estimée' },
    statutDem: { a_examiner: 'À examiner', prise_en_charge: 'Prise en charge', traitement_organise: 'Traitement organisé', close_sans_travail: 'Close sans travail', annulee: 'Annulée' },
    nature: { a_qualifier: 'À qualifier', corrective: 'Corrective', preventive: 'Préventive', assistance_production: 'Assistance production', travaux_techniques: 'Travaux techniques' },
    priorite: { urgence_securite: 'Urgence sécurité', critique_service: 'Critique', rapide: 'Rapide', planifiable: 'Planifiable', a_qualifier: 'À qualifier' },
    statutOT: { a_preparer: 'À préparer', a_planifier: 'À planifier', prete: 'Prête', en_cours: 'En cours', suspendue: 'En attente', travail_termine: 'Travail terminé', cloturee: 'Clôturée', annulee: 'Annulée' },
    resultat: { resolu: 'Résolu', retabli_provisoirement: 'Rétabli provisoirement', aucun_defaut_constate: 'Aucun défaut constaté', partiel: 'Partiel', non_resolu: 'Non résolu' },
    certitude: { non_determinee: 'Non déterminée', probable: 'Probable', confirmee: 'Confirmée' },
    famille: { mecanique: 'Mécanique', electrique: 'Électrique', automatisme: 'Automatisme', instrumentation: 'Instrumentation', pneumatique: 'Pneumatique', hydraulique: 'Hydraulique', utilite_externe: 'Utilité externe', autre: 'Autre' },
    activite: { inspection: 'Inspection', mesure: 'Mesure', diagnostic: 'Diagnostic', reglage: 'Réglage', nettoyage_technique: 'Nettoyage', graissage: 'Graissage', depannage: 'Dépannage', reparation: 'Réparation', remplacement: 'Remplacement', montage_demontage: 'Montage / démontage', installation: 'Installation', modification: 'Modification', essai: 'Essai', verification_externe: 'Vérif. externe', autre: 'Autre' },
    attente: { piece: 'Pièce', acces_exploitation: 'Accès / exploitation', autorisation: 'Autorisation', specialiste: 'Spécialiste', outillage_moyen: 'Outillage / moyen', verification_essai: 'Vérification / essai', autre: 'Autre' },
    role: { technicien: 'Technicien', responsable: 'Responsable', magasinier: 'Magasinier', achats: 'Achats', prestataire: 'Prestataire', exploitation: 'Exploitation', pilote: 'Pilote' },
    roleOT: { coordinateur: 'Coordinateur', intervenant: 'Intervenant', renfort: 'Renfort', prestataire: 'Prestataire' },
    arret: { oui: 'Oui', non: 'Non', inconnu: 'Inconnu' },
    modele: { entretien: 'Entretien', inspection: 'Inspection', test: 'Test', verification_externe: 'Vérification externe', autre: 'Autre' },
    regle: { fixe: 'Échéance fixe', apres_realisation: 'Après réalisation' },
    typeSuite: { reserve: 'Réserve', suite: 'Action de suite', provisoire: 'Solution provisoire' },
    mvt: { entree: 'Réception', sortie: 'Sortie', remise: 'Remise', retour: 'Retour', rebut: 'Rebut', ajustement: 'Ajustement inventaire' },
    entite: { demandes: 'Demande', ots: 'Intervention', equipements: 'Équipement', localisations: 'Lieu', personnes: 'Personne', programmes: 'Programme', articles: 'Article', mouvements: 'Mouvement', besoins: 'Besoin de pièce' },
    etatBesoin: { demande: 'Demandée', reserve: 'Réservée', partiellement_remis: 'Remise en partie', remis: 'Remise', indisponible: 'Indisponible', annule: 'Annulée' },
  };
  const opts = d => Object.entries(d);
  const PRIO_ORDER = ['urgence_securite', 'critique_service', 'rapide', 'a_qualifier', 'planifiable'];
  const { ETAT_RANK, addDays, daysBetween, minutesBetween, otOuvert } = Calculs;

  // ---------- dates ----------
  const today = () => Store.now().slice(0, 10);
  const fmt = iso => iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}${iso.length > 10 ? ' ' + iso.slice(11, 16) : ''}` : '—';
  const fmtY = iso => iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}${iso.length > 10 ? ' ' + iso.slice(11, 16) : ''}` : '—';
  function fmtDuree(min) {
    if (min == null || isNaN(min)) return '—';
    if (min < 60) return `${Math.round(min)} min`;
    if (min < 1440) { const h = Math.floor(min / 60), m = Math.round(min % 60); return `${h} h${m ? ' ' + String(m).padStart(2, '0') : ''}`; }
    return `${(min / 1440).toFixed(1).replace('.', ',')} j`;
  }

  // ---------- accès aux données ----------
  const eq = id => data.equipements.get(id);
  const pers = id => data.personnes.get(id);
  const persNom = id => pers(id)?.nom || '—';
  function locPath(id) { const p = []; let l = data.localisations.get(id), n = 0; while (l && n++ < 10) { p.unshift(l.nom); l = data.localisations.get(l.parentId); } return p.join(' › '); }
  const otsDeDemande = d => list('ots').filter(o => (o.demandeIds || []).includes(d.id));
  const demandeOuverte = d => Calculs.demandeOuverte(d, otsDeDemande(d));
  // Cache recalculé à chaque affichage (le parc trie par état : évite de tout reparcourir).
  let cacheEtat = null;
  function etatEquipement(id) {
    if (!cacheEtat) {
      const dem = list('demandes'), ots = list('ots'), idx = Calculs.indexOtsParDemande(ots);
      cacheEtat = new Map(list('equipements').map(e => [e.id, Calculs.etatEquipement(e.id, dem, ots, idx)]));
    }
    return cacheEtat.get(id) || 'normal';
  }
  const actifs = o => (o.intervenants || []).filter(i => !i.fin);
  const attenteOuverte = o => (o.attentes || []).find(a => !a.fin);
  function journalDe(id) { return list('journal').filter(j => j.entiteId === id).reverse().sort((a, b) => b.le.localeCompare(a.le)); }
  function refDe(t, id) { const o = data[t]?.get(id); return o ? (o.ref || o.code || o.designation || o.nom || o.libelle || '') : ''; }

  function preventifsSansOT(horizonJours) {
    const lim = addDays(today(), horizonJours);
    return list('programmes').filter(p => p.actif !== false && p.prochaineEcheance && p.prochaineEcheance <= lim &&
      !list('ots').some(o => o.programmeId === p.id && o.echeance === p.prochaineEcheance && o.statut !== 'annulee'))
      .sort((a, b) => a.prochaineEcheance.localeCompare(b.prochaineEcheance));
  }

  // ---------- éléments d'interface ----------
  function chipGroup(name, dict, value, { multi = false, bind = null, colored = false, required = false } = {}) {
    const type = multi ? 'checkbox' : 'radio';
    const vals = multi ? (value || []) : [value];
    return `<div class="chips">${opts(dict).map(([k, l], i) => `<label class="chip ${colored ? k : ''}"><input type="${type}" name="${name}" value="${k}" ${vals.includes(k) ? 'checked' : ''} ${bind ? `data-bind="${bind}"` : ''} ${required && i === 0 ? 'required' : ''}><span>${esc(l)}</span></label>`).join('')}</div>`;
  }
  const badge = (txt, cls = '') => `<span class="badge ${cls}">${esc(txt)}</span>`;
  function badgeDem(d) {
    if (d.statut === 'traitement_organise' && !demandeOuverte(d)) return badge('Traitée', 'green');
    const c = { a_examiner: 'amber', prise_en_charge: 'blue', traitement_organise: 'blue' }[d.statut] || '';
    return badge(L.statutDem[d.statut], c);
  }
  function badgeOT(o) {
    const c = { en_cours: 'blue', suspendue: 'amber', cloturee: 'green', travail_termine: 'blue' }[o.statut] || '';
    return badge(L.statutOT[o.statut], c);
  }
  const badgeEtat = e => badge(L.etat[e] || 'Normal', { indisponible: 'red', degrade: 'amber', anomalie: 'amber', normal: 'green' }[e] || '');
  const empty = txt => `<div class="list-empty">${esc(txt)}</div>`;

  function demCard(d) {
    const e = eq(d.equipementId);
    return `<a class="card" href="#/demande/${d.id}"><div class="row"><span class="dot ${d.etat}"></span><span class="t grow">${esc(e?.designation || 'Équipement inconnu')}</span>${badgeDem(d)}</div>
      <div class="s">${esc(d.ref)} · ${esc(L.besoin[d.besoin] || '')} · ${fmt(d.creeLe)}</div><div class="s">${esc(trunc(d.constat, 120))}</div></a>`;
  }
  function otCard(o) {
    const e = eq(o.equipementId);
    const who = actifs(o).map(i => persNom(i.personneId)).join(', ');
    const quand = o.echeance ? `échéance ${fmt(o.echeance)}` : o.creneau ? `prévu ${fmt(o.creneau)}` : `créée ${fmt(o.creeLe)}`;
    return `<a class="card" href="#/ot/${o.id}"><div class="row"><span class="t grow">${esc(e?.designation || '—')}</span>${badgeOT(o)}</div>
      <div class="s">${esc(o.ref)} · ${esc(L.nature[o.nature])}${o.priorite && o.priorite !== 'a_qualifier' ? ' · ' + esc(L.priorite[o.priorite]) : ''} · ${quand}</div>
      ${who ? `<div class="s">👤 ${esc(who)}</div>` : ''}</a>`;
  }
  function eqCard(e) {
    const et = etatEquipement(e.id);
    return `<a class="card" href="#/eq/${e.id}"><div class="row"><span class="dot ${et}"></span><span class="t grow">${esc(e.designation)}</span>${et !== 'normal' ? badgeEtat(et) : ''}</div>
      <div class="s">${esc(e.code)} · ${esc(locPath(e.localisationId))}</div></a>`;
  }
  const seg = (items, cur) => `<div class="seg">${items.map(([href, lab, k]) => `<a href="${href}" class="${k === cur ? 'on' : ''}">${esc(lab)}</a>`).join('')}</div>`;
  const search = (target, ph) => `<input type="search" placeholder="${esc(ph)}" data-filter="${target}" style="margin-bottom:10px">`;

  function toast(msg) { const t = $('#toast'); t.textContent = msg; t.classList.add('show'); clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove('show'), 2200); }

  // ---------- fenêtres de saisie ----------
  function fieldHtml(f, v) {
    const id = 'ff_' + f.name;
    const lab = `<label class="f" ${f.type === 'chips' ? '' : `for="${id}"`}>${esc(f.label)}${f.required ? '' : ' <span class="opt">(facultatif)</span>'}</label>`;
    const req = f.required ? 'required' : '';
    switch (f.type) {
      case 'info': return `<p class="${f.cls || 'info'}">${f.html || esc(f.text)}</p>`;
      case 'textarea': return lab + `<textarea id="${id}" name="${f.name}" ${req} placeholder="${esc(f.placeholder || '')}">${esc(v)}</textarea>`;
      case 'select': return lab + `<select id="${id}" name="${f.name}" ${req}>${f.empty !== undefined ? `<option value="">${esc(f.empty)}</option>` : ''}${f.options.map(([k, l]) => `<option value="${esc(k)}" ${k === v ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
      case 'chips': return lab + chipGroup(f.name, f.options, v, { required: f.required });
      case 'chipsMulti': return lab + chipGroup(f.name, f.options, v || [], { multi: true });
      case 'checkbox': return `<label class="check"><input type="checkbox" name="${f.name}" ${v ? 'checked' : ''}> ${esc(f.label)}</label>`;
      default: return lab + `<input id="${id}" type="${f.type || 'text'}" name="${f.name}" value="${esc(v)}" ${req} ${f.type === 'number' ? 'step="any" inputmode="decimal"' : ''} placeholder="${esc(f.placeholder || '')}">`;
    }
  }
  function askForm({ title, fields, ok = 'Enregistrer', values = {}, cancel = 'Annuler' }) {
    return new Promise(resolve => {
      let out = null;
      const d = document.createElement('dialog');
      d.className = 'sheet';
      d.innerHTML = `<form novalidate><h3>${esc(title)}</h3>${fields.map(f => fieldHtml(f, values[f.name] ?? f.default)).join('')}
        <div class="sheet-actions">${cancel ? `<button type="button" class="btn ghost" data-x>${esc(cancel)}</button>` : ''}<button class="btn primary" type="submit">${esc(ok)}</button></div></form>`;
      document.body.append(d);
      const form = d.querySelector('form');
      d.querySelector('[data-x]')?.addEventListener('click', () => d.close());
      form.addEventListener('submit', e => {
        e.preventDefault();
        if (!form.reportValidity()) return;
        const v = {};
        for (const f of fields) {
          if (f.type === 'info') continue;
          const el = form.elements[f.name];
          if (f.type === 'chipsMulti') v[f.name] = [...form.querySelectorAll(`input[name="${f.name}"]:checked`)].map(i => i.value);
          else if (f.type === 'checkbox') v[f.name] = el.checked;
          else if (f.type === 'number') v[f.name] = el.value === '' ? null : Number(el.value);
          else v[f.name] = (el.value || '').trim() || null;
        }
        out = v; d.close();
      });
      d.addEventListener('close', () => { d.remove(); resolve(out); });
      d.showModal();
    });
  }
  const askText = async (title, label, ok = 'Valider') => (await askForm({ title, ok, fields: [{ name: 'v', label, type: 'textarea', required: true }] }))?.v || null;
  const askConfirm = async (title, text, ok = 'Confirmer') => !!(await askForm({ title, ok, fields: [{ type: 'info', text }] }));
  const alertBox = (title, lines) => askForm({ title, ok: 'Compris', cancel: null, fields: [{ type: 'info', cls: 'warn', html: lines.map(esc).join('<br>') }] });

  /** Modification tracée. Une intervention clôturée exige un motif de correction. */
  async function edit(t, id, patch, { render: rr = true, motif = null, action = null } = {}) {
    const cur = data[t].get(id);
    if (!cur) return;
    if (t === 'ots' && !peutModifierOT(cur)) { toast(cur.statut === 'cloturee' ? 'Intervention clôturée : correction réservée au responsable' : 'Consultation seule'); render(); return; }
    if (t === 'ots' && cur.statut === 'cloturee' && !motif && !action) {
      motif = await askText('Correction d’une intervention clôturée', 'Motif de la correction (conservé dans le journal)');
      if (!motif) { render(); return; }
    }
    await Store.save(t, { ...cur, ...patch }, { motif, action });
    if (rr) render(); else toast('✓ Enregistré sur l’appareil');
  }

  // ---------- droits (miroir de supabase/roles.sql ; le serveur reste l'autorité) ----------
  // Sans compte cloud : appli locale, aucune restriction.
  const role = () => Sync.profil()?.role || null;
  const estResp = () => !role() || role() === 'responsable';
  const DROITS = {
    responsable: ['eq-new', 'eq-edit', 'loc-new', 'prog-new', 'prog-edit', 'pers-new', 'pers-edit', 'ot-rouvrir', 'sync-tout', 'equipe', 'seuil-valider', 'seuil-refuser', 'achat-valider', 'achat-completer', 'achat-refuser'],
    terrain: ['ot-new', 'dem-ot', 'prog-ot', 'dem-pec', 'dem-classer', 'ot-demarrer', 'ot-planifier', 'ot-annuler', 'ot-suspendre', 'ot-reprendre', 'ot-terminer', 'ot-cloturer',
      'ot-ajout-int', 'ot-retirer', 'ot-ajout-piece', 'ot-annuler-piece', 'ot-ajout-suite', 'ot-lever',
      'bes-new', 'bes-urgent', 'bes-utilise', 'bes-rendre', 'bes-annuler'],
    magasin: ['art-new', 'mvt', 'mag-reserver', 'mag-remettre', 'mag-indispo', 'mag-rattacher', 'mag-verifier', 'seuil-proposer', 'achat-new', 'achat-soumettre', 'achat-annuler', 'achat-qte', 'achat-recevoir', 'achat-clore', 'iso-decider'],
    achats: ['achat-commande'],
    saisie: ['dem-edit', 'dem-annuler', 'photo-ajout', 'signaler'],
  };
  const ACT_MODULE = { 'art-new': 'magasin', mvt: 'magasin', 'mag-reserver': 'magasin', 'mag-remettre': 'magasin', 'mag-indispo': 'magasin', 'mag-rattacher': 'magasin', 'mag-verifier': 'magasin', 'seuil-proposer': 'magasin', 'seuil-valider': 'magasin', 'seuil-refuser': 'magasin', 'achat-new': 'achats', 'achat-soumettre': 'achats', 'achat-annuler': 'achats', 'achat-qte': 'achats', 'achat-valider': 'achats', 'achat-completer': 'achats', 'achat-refuser': 'achats', 'achat-commande': 'achats', 'achat-recevoir': 'achats', 'achat-clore': 'achats', 'iso-decider': 'achats', 'bes-new': 'magasin', 'bes-urgent': 'magasin', 'bes-utilise': 'magasin', 'bes-rendre': 'magasin', 'bes-annuler': 'magasin', 'prog-new': 'preventif', 'prog-edit': 'preventif', 'prog-ot': 'preventif' };
  function autorise(act) {
    const r = role();
    if (ACT_MODULE[act] && !aModule(ACT_MODULE[act])) return false;
    if (r && !ecritureOK() && Object.values(DROITS).some(l => l.includes(act))) return false;
    if (!r || r === 'responsable') return true;
    if (DROITS.responsable.includes(act)) return false;
    if (DROITS.terrain.includes(act)) return ['technicien', 'prestataire'].includes(r);
    if (DROITS.magasin.includes(act)) return r === 'magasinier';
    if (DROITS.achats.includes(act)) return r === 'achats';
    if (DROITS.saisie.includes(act)) return r !== 'pilote';
    return true;
  }
  const peutModifierOT = o => !ecritureOK() ? false : o.statut === 'cloturee' ? estResp() : (!role() || ['responsable', 'technicien', 'prestataire'].includes(role()));
  const REFUS_TXT = { responsable: 'Réservé au responsable', terrain: 'Réservé aux techniciens et au responsable', magasin: 'Réservé au magasin et au responsable', achats: 'Réservé aux achats et au responsable', saisie: 'Consultation seule' };
  function motifRefus(act) {
    if (ACT_MODULE[act] && !aModule(ACT_MODULE[act])) return `Module « ${ACT_MODULE[act]} » non inclus dans votre abonnement`;
    if (!ecritureOK()) return 'Abonnement suspendu ou expiré : consultation seule'; for (const [k, l] of Object.entries(DROITS)) if (l.includes(act)) return REFUS_TXT[k]; return 'Action non autorisée'; }

  // ---------- objets métier ----------
  const { NATURE_DU_BESOIN } = Calculs;
  function moiIntervenant(role = 'intervenant') {
    const me = Store.currentUser();
    return me ? [{ id: Store.uid(), personneId: me.id, role, depuis: Store.now(), fin: null, par: me.nom }] : [];
  }
  async function newOT(base) {
    const o = {
      id: Store.uid(), ref: await Store.nextRef('OT'), demandeIds: [], programmeId: null, equipementId: null,
      nature: 'a_qualifier', priorite: 'a_qualifier', statut: 'a_planifier', creneau: null, echeance: null,
      intervenants: [], activites: [], travaux: null, resultat: null, cause: null, certitudeCause: null, familleDefaut: null,
      avecArret: 'inconnu', arretDebut: null, arretFin: null, pieces: [], reserves: [], attentes: [], clotureLe: null, cloturePar: null, ...base,
    };
    await Store.save('ots', o);
    return o;
  }
  async function otDepuisDemande(d, demarrer) {
    const indispo = d.etat === 'indisponible';
    const o = await newOT({
      demandeIds: [d.id], equipementId: d.equipementId, nature: NATURE_DU_BESOIN[d.besoin] || 'a_qualifier',
      priorite: indispo ? 'critique_service' : 'a_qualifier', statut: demarrer ? 'en_cours' : 'a_planifier',
      intervenants: moiIntervenant(), avecArret: d.impact === 'interrompu' ? 'oui' : d.impact === 'aucun_constate' ? 'non' : 'inconnu',
      arretDebut: d.impact === 'interrompu' ? d.heureFait : null,
    });
    if (d.statut !== 'traitement_organise') await Store.update('demandes', d.id, { statut: 'traitement_organise' });
    return o;
  }

  // ---------- vues ----------
  const V = {};

  V.accueil = () => {
    if (role() === 'magasinier' && aModule('magasin') && V.accueilMagasin) return V.accueilMagasin();
    if (role() === 'achats' && aModule('achats') && V.accueilAchats) return V.accueilAchats();
    if (!data.equipements.size) {
      return `<h1>Bienvenue</h1><div class="card"><p>Aucune donnée sur cet appareil.</p>
        <div class="actions"><button class="btn primary" data-act="demo">Charger la démo</button><a class="btn" href="#/parc">Créer mes équipements</a></div>
        <p class="small muted">Tout est enregistré sur cet appareil, même sans réseau. Exportez régulièrement une sauvegarde (Réglages).</p></div>`;
    }
    const dem = list('demandes').filter(demandeOuverte);
    const aEx = dem.filter(d => d.statut === 'a_examiner').sort((a, b) => b.creeLe.localeCompare(a.creeLe));
    const indispo = list('equipements').filter(e => etatEquipement(e.id) === 'indisponible');
    const otsO = list('ots').filter(otOuvert);
    const me = Store.currentUser();
    const mine = me ? otsO.filter(o => actifs(o).some(i => i.personneId === me.id)) : [];
    const susp = otsO.filter(o => o.statut === 'suspendue');
    const prev = preventifsSansOT(7);
    return `<h1>Aujourd’hui <span class="muted small" style="font-weight:400">${fmtY(today())}</span></h1>
      ${!me ? `<p class="warn">Indiquez qui utilise cet appareil pour signer vos saisies. <a href="#" data-act="who">Choisir</a></p>` : ''}
      ${rappelSauvegarde()}
      <div class="tiles">
        <a class="tile red" href="#/parc?f=indisponible"><b>${indispo.length}</b><span>Équipements indisponibles</span></a>
        <a class="tile amber" href="#/demandes?f=a_examiner"><b>${aEx.length}</b><span>Demandes à examiner</span></a>
        <a class="tile blue" href="#/ots"><b>${otsO.length}</b><span>Travaux ouverts</span></a>
        <a class="tile" href="#/preventif"><b>${prev.length}</b><span>Préventifs à lancer (7 j)</span></a>
      </div>
      ${indispo.length ? `<h2>Indisponibles</h2>${indispo.map(eqCard).join('')}` : ''}
      ${me ? `<h2>Mes travaux</h2>${mine.length ? mine.map(otCard).join('') : empty('Aucun travail affecté.')}` : ''}
      <h2>Demandes à examiner</h2>${aEx.length ? aEx.slice(0, 8).map(demCard).join('') : empty('Rien à examiner.')}
      ${susp.length ? `<h2>Travaux en attente</h2>${susp.map(otCard).join('')}` : ''}
      ${prev.length ? `<h2>Préventif à lancer</h2>${prev.map(progCard).join('')}` : ''}`;
  };

  /** Les données n'existent que sur l'appareil : rappeler l'export au-delà de 7 jours ou 100 modifications. */
  function etatSauvegarde() {
    const depuis = data.meta.get('sauvegarde')?.le || null;
    const modifs = list('journal').filter(j => !depuis || j.le > depuis).length;
    return { depuis, modifs, jours: depuis ? daysBetween(depuis, today()) : null };
  }
  function rappelSauvegarde() {
    const s = etatSauvegarde(), c = Sync.etatCourant();
    if (c.connecte && !c.attente && !c.erreur) return ''; // tout est déjà sur le serveur
    if (!s.modifs || (s.depuis && s.jours < 7 && s.modifs < 100)) return '';
    return `<p class="warn">💾 ${s.depuis ? `Dernière sauvegarde il y a ${s.jours} j` : 'Aucune sauvegarde exportée'} · ${s.modifs} modification(s) présentes uniquement sur cet appareil. <a href="#" data-act="export">Exporter maintenant</a></p>`;
  }

  // ---------- photos (compressées sur l'appareil, ~150 Ko) ----------
  async function compresserPhoto(file, max = 1280, qualite = 0.72) {
    const url = URL.createObjectURL(file);
    try {
      const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = url; });
      const k = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
      const c = document.createElement('canvas');
      c.width = Math.round(img.naturalWidth * k); c.height = Math.round(img.naturalHeight * k);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      return c.toDataURL('image/jpeg', qualite);
    } finally { URL.revokeObjectURL(url); }
  }
  const photosDe = id => list('photos').filter(p => p.parentId === id).sort((a, b) => a.le.localeCompare(b.le));
  function blocPhotos(type, id) {
    const ph = photosDe(id);
    return `<h2>Photos</h2><div class="card"><div class="thumbs">${ph.map(p => `<button type="button" data-act="photo-voir" data-id="${p.id}"><img src="${p.dataUrl}" alt="Photo du ${esc(fmt(p.le))}"></button>`).join('')}</div>
      ${ph.length ? '' : '<p class="muted small" style="margin-top:0">Aucune photo.</p>'}<button class="btn sm" data-act="photo-ajout" data-type="${type}" data-id="${id}">📷 Ajouter une photo</button></div>`;
  }

  V.demandes = r => {
    const f = r.q.get('f') || 'ouvertes';
    let items = list('demandes');
    if (f === 'ouvertes') items = items.filter(demandeOuverte);
    if (f === 'a_examiner') items = items.filter(d => d.statut === 'a_examiner');
    items.sort((a, b) => b.creeLe.localeCompare(a.creeLe));
    return `<h1>Demandes</h1>${seg([['#/demandes', 'Ouvertes', 'ouvertes'], ['#/demandes?f=a_examiner', 'À examiner', 'a_examiner'], ['#/demandes?f=toutes', 'Toutes', 'toutes']], f)}
      ${search('#lst', 'Rechercher (équipement, constat, réf.)')}<div id="lst">${items.length ? items.map(demCard).join('') : empty('Aucune demande.')}</div>`;
  };

  V.demande = r => {
    const d = data.demandes.get(r.id);
    if (!d) return empty('Demande introuvable.');
    const e = eq(d.equipementId);
    const ots = otsDeDemande(d);
    const ouverte = ['a_examiner', 'prise_en_charge'].includes(d.statut);
    const doublons = list('demandes').filter(x => x.id !== d.id && x.equipementId === d.equipementId && demandeOuverte(x));
    return `<div class="row"><h1 class="grow">${esc(d.ref)}</h1>${badgeDem(d)}</div>
      <a class="card" href="#/eq/${e?.id}"><div class="row"><span class="dot ${etatEquipement(d.equipementId)}"></span><span class="t">${esc(e?.designation)}</span></div><div class="s">${esc(e?.code)} · ${esc(locPath(e?.localisationId))}</div></a>
      <div class="card"><p style="margin-top:0">${esc(d.constat)}</p><dl class="kv">
        <dt>État</dt><dd>${badgeEtat(d.etat)}</dd>
        <dt>Besoin</dt><dd>${esc(L.besoin[d.besoin])}</dd>
        <dt>Impact</dt><dd>${esc(L.impact[d.impact] || '—')}</dd>
        <dt>Heure du fait</dt><dd>${d.heureFait ? fmtY(d.heureFait) + ` <span class="muted">(${esc((L.precision[d.precisionHeure] || '').toLowerCase())})</span>` : '<span class="muted">inconnue</span>'}</dd>
        <dt>Origine</dt><dd>${esc(L.origine[d.origine])}${d.tiers?.nom ? ' — ' + esc(d.tiers.nom) + (d.tiers.service ? ' (' + esc(d.tiers.service) + ')' : '') : ''}</dd>
        <dt>Créée</dt><dd>${fmtY(d.creeLe)} par ${esc(d.creePar)}</dd>
        ${d.priseEnChargePar ? `<dt>Prise en charge</dt><dd>${fmtY(d.priseEnChargeLe)} par ${esc(persNom(d.priseEnChargePar))}</dd>` : ''}
        ${d.motifClassement ? `<dt>Motif</dt><dd>${esc(d.motifClassement)}</dd>` : ''}
      </dl></div>
      ${doublons.length && ouverte ? `<p class="warn">Autre(s) demande(s) ouverte(s) sur cet équipement : ${doublons.map(x => `<a href="#/demande/${x.id}">${esc(x.ref)}</a>`).join(', ')}. Vérifiez s’il s’agit du même fait.</p>` : ''}
      <div class="actions">
        ${d.statut === 'a_examiner' ? `<button class="btn primary" data-act="dem-pec" data-id="${d.id}">Je prends en charge</button>` : ''}
        ${ouverte || d.statut === 'traitement_organise' ? `<button class="btn ${d.statut === 'a_examiner' ? '' : 'primary'}" data-act="dem-ot" data-id="${d.id}">${ots.length ? 'Ajouter une intervention' : 'Créer l’intervention'}</button>` : ''}
        ${ouverte ? `<button class="btn" data-act="dem-classer" data-id="${d.id}">Classer sans travail</button>` : ''}
        <button class="btn ghost" data-act="dem-edit" data-id="${d.id}">Compléter / corriger</button>
        ${ouverte ? `<button class="btn ghost danger" data-act="dem-annuler" data-id="${d.id}">Annuler</button>` : ''}
      </div>
      ${blocPhotos('demandes', d.id)}
      <h2>Interventions liées</h2>${ots.length ? ots.map(otCard).join('') : empty('Aucune intervention.')}
      ${historique(d.id)}`;
  };

  V.ots = r => {
    const f = r.q.get('f') || 'ouverts';
    let items = list('ots');
    const F = {
      ouverts: otOuvert, en_cours: o => ['en_cours', 'travail_termine'].includes(o.statut), suspendue: o => o.statut === 'suspendue',
      a_faire: o => ['a_preparer', 'a_planifier', 'prete'].includes(o.statut), cloturee: o => o.statut === 'cloturee', tous: () => true,
    };
    items = items.filter(F[f] || F.ouverts);
    items.sort((a, b) => f === 'cloturee' ? (b.clotureLe || '').localeCompare(a.clotureLe || '')
      : (PRIO_ORDER.indexOf(a.priorite) - PRIO_ORDER.indexOf(b.priorite)) || b.creeLe.localeCompare(a.creeLe));
    return `<h1>Travaux</h1>${seg([['#/ots', 'Ouverts', 'ouverts'], ['#/ots?f=a_faire', 'À faire', 'a_faire'], ['#/ots?f=en_cours', 'En cours', 'en_cours'], ['#/ots?f=suspendue', 'En attente', 'suspendue'], ['#/ots?f=cloturee', 'Clôturés', 'cloturee'], ['#/ots?f=tous', 'Tous', 'tous']], f)}
      ${search('#lst', 'Rechercher')}<div id="lst">${items.length ? items.map(otCard).join('') : empty('Aucune intervention.')}</div>
      <div class="actions"><button class="btn" data-act="ot-new">Nouvelle intervention sans demande</button></div>`;
  };

  V.ot = r => {
    const o = data.ots.get(r.id);
    if (!o) return empty('Intervention introuvable.');
    const e = eq(o.equipementId);
    const b = `ots|${o.id}|`;
    const att = attenteOuverte(o);
    const prog = o.programmeId ? data.programmes.get(o.programmeId) : null;
    const dems = (o.demandeIds || []).map(id => data.demandes.get(id)).filter(Boolean);
    const clos = o.statut === 'cloturee';
    const sAct = {
      a_preparer: ['demarrer', 'planifier', 'annuler'], a_planifier: ['demarrer', 'planifier', 'annuler'], prete: ['demarrer', 'planifier', 'annuler'],
      en_cours: ['suspendre', 'terminer', 'cloturer'], suspendue: ['reprendre', 'cloturer'], travail_termine: ['cloturer', 'reprendre'],
      cloturee: ['rouvrir'], annulee: [],
    }[o.statut];
    const LBL = { demarrer: ['Démarrer', 'primary'], planifier: ['Planifier', ''], annuler: ['Annuler', 'ghost danger'], suspendre: ['Mettre en attente', ''], terminer: ['Travail terminé', ''], cloturer: ['Clôturer', 'primary'], reprendre: ['Reprendre', 'primary'], rouvrir: ['Rouvrir', 'ghost'] };
    let duree = '';
    if (o.avecArret === 'oui') {
      duree = o.arretDebut && o.arretFin ? `<p class="info">Durée d’arrêt : <b>${fmtDuree(minutesBetween(o.arretDebut, o.arretFin))}</b> (bornes renseignées)</p>`
        : `<p class="small muted">Durée non calculée tant que début et fin ne sont pas tous deux connus.</p>`;
    }
    return `<div class="row"><h1 class="grow">${esc(o.ref)}</h1>${badgeOT(o)}</div>
      <a class="card" href="#/eq/${e?.id}"><div class="row"><span class="dot ${etatEquipement(o.equipementId)}"></span><span class="t">${esc(e?.designation)}</span></div><div class="s">${esc(e?.code)} · ${esc(locPath(e?.localisationId))}</div>
        ${dems.length ? `<div class="s">Demande : ${dems.map(d => esc(d.ref) + ' — ' + esc(trunc(d.constat, 60))).join(' ; ')}</div>` : ''}
        ${prog ? `<div class="s">Programme : ${esc(prog.libelle)} · échéance ${fmtY(o.echeance)}</div>` : ''}</a>
      ${att ? `<p class="warn">En attente : <b>${esc(L.attente[att.motif])}</b>${att.detail ? ' — ' + esc(att.detail) : ''} · depuis ${fmt(att.depuis)}${att.responsableId ? ' · levée : ' + esc(persNom(att.responsableId)) : ''}</p>` : ''}
      ${clos ? `<p class="info">Clôturée le ${fmtY(o.clotureLe)} par ${esc(o.cloturePar)}. Toute modification demande un motif.</p>` : ''}
      <div class="actions">${sAct.map(a => `<button class="btn ${LBL[a][1]}" data-act="ot-${a}" data-id="${o.id}">${LBL[a][0]}</button>`).join('')}</div>
      ${prog?.instruction ? `<div class="card"><div class="t">Instruction</div><p class="small" style="white-space:pre-wrap;margin:6px 0 0">${esc(prog.instruction)}</p></div>` : ''}

      <h2>Intervenants</h2><div class="card"><ul class="lines">${(o.intervenants || []).map(i => `<li class="${i.fin ? 'off' : ''}"><span class="grow">${esc(persNom(i.personneId))} <span class="muted small">· ${esc(L.roleOT[i.role])}</span></span>${!i.fin ? `<button class="btn sm ghost" data-act="ot-retirer" data-id="${o.id}" data-sub="${i.id}">Retirer</button>` : `<span class="small">jusqu’au ${fmt(i.fin)}</span>`}</li>`).join('') || '<li class="muted">Personne n’est affecté.</li>'}</ul>
        <button class="btn sm" data-act="ot-ajout-int" data-id="${o.id}">+ Ajouter</button></div>

      <h2>Arrêt de production</h2><div class="card">${chipGroup('avecArret', L.arret, o.avecArret, { bind: b + 'avecArret' })}
        ${o.avecArret === 'oui' ? `<label class="f">Début <span class="opt">(facultatif)</span></label><input type="datetime-local" value="${esc(o.arretDebut)}" data-bind="${b}arretDebut" data-rerender>
        <label class="f">Remise à disposition <span class="opt">(facultatif)</span></label><input type="datetime-local" value="${esc(o.arretFin)}" data-bind="${b}arretFin" data-rerender>${duree}` : ''}</div>

      <h2>Travail réalisé</h2><div class="card">
        <label class="f" style="margin-top:0">Activités</label>${chipGroup('activites', L.activite, o.activites, { multi: true, bind: b + 'activites' })}
        <label class="f">Ce qui a été fait</label><textarea data-bind="${b}travaux" placeholder="Constats, travaux, essais…">${esc(o.travaux)}</textarea>
        <label class="f">Résultat</label>${chipGroup('resultat', L.resultat, o.resultat, { bind: b + 'resultat' })}</div>

      <h2>Cause</h2><div class="card">
        ${chipGroup('certitudeCause', L.certitude, o.certitudeCause, { bind: b + 'certitudeCause' })}
        <label class="f">Famille du défaut <span class="opt">(facultatif)</span></label><select data-bind="${b}familleDefaut"><option value="">—</option>${opts(L.famille).map(([k, l]) => `<option value="${k}" ${o.familleDefaut === k ? 'selected' : ''}>${l}</option>`).join('')}</select>
        <label class="f">Cause <span class="opt">(laisser vide si inconnue)</span></label><textarea data-bind="${b}cause">${esc(o.cause)}</textarea></div>

      ${blocPieces(o)}

      <h2>Réserves et suites</h2><div class="card"><ul class="lines">${(o.reserves || []).map(s => `<li class="${s.statut !== 'ouverte' ? 'off' : ''}"><span class="grow">${s.bloquante ? badge('Bloquante', 'red') + ' ' : ''}${esc(L.typeSuite[s.type] || '')} : ${esc(s.texte)}<span class="muted small">${s.responsableId ? ' · ' + esc(persNom(s.responsableId)) : ''}${s.echeance ? ' · avant ' + fmt(s.echeance) : ''}</span></span>${s.statut === 'ouverte' ? `<button class="btn sm" data-act="ot-lever" data-id="${o.id}" data-sub="${s.id}">Lever</button>` : `<span class="small">levée ${fmt(s.leveeLe)}</span>`}</li>`).join('') || '<li class="muted">Aucune.</li>'}</ul>
        <button class="btn sm" data-act="ot-ajout-suite" data-id="${o.id}">+ Réserve / suite</button></div>
      ${blocPhotos('ots', o.id)}

      <h2>Qualification</h2><div class="card">
        <label class="f" style="margin-top:0">Nature</label>${chipGroup('nature', L.nature, o.nature, { bind: b + 'nature' })}
        <label class="f">Priorité</label>${chipGroup('priorite', L.priorite, o.priorite, { bind: b + 'priorite' })}
        <label class="f">Créneau prévu <span class="opt">(facultatif)</span></label><input type="datetime-local" value="${esc(o.creneau)}" data-bind="${b}creneau"></div>
      ${(o.attentes || []).length ? `<h2>Attentes</h2><div class="card"><ul class="lines">${o.attentes.map(a => `<li><span class="grow">${esc(L.attente[a.motif])}${a.detail ? ' — ' + esc(a.detail) : ''}</span><span class="small muted">${fmt(a.depuis)} → ${a.fin ? fmt(a.fin) : 'en cours'}</span></li>`).join('')}</ul></div>` : ''}
      ${historique(o.id)}`;
  };

  // ---------- pièces de l'intervention (volet B : besoin ≠ réservation ≠ remise ≠ utilisation ≠ retour) ----------
  const besoinsDe = o => [...data.besoins.values()].filter(b => b.otId === o.id).sort((a, b) => (a.creeLe || '').localeCompare(b.creeLe || ''));
  const desigBesoin = b => b.articleId ? (data.articles.get(b.articleId)?.designation || 'Article') : (b.description || 'Pièce');
  const CLS_BESOIN = { demande: 'blue', reserve: 'blue', partiellement_remis: 'amber', remis: 'green', indisponible: 'red' };
  // Stock par site : celui de l'intervention, pas le site affiché sur l'appareil.
  const dispo = (id, siteId) => Calculs.stockDisponible([...data.besoins.values()], [...data.mouvements.values()], id, siteId);
  const optsArticles = siteId => list('articles').filter(a => a.actif !== false).map(a => [a.id, `${a.designation} · disponible ${dispo(a.id, siteId)} ${a.unite || ''}`]);
  function blocPieces(o) {
    const mvts = [...data.mouvements.values()];
    const lignes = besoinsDe(o).map(b => {
      const e = Calculs.etatBesoin(b, mvts), r = Calculs.rapprochementBesoin(b, mvts, o.pieces), actif = e !== 'annule';
      const k = `data-id="${o.id}" data-sub="${b.id}"`;
      const btn = [
        actif && b.articleId && e !== 'remis' ? `<button class="btn sm" data-act="bes-urgent" ${k}>Retrait urgent</button>` : '',
        r.detenu > 0 ? `<button class="btn sm primary" data-act="bes-utilise" ${k}>J’ai utilisé</button><button class="btn sm" data-act="bes-rendre" ${k}>Je rends</button>` : '',
        ['demande', 'reserve'].includes(e) ? `<button class="btn sm ghost" data-act="bes-annuler" ${k}>Annuler</button>` : ''].join('');
      const suivi = [r.remis && `remis ${r.remis}`, r.utilise && `utilisé ${r.utilise}`, r.retourne && `rendu ${r.retourne}`, r.detenu > 0 && `<b>en main ${r.detenu}</b>`,
        r.ecart && '<b>écart à expliquer</b>', b.delai && `délai annoncé ${esc(fmtY(b.delai))}`].filter(Boolean).join(' · ');
      return `<li class="${actif ? '' : 'off'}" style="display:block"><div>${esc(b.qte)} × ${esc(desigBesoin(b))}${b.articleId ? '' : ' <span class="muted small">(hors catalogue)</span>'} ${b.urgent ? badge('Urgent', 'red') : ''} ${badge(L.etatBesoin[e], CLS_BESOIN[e] || '')}</div>
        <div class="small muted">Demandée ${esc(fmtY(b.demandeLe || b.creeLe))} par ${esc(b.demandeur || b.creePar)}${suivi ? ' · ' + suivi : ''}</div>
        ${btn ? `<div class="actions" style="margin:8px 0 0">${btn}</div>` : ''}</li>`;
    });
    const utilisees = (o.pieces || []).map(p => `<li class="${p.annulee ? 'off' : ''}"><span class="grow">${esc(p.qte)} × ${esc(p.articleId ? data.articles.get(p.articleId)?.designation : p.libelle)}${p.articleId || p.besoinId ? '' : ' <span class="muted small">(hors stock)</span>'}</span>${!p.annulee ? `<button class="btn sm ghost" data-act="ot-annuler-piece" data-id="${o.id}" data-sub="${p.id}">${p.articleId && !p.besoinId ? 'Retour' : 'Annuler'}</button>` : ''}</li>`);
    return `<h2>Pièces</h2><div class="card">
      ${lignes.length ? `<ul class="lines">${lignes.join('')}</ul>` : '<p class="muted small" style="margin:0 0 8px">Aucune pièce demandée. Une demande ne retire rien du stock : le magasin réserve puis remet.</p>'}
      <div class="actions" style="margin-bottom:0"><button class="btn sm" data-act="bes-new" data-id="${o.id}">Demander une pièce</button><button class="btn sm" data-act="bes-urgent" data-id="${o.id}">Retrait urgent</button></div></div>
      <h2>Pièces utilisées</h2><div class="card"><ul class="lines">${utilisees.join('') || '<li class="muted">Aucune pièce déclarée utilisée.</li>'}</ul>
        <button class="btn sm" data-act="ot-ajout-piece" data-id="${o.id}">+ Pièce hors stock</button></div>`;
  }

  function historique(id) {
    const j = journalDe(id);
    if (!j.length) return '';
    return `<details class="more" style="margin-top:22px"><summary>Historique (${j.length})</summary>${j.slice(0, 80).map(journalLine).join('')}</details>`;
  }
  function valTxt(v) { if (v == null) return '∅'; if (typeof v === 'object') return trunc(Array.isArray(v) ? `${v.length} élément(s)` : JSON.stringify(v), 60); return trunc(String(v), 80); }
  function journalLine(j) {
    const quoi = j.champ ? `<code>${esc(j.champ)}</code> : ${esc(valTxt(j.avant))} → ${esc(valTxt(j.apres))}` : esc(j.action === 'creation' ? 'création' : j.action);
    return `<div class="journal-item"><span class="muted">${fmtY(j.le)} · ${esc(j.auteur)}</span><br>${quoi}${j.motif ? `<br><span class="muted">Motif : ${esc(j.motif)}</span>` : ''}</div>`;
  }

  V.parc = r => {
    const f = r.q.get('f') || 'tous';
    let items = list('equipements').filter(e => e.actif !== false);
    if (f === 'indisponible') items = items.filter(e => etatEquipement(e.id) === 'indisponible');
    if (f === 'alerte') items = items.filter(e => etatEquipement(e.id) !== 'normal');
    items.sort((a, b) => (ETAT_RANK[etatEquipement(a.id)] - ETAT_RANK[etatEquipement(b.id)]) || a.designation.localeCompare(b.designation));
    return `<h1>Parc</h1>${seg([['#/parc', 'Tous', 'tous'], ['#/parc?f=alerte', 'Avec anomalie', 'alerte'], ['#/parc?f=indisponible', 'Indisponibles', 'indisponible']], f)}
      ${search('#lst', 'Rechercher (code, nom, lieu)')}<div id="lst">${items.length ? items.map(eqCard).join('') : empty('Aucun équipement.')}</div>
      <div class="actions"><button class="btn" data-act="eq-new">+ Équipement</button><button class="btn" data-act="loc-new">+ Lieu</button><a class="btn" href="#/qr">Planche de QR codes</a></div>`;
  };

  /** Adresse imprimée dans les QR : jamais une adresse locale (localhost, IP du PC),
      sinon le téléphone ne peut pas l'ouvrir. Réglable dans Réglages. */
  const ADRESSE_PAR_DEFAUT = 'https://hichamothmani90-ship-it.github.io/perfora-Eng/';
  const estLocale = h => /^(localhost|127\.|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.|\[?::1\]?$)/.test(h) || h === '';
  function adressePublique() {
    const reglee = data.meta.get('adresse')?.url;
    if (reglee) return reglee;
    return estLocale(location.hostname) || location.protocol !== 'https:' ? ADRESSE_PAR_DEFAUT : location.origin + location.pathname;
  }
  const lienSignaler = e => `${adressePublique().replace(/#.*$/, '')}#/signaler?eq=${encodeURIComponent(e.code)}`;

  V.eq = r => {
    const e = data.equipements.get(r.id);
    if (!e) return empty('Équipement introuvable.');
    const et = etatEquipement(e.id);
    const dems = list('demandes').filter(d => d.equipementId === e.id);
    const ots = list('ots').filter(o => o.equipementId === e.id);
    const ouverts = [...dems.filter(demandeOuverte).map(d => ['d', d]), ...ots.filter(otOuvert).map(o => ['o', o])];
    const hist = [...dems.map(d => ['d', d]), ...ots.map(o => ['o', o])].sort((a, b) => b[1].creeLe.localeCompare(a[1].creeLe));
    const progs = list('programmes').filter(p => p.equipementId === e.id);
    const conso = consoParArticle(ots.map(o => o.id));
    const lien = lienSignaler(e);
    return `<div class="row"><h1 class="grow">${esc(e.designation)}</h1>${badgeEtat(et)}</div>
      <div class="card"><dl class="kv"><dt>Code</dt><dd>${esc(e.code)}</dd><dt>Lieu</dt><dd>${esc(locPath(e.localisationId))}</dd>
        ${e.famille ? `<dt>Famille</dt><dd>${esc(e.famille)}</dd>` : ''}<dt>Criticité</dt><dd>${esc(e.criticite || '—')} / 4</dd></dl>
        <div class="row" style="margin-top:12px;align-items:flex-start">${QR.svg(lien, 104)}<p class="small muted grow" style="margin:0">Scanner ce code ouvre « Signaler » sur cet équipement.<br><span style="word-break:break-all">${esc(lien)}</span><br><button class="btn sm ghost" data-act="copy" data-v="${esc(lien)}">Copier le lien</button> <a class="btn sm ghost" href="#/qr?eq=${e.id}">Imprimer</a></p></div></div>
      <div class="actions"><a class="btn primary" href="#/signaler?eq=${encodeURIComponent(e.code)}">Signaler sur cet équipement</a><button class="btn ghost" data-act="eq-edit" data-id="${e.id}">Modifier</button></div>
      <h2>En cours</h2>${ouverts.length ? ouverts.map(([k, x]) => k === 'd' ? demCard(x) : otCard(x)).join('') : empty('Rien en cours.')}
      ${progs.length ? `<h2>Préventif</h2>${progs.map(progCard).join('')}` : ''}
      ${conso.length ? `<h2>Pièces consommées</h2><div class="card"><ul class="lines">${conso.map(([n, q]) => `<li><span class="grow">${esc(n)}</span><b>${q}</b></li>`).join('')}</ul></div>` : ''}
      <h2>Historique</h2>${hist.length ? hist.slice(0, 40).map(([k, x]) => k === 'd' ? demCard(x) : otCard(x)).join('') : empty('Aucun historique.')}`;
  };

  function consoParArticle(otIds) {
    const m = new Map();
    for (const o of otIds.map(id => data.ots.get(id))) for (const p of o.pieces || []) {
      if (p.annulee) continue;
      const n = p.articleId ? data.articles.get(p.articleId)?.designation : p.libelle + ' (hors stock)';
      m.set(n, (m.get(n) || 0) + Number(p.qte || 0));
    }
    return [...m.entries()].sort((a, b) => b[1] - a[1]);
  }

  function progCard(p) {
    const e = eq(p.equipementId);
    const retard = p.prochaineEcheance && p.prochaineEcheance < today();
    const otOpen = list('ots').find(o => o.programmeId === p.id && o.echeance === p.prochaineEcheance && o.statut !== 'annulee');
    const b = otOpen ? badge(otOpen.statut === 'cloturee' ? 'Réalisé' : 'OT ' + L.statutOT[otOpen.statut].toLowerCase(), otOpen.statut === 'cloturee' ? 'green' : 'blue')
      : retard ? badge('En retard', 'red') : p.prochaineEcheance <= addDays(today(), 7) ? badge('À lancer', 'amber') : '';
    return `<div class="card"><div class="row"><span class="t grow">${esc(p.libelle)}</span>${b}</div>
      <div class="s">${esc(e?.designation)} · ${esc(L.modele[p.modele] || '')} · tous les ${esc(p.periodiciteJours)} j · échéance <b>${fmtY(p.prochaineEcheance)}</b></div>
      <div class="actions" style="margin-bottom:0">${otOpen ? `<a class="btn sm" href="#/ot/${otOpen.id}">Ouvrir ${esc(otOpen.ref)}</a>` : `<button class="btn sm primary" data-act="prog-ot" data-id="${p.id}">Créer l’OT</button>`}<button class="btn sm ghost" data-act="prog-edit" data-id="${p.id}">Modifier</button></div></div>`;
  }

  V.preventif = () => {
    const progs = list('programmes').filter(p => p.actif !== false).sort((a, b) => (a.prochaineEcheance || '').localeCompare(b.prochaineEcheance || ''));
    return `<h1>Préventif</h1><p class="small muted">Chaque échéance produit une intervention. L’échéance initiale est conservée ; la suivante est calculée à la clôture.</p>
      ${progs.length ? progs.map(progCard).join('') : empty('Aucun programme préventif.')}
      <div class="actions"><button class="btn" data-act="prog-new">+ Programme</button></div>`;
  };

  V.indicateurs = r => {
    const p = Number(r.q.get('p') || 90);
    const from = addDays(today(), -p);
    const I = Calculs.indicateurs({ demandes: list('demandes'), ots: list('ots'), programmes: list('programmes') }, { from, today: today() });
    const parNature = I.parNature, maxN = Math.max(1, ...Object.values(parNature));
    const med = I.delaiCloture.mediane, totalDus = I.preventif.dus, aTemps = I.preventif.aTemps;
    const rep = I.repetitives, A = I.arrets, ouv = I.demandesOuvertes;
    return `<h1>Indicateurs</h1>${seg([['#/indicateurs?p=30', '30 jours', 30], ['#/indicateurs?p=90', '90 jours', 90], ['#/indicateurs?p=365', '12 mois', 365]], p)}
      <div class="tiles">
        <div class="tile blue"><b>${I.interventions}</b><span>Interventions créées</span></div>
        <div class="tile"><b>${med == null ? '—' : fmtDuree(med)}</b><span>Délai médian de clôture (${I.delaiCloture.n})</span></div>
        <div class="tile ${totalDus && aTemps / totalDus < .8 ? 'amber' : ''}"><b>${totalDus ? Math.round(100 * aTemps / totalDus) + ' %' : '—'}</b><span>Préventif à échéance (${aTemps}/${totalDus})</span></div>
        <div class="tile ${ouv.n ? 'amber' : ''}"><b>${ouv.n}</b><span>Demandes ouvertes${ouv.n ? ` · la plus ancienne ${ouv.plusAncienneJours} j` : ''}</span></div>
      </div>
      <h2>Interventions par nature</h2><div class="card">${opts(L.nature).filter(([k]) => parNature[k]).map(([k, l]) => `<div class="barrow"><span>${esc(l)}</span><div class="bar" style="width:${100 * parNature[k] / maxN}%"></div><b>${parNature[k]}</b></div>`).join('') || '<p class="muted">Aucune intervention sur la période.</p>'}</div>
      <h2>Pannes répétitives</h2><div class="card">${rep.length ? `<ul class="lines">${rep.map(([id, n]) => `<li><a class="grow" href="#/eq/${id}">${esc(eq(id)?.designation)}</a>${n >= 3 ? badge('À analyser', 'red') : ''}<b>${n} faits</b></li>`).join('')}</ul>` : '<p class="muted" style="margin:0">Aucun équipement avec 2 faits ou plus.</p>'}<p class="small muted">Un fait = une demande (anomalie, dégradé, indisponible), quel que soit le nombre d’interventions.</p></div>
      <h2>Pièces consommées par équipement</h2><div class="card">${I.piecesParEquipement.length ? `<ul class="lines">${I.piecesParEquipement.map(([id, n]) => `<li><a class="grow" href="#/eq/${id}">${esc(eq(id)?.designation)}</a><b>${n}</b></li>`).join('')}</ul>` : '<p class="muted" style="margin:0">Aucune pièce consommée.</p>'}</div>
      <h2>Arrêts de production</h2><div class="card"><dl class="kv"><dt>Faits avec arrêt</dt><dd>${A.faits}</dd><dt>Bornes connues</dt><dd>${A.faitsBornes} sur ${A.faits}</dd><dt>Durée cumulée connue</dt><dd>${A.dureeConnue == null ? '—' : fmtDuree(A.dureeConnue)}</dd></dl>
        <p class="small muted">Durée calculée uniquement quand début et fin sont renseignés ; les plages qui se chevauchent sur un même équipement ne sont comptées qu’une fois.</p></div>
      <p class="small muted">Aucun classement individuel : les indicateurs portent sur les équipements.</p>`;
  };

  V.journal = r => {
    const f = r.q.get('f') || '';
    let j = list('journal').reverse().sort((a, b) => b.le.localeCompare(a.le));
    if (f) j = j.filter(x => x.entite === f);
    return `<h1>Journal d’audit</h1><p class="small muted">Append-only : chaque création et modification est conservée avec auteur, date et motif.</p>
      ${seg([['#/journal', 'Tout', ''], ...['demandes', 'ots', 'equipements', 'mouvements', 'programmes'].map(k => [`#/journal?f=${k}`, L.entite[k], k])], f)}
      <div class="card">${j.slice(0, 300).map(x => `<div class="journal-item"><b>${esc(L.entite[x.entite] || x.entite)} ${esc(refDe(x.entite, x.entiteId))}</b><br>${journalLine(x).replace('<div class="journal-item">', '').replace(/<\/div>$/, '')}</div>`).join('') || '<p class="muted">Journal vide.</p>'}</div>`;
  };

  V.qr = r => {
    const lieu = r.q.get('lieu') || '', un = r.q.get('eq');
    let eqs = list('equipements').filter(e => e.actif !== false);
    if (un) eqs = eqs.filter(e => e.id === un);
    else if (lieu) eqs = eqs.filter(e => locPath(e.localisationId).startsWith(locPath(lieu)));
    eqs.sort((a, b) => locPath(a.localisationId).localeCompare(locPath(b.localisationId)) || a.designation.localeCompare(b.designation));
    return `<div class="no-print"><h1>Planche de QR codes</h1>
      <p class="small muted">Un QR par équipement : scanné avec l’appareil photo du téléphone, il ouvre « Signaler » sur cet équipement. Imprimez sur étiquettes ou papier, puis plastifiez.</p>
      <p class="info">Les QR ouvrent : <b style="word-break:break-all">${esc(adressePublique())}</b> <a href="#/reglages">Modifier</a></p>
      <div class="row"><select class="grow" data-nav="#/qr?lieu=" style="flex:1"><option value="">Tous les lieux</option>${list('localisations').map(l => `<option value="${l.id}" ${l.id === lieu ? 'selected' : ''}>${esc(locPath(l.id))}</option>`).join('')}</select>
      <button class="btn primary" data-act="imprimer">Imprimer (${eqs.length})</button></div></div>
      <div class="qr-grid">${eqs.map(e => `<div class="qr-label">${QR.svg(lienSignaler(e), 132)}<div><b>${esc(e.designation)}</b><div class="small">${esc(e.code)}</div><div class="small muted">${esc(locPath(e.localisationId))}</div><div class="small">Scanner pour signaler</div></div></div>`).join('') || empty('Aucun équipement.')}</div>`;
  };

  V.plateforme = () => Sync.profil()?.adminPlateforme
    ? `<h1>Console plateforme</h1><p class="small muted">Réservée à l’administrateur plateforme. Chaque action est vérifiée par le serveur.</p>
       <div class="actions"><button class="btn primary" type="button" id="pf-creer">+ Nouvelle entreprise</button><button class="btn" type="button" id="pf-actualiser">Actualiser</button></div>
       <div id="pf-liste"><p class="muted">Chargement…</p></div>`
    : empty('Réservé à l’administrateur plateforme.');

  V.plus = () => `<h1>Plus</h1>${[['#/preventif', '↻ Préventif', 'Programmes et échéances'], ['#/qr', '▣ QR codes', 'Planche imprimable des équipements'], ['#/magasin', '▤ Magasin', 'Articles, stock, mouvements'], ['#/achats', '₪ Achats', 'Demandes d’achat, commandes, réceptions'], ['#/valeur', '∑ Valeur du stock', 'Coût moyen pondéré par article et site'], ['#/indicateurs', '▥ Indicateurs', 'Pilotage par équipement'], ['#/journal', '☰ Journal d’audit', 'Toutes les modifications'], ['#/reglages', '⚙ Réglages', 'Utilisateur, personnes, sauvegarde']]
    .concat(Sync.profil()?.adminPlateforme ? [['#/plateforme', '◆ Console plateforme', 'Clients, abonnements, démo commerciale']] : [])
    .filter(([h]) => !(h === '#/magasin' && !aModule('magasin')) && !(h === '#/preventif' && !aModule('preventif')) && !(['#/achats', '#/valeur'].includes(h) && !(aModule('achats') && App.voitCouts?.())))
    .map(([h, t, s]) => `<a class="card" href="${h}"><div class="t">${t}</div><div class="s">${s}</div></a>`).join('')}`;

  V.reglages = () => {
    const dev = Store.device();
    const swState = !('serviceWorker' in navigator) ? 'Navigateur sans mode hors ligne.'
      : !isSecureContext ? 'Mode hors ligne indisponible à cette adresse (il faut localhost ou HTTPS). Les données restent enregistrées sur l’appareil.'
        : navigator.serviceWorker.controller ? 'Actif : l’application s’ouvre sans réseau.' : 'En cours d’activation (rechargez la page une fois).';
    return `<h1>Réglages</h1>
      <h2>Cet appareil</h2><div class="card">${Sync.profil() ? `<p style="margin-top:0">Connecté : <b>${esc(Store.currentUser()?.nom || Sync.profil().nom || Sync.profil().email)}</b> · ${badge(L.role[Sync.profil().role] || Sync.profil().role, 'blue')}<br><span class="small muted">${esc(Sync.profil().email)} — identité et droits fixés par le compte.</span></p>` : `<label class="f" style="margin-top:0">Qui utilise cet appareil ?</label>
        <select data-bind="meta|device|personneId"><option value="">— Choisir —</option>${list('personnes').filter(p => p.actif !== false).map(p => `<option value="${p.id}" ${dev.personneId === p.id ? 'selected' : ''}>${esc(p.nom)} (${esc(L.role[p.role])})</option>`).join('')}</select>`}
        <p class="small muted">Version de l’appli : <b>${APP_VERSION}</b> · ${Sync.etatCourant().configure ? (Sync.etatCourant().connecte ? 'connectée au cloud' : 'cloud configuré, non connectée') : '<b>non connectée au cloud</b> (données sur cet appareil uniquement)'}<br>Code appareil : <b>${esc(dev.code)}</b> (dans les références, évite les doublons entre appareils).<br>Hors ligne : ${esc(swState)}</p></div>
      ${blocEntreprise()}
      ${blocSynchro()}
      ${Sync.profil()?.role === 'responsable' ? `<h2>Équipe et droits</h2><div class="card" id="equipe"><p class="muted small" style="margin:0">Chargement de l’équipe…</p></div>` : ''}
      <h2>Adresse de l’application</h2><div class="card"><p class="small muted" style="margin-top:0">Adresse utilisée dans les QR codes. Elle doit être accessible depuis les téléphones (HTTPS).</p>
        <input type="text" value="${esc(adressePublique())}" data-bind="meta|adresse|url" inputmode="url"></div>
      <h2>Personnes</h2><div class="card"><ul class="lines">${list('personnes').map(p => `<li><span class="grow">${esc(p.nom)} <span class="muted small">· ${esc(L.role[p.role])}${p.societe ? ' · ' + esc(p.societe) : ''}</span></span><button class="btn sm ghost" data-act="pers-edit" data-id="${p.id}">Modifier</button></li>`).join('') || '<li class="muted">Aucune personne.</li>'}</ul><button class="btn sm" data-act="pers-new">+ Personne</button></div>
      <h2>Lieux</h2><div class="card"><ul class="lines">${list('localisations').map(l => `<li><span class="grow">${esc(locPath(l.id))} <span class="muted small">· ${esc(l.code)}</span></span></li>`).join('') || '<li class="muted">Aucun lieu.</li>'}</ul><button class="btn sm" data-act="loc-new">+ Lieu</button></div>
      <h2>Sauvegarde et partage entre appareils</h2><div class="card"><p style="margin-top:0">Dernière sauvegarde : <b>${(s => s.depuis ? fmtY(s.depuis) + ` (${s.modifs} modification(s) depuis)` : 'jamais')(etatSauvegarde())}</b></p><p class="small muted">Exportez sur le téléphone, importez sur le PC (ou l’inverse) : les fiches sont fusionnées, la version la plus récente est gardée, rien n’est supprimé.</p>
        <div class="actions"><button class="btn primary" data-act="export">Exporter (JSON)</button><button class="btn" data-act="import">Importer</button><button class="btn" data-act="csv">Interventions (CSV Excel)</button></div>
        <input type="file" id="importFile" accept=".json,application/json" class="hidden"></div>
      <h2>Démonstration</h2><div class="card">${data.equipements.size ? '<p class="small muted" style="margin:0">La démo se charge uniquement sur un appareil vide.</p>' : '<button class="btn" data-act="demo">Charger la démo</button>'}</div>
      <h2>Zone sensible</h2><div class="card"><button class="btn danger" data-act="wipe">Effacer toutes les données de cet appareil</button><p class="small muted">Exportez d’abord une sauvegarde.</p></div>`;
  };

  const MODULES = { base: 'Demandes et interventions', preventif: 'Préventif', magasin: 'Magasin', rapports: 'Rapports', achats: 'Achats', energie: 'Énergie et eau', imports: 'Imports Excel' };
  function blocEntreprise() {
    const p = Sync.profil();
    if (!p?.entreprise) return '';
    const a = p.abonnement || {};
    const lim = v => v == null ? 'illimité' : v;
    return `<h2>Entreprise et abonnement</h2><div class="card"><dl class="kv">
        <dt>Entreprise</dt><dd><b>${esc(p.entreprise.nom)}</b> <span class="muted small">${esc(p.entreprise.code)}</span></dd>
        <dt>Pack</dt><dd>${esc(a.packNom || a.pack || '—')} ${a.ecriture === false ? badge('lecture seule', 'red') : badge(a.statut || 'actif', 'green')}${a.fin ? ` <span class="small muted">jusqu’au ${fmtY(a.fin)}</span>` : ''}</dd>
        <dt>Modules</dt><dd class="small">${(a.modules || []).map(m => esc(MODULES[m] || m)).join(' · ')}</dd>
        <dt>Limites</dt><dd class="small">${lim(a.maxSites)} site(s) · ${lim(a.maxUtilisateursSite)} utilisateur(s) par site · ${lim(a.maxUtilisateursTotal)} au total</dd>
        <dt>Mes sites</dt><dd>${mesSites().map(s => `${esc(s.nom)}${s.id === siteActif() ? ' ' + badge('actif', 'blue') : ''}`).join('<br>') || '—'}</dd></dl>
      ${mesSites().length > 1 ? '<button class="btn sm" data-act="site">Changer de site</button>' : ''}</div>`;
  }

  function blocSynchro() {
    const s = Sync.etatCourant();
    if (!s.configure) {
      return `<h2>Synchronisation cloud <span class="badge blue">prototype</span></h2><div class="card"><p class="small muted" style="margin-top:0">Partage les données entre tous les appareils via un serveur Supabase. L’appli continue de fonctionner hors ligne : les saisies partent dès que le réseau revient.</p>
        <div class="actions"><button class="btn primary" data-act="sync-config">Connecter ce compte</button>
        <button class="btn" data-act="sync-lien">Première connexion ou mot de passe oublié</button></div></div>`;
    }
    return `<h2>Synchronisation cloud <span class="badge blue">prototype</span></h2><div class="card" id="bloc-sync"><dl class="kv">
        <dt>Serveur</dt><dd style="word-break:break-all">${esc(s.url)}</dd>
        <dt>Compte</dt><dd>${s.connecte ? esc(s.email || '—') : '<span class="badge red">déconnecté</span>'}</dd>
        <dt>En attente d’envoi</dt><dd><b>${s.attente}</b> modification(s)</dd>
        <dt>Dernière synchro</dt><dd>${s.dernier ? fmtY(s.dernier) : 'jamais'}</dd>
        ${s.profil ? `<dt>Rôle</dt><dd>${esc(L.role[s.profil.role] || s.profil.role)}</dd>` : ''}
        ${s.erreur ? `<dt>Erreur</dt><dd class="small" style="color:var(--red)">${esc(s.erreur)}</dd>` : ''}</dl>
      ${s.refus.filter(r => r.type !== 'journal').length ? `<details class="more"><summary>Modifications refusées par le serveur (${s.refus.filter(r => r.type !== 'journal').length})</summary><ul class="lines">${s.refus.filter(r => r.type !== 'journal').map(r => `<li class="small"><span class="grow">${esc(L.entite[r.type] || r.type)} ${esc(refDe(r.type, r.id))} — ${esc(r.motif)}</span><span class="muted">${fmt(r.le)}</span></li>`).join('')}</ul></details>` : ''}
      <div class="actions">${s.connecte ? `<button class="btn primary" data-act="sync-maintenant">Synchroniser maintenant</button>` : `<button class="btn primary" data-act="sync-config">Se reconnecter</button><button class="btn" data-act="sync-lien">Mot de passe oublié</button>`}
        <button class="btn" data-act="sync-tout">Envoyer toutes les données de cet appareil</button>
        ${s.connecte ? `<button class="btn ghost" data-act="sync-deconnecter">Se déconnecter</button>` : ''}</div></div>`;
  }

  V.signaler = r => {
    const me = Store.currentUser();
    return `<h1>Signaler</h1><form id="sig" novalidate>
      <label class="f" style="margin-top:0">Équipement ou lieu</label>
      <input type="hidden" name="equipementId">
      <div id="eqpick"></div>
      <div id="dupl"></div>
      <label class="f">État constaté</label>${chipGroup('etat', L.etat, null, { colored: true, required: true })}
      <label class="f">Besoin</label>${chipGroup('besoin', L.besoin, null, { required: true })}
      <label class="f" for="constat">Constat</label><textarea id="constat" name="constat" required placeholder="Ce que vous avez observé (bruit, fuite, défaut…)"></textarea>
      <label class="f">Impact sur l’exploitation</label>${chipGroup('impact', L.impact, 'a_confirmer')}
      <label class="f">Photos <span class="opt">(facultatif)</span></label>
      <input type="file" id="photoIn" accept="image/*" class="hidden">
      <div class="thumbs" id="thumbs"></div><button type="button" class="btn sm" id="photoBtn">📷 Ajouter une photo</button>
      <details class="more"><summary>Heure du fait, demandeur</summary>
        <label class="f">Heure du fait</label>${chipGroup('quand', { maintenant: 'Maintenant', autre: 'Autre heure', inconnue: 'Inconnue' }, 'maintenant')}
        <div id="quandAutre" class="hidden"><input type="datetime-local" name="heureFait" style="margin-top:8px"><div style="margin-top:8px">${chipGroup('precisionHeure', L.precision, 'estimee')}</div></div>
        <label class="f">Origine</label>${chipGroup('origine', L.origine, 'observation')}
        <div id="tiers" class="hidden"><label class="f">Demandeur <span class="opt">(facultatif)</span></label><input type="text" name="tiersNom" placeholder="Nom"><input type="text" name="tiersService" placeholder="Service" style="margin-top:8px"></div>
      </details>
      ${me && me.role !== 'exploitation' ? `<label class="check"><input type="checkbox" name="jInterviens"> Je prends en charge et j’interviens maintenant</label>` : ''}
      <div class="sticky-save"><button class="btn primary block" type="submit">Enregistrer le signalement</button></div>
    </form>`;
  };

  // ---------- comportements après affichage ----------
  const AFTER = {};
  AFTER.reglages = async () => {
    const box = $('#equipe');
    if (!box) return;
    try {
      const [liste, u] = await Promise.all([Sync.equipe(), Sync.utilisation()]);
      const moi = Sync.profil()?.userId;
      const sitesDe = id => (u.affectations || []).filter(a => a.userId === id).map(a => (u.sites.find(s => s.id === a.siteId) || {}).nom).filter(Boolean);
      const places = (n, max) => max == null ? `${n}` : `${n} / ${max}`;
      const plein = (n, max) => max != null && n >= max;
      box.innerHTML = `<div class="tiles" style="margin-bottom:10px">
          <div class="tile ${plein(u.actifs, u.maxTotal) ? 'amber' : 'blue'}"><b>${places(u.actifs, u.maxTotal)}</b><span>Utilisateurs actifs</span></div>
          ${u.sites.map(s => `<div class="tile ${plein(s.actifs, u.maxSite) ? 'amber' : ''}"><b>${places(s.actifs, u.maxSite)}</b><span>${esc(s.nom)}</span></div>`).join('')}</div>
        <div class="actions" style="margin-top:0"><button class="btn primary" type="button" id="inviter" ${plein(u.actifs, u.maxTotal) ? 'disabled title="Plus de place dans le pack"' : ''}>+ Inviter un membre</button></div>
        ${plein(u.actifs, u.maxTotal) ? '<p class="warn small">Toutes les places du pack sont prises : désactivez un compte ou changez de pack.</p>' : ''}
        <ul class="lines">${liste.map(p => `<li style="flex-wrap:wrap"><span class="grow"><b>${esc(p.nom || p.email)}</b>${p.actif ? '' : ' ' + badge('désactivé', 'red')}<br><span class="small muted">${esc(p.email)}</span><br><span class="small">📍 ${esc(sitesDe(p.user_id).join(', ') || 'aucun site')}</span></span>
          <select data-profil="${p.user_id}" ${p.user_id === moi ? 'disabled title="Votre propre rôle"' : ''} style="width:auto;min-height:38px">${['responsable', 'technicien', 'prestataire', 'magasinier', 'exploitation', 'pilote'].map(r => `<option value="${r}" ${p.role === r ? 'selected' : ''}>${L.role[r]}</option>`).join('')}</select>
          ${p.user_id === moi ? '' : `<button class="btn sm ghost" data-sites="${p.user_id}">Sites</button><button class="btn sm ghost" data-equipe="${p.user_id}" data-nom="${esc(p.nom || '')}" data-role="${p.role}" data-actif="${p.actif}">Modifier</button>`}</li>`).join('')}</ul>
        <p class="small muted">Les limites du pack sont vérifiées par le serveur à chaque invitation, activation ou affectation de site. Désactiver un compte libère sa place.</p>`;
      const optsSites = Object.fromEntries(u.sites.map(s => [s.id, `${s.nom} (${places(s.actifs, u.maxSite)})`]));
      $('#inviter')?.addEventListener('click', async () => {
        const v = await askForm({ title: 'Inviter un membre', ok: 'Envoyer l’invitation', values: { role: 'technicien', sites: siteActif() && siteActif() !== 'tous' ? [siteActif()] : [] }, fields: [
          { name: 'email', label: 'E-mail', type: 'email', required: true },
          { name: 'nom', label: 'Nom affiché', type: 'text' },
          { name: 'role', label: 'Rôle', type: 'chips', options: L.role, required: true },
          { name: 'sites', label: 'Sites', type: 'chipsMulti', options: optsSites },
          { type: 'info', text: 'La personne reçoit un e-mail, choisit son mot de passe et arrive directement dans l’appli, sur ses sites.' }] });
        if (!v) return;
        if (!v.sites.length) { toast('Choisissez au moins un site'); return; }
        try {
          toast('Envoi de l’invitation…');
          const rep = await Sync.inviter({ ...v, redirectTo: adressePublique() });
          await alertBox('Invitation', [rep.emailEnvoye ? `E-mail envoyé à ${v.email}.` : `${v.email} avait déjà un compte : il est maintenant rattaché à l’équipe (connexion avec son mot de passe, ou « mot de passe oublié »).`]);
        } catch (e) { await alertBox('Invitation refusée', [e.message]); }
        AFTER.reglages();
      });
      box.querySelectorAll('[data-sites]').forEach(b => b.onclick = async () => {
        const actuels = (u.affectations || []).filter(a => a.userId === b.dataset.sites).map(a => a.siteId);
        const v = await askForm({ title: 'Sites du membre', values: { sites: actuels }, fields: [{ name: 'sites', label: 'Sites autorisés', type: 'chipsMulti', options: optsSites }] });
        if (!v) return;
        try { await Sync.affecterSites(b.dataset.sites, v.sites); toast('Sites mis à jour'); } catch (e) { await alertBox('Affectation refusée', [e.message]); }
        AFTER.reglages();
      });
      box.querySelectorAll('[data-profil]').forEach(sel => sel.onchange = async () => {
        const p = liste.find(x => x.user_id === sel.dataset.profil);
        try { await Sync.definirProfil(p.user_id, sel.value, p.nom, p.actif); toast('Rôle mis à jour'); Sync.planifier(200); } catch (e) { toast('Échec : ' + e.message); }
        AFTER.reglages();
      });
      box.querySelectorAll('[data-equipe]').forEach(b => b.onclick = async () => {
        const v = await askForm({ title: 'Membre de l’équipe', values: { nom: b.dataset.nom, actif: b.dataset.actif === 'true' }, fields: [
          { name: 'nom', label: 'Nom affiché', type: 'text', required: true },
          { name: 'actif', label: 'Compte actif (décocher pour retirer l’accès)', type: 'checkbox' }] });
        if (!v) return;
        try { await Sync.definirProfil(b.dataset.equipe, b.dataset.role, v.nom, v.actif); toast('Membre mis à jour'); Sync.planifier(200); } catch (e) { await alertBox('Modification refusée', [e.message]); }
        AFTER.reglages();
      });
    } catch (e) { box.innerHTML = `<p class="warn" style="margin:0">Équipe indisponible : ${esc(e.message)}</p>`; }
  };
  const PACKS = { essentiel: 'Essentiel', pro: 'Pro', entreprise: 'Entreprise' };
  const STATUTS_ABO = { essai: 'Essai', actif: 'Actif', suspendu: 'Suspendu', resilie: 'Résilié' };
  AFTER.plateforme = async () => {
    const box = $('#pf-liste');
    if (!box) return;
    const recharger = () => AFTER.plateforme();
    $('#pf-actualiser').onclick = recharger;
    $('#pf-creer').onclick = async () => {
      const v = await askForm({ title: 'Nouvelle entreprise cliente', ok: 'Créer', values: { pack: 'essentiel', statut: 'essai', siteCode: 'S1' }, fields: [
        { name: 'nom', label: 'Nom de l’entreprise', type: 'text', required: true },
        { name: 'code', label: 'Code (majuscules, ex. ACME)', type: 'text', required: true },
        { name: 'pack', label: 'Pack', type: 'chips', options: PACKS, required: true },
        { name: 'statut', label: 'Statut', type: 'chips', options: { essai: 'Essai', actif: 'Actif' }, required: true },
        { name: 'siteNom', label: 'Premier site', type: 'text', required: true, placeholder: 'ex. Usine de Tanger' },
        { name: 'siteCode', label: 'Code du site', type: 'text', required: true },
        { name: 'email', label: 'E-mail du responsable à inviter', type: 'email' },
        { name: 'demo', label: 'Entreprise de démonstration (réinitialisable)', type: 'checkbox' }] });
      if (!v) return;
      try {
        const r = await Sync.pf.creer(v);
        let msg = `Entreprise « ${v.nom} » créée avec le site « ${v.siteNom} ».`;
        if (v.demo) { await Sync.pf.reinitialiserDemo(r.entrepriseId); msg += ' Données de démonstration chargées.'; }
        if (v.email) {
          try { await Sync.inviter({ email: v.email, role: 'responsable', sites: [r.siteId], entrepriseId: r.entrepriseId, redirectTo: adressePublique() }); msg += ` Invitation envoyée à ${v.email}.`; }
          catch (e) { msg += ` Invitation non envoyée : ${e.message}`; }
        }
        await alertBox('Nouvelle entreprise', [msg]);
      } catch (e) { await alertBox('Création refusée', [e.message]); }
      recharger();
    };
    try {
      const liste = await Sync.pf.entreprises();
      const lim = v => v == null ? '∞' : v;
      box.innerHTML = liste.map(e => {
        const a = e.abonnement || {};
        const badgeStatut = badge(STATUTS_ABO[a.statut] || a.statut || '—', { actif: 'green', essai: 'blue', suspendu: 'red', resilie: 'red' }[a.statut] || '');
        return `<div class="card"><div class="row"><span class="t grow">${esc(e.nom)} <span class="muted small">${esc(e.code)}</span></span>${e.demo ? badge('démo', 'amber') : ''}${badge(a.packNom || a.pack || '—', 'blue')}${badgeStatut}</div>
          <dl class="kv small" style="margin-top:8px">
            <dt>Utilisateurs</dt><dd>${e.actifs} / ${lim(a.maxUtilisateursTotal)} actifs · responsables : ${esc((e.responsables || []).join(', ') || 'aucun')}</dd>
            <dt>Sites</dt><dd>${(e.sites || []).map(s => `${esc(s.nom)} (${s.actifs} / ${lim(a.maxUtilisateursSite)})`).join(' · ') || '—'} — max ${lim(a.maxSites)}</dd>
            <dt>Données</dt><dd>${e.fiches} fiches · ${e.photos} photos · dernière activité ${e.derniereActivite ? fmtY(String(e.derniereActivite).slice(0, 16).replace(' ', 'T')) : '—'}</dd>
            ${a.fin ? `<dt>Échéance</dt><dd>${fmtY(a.fin)}</dd>` : ''}
            ${Object.values(e.derogations || {}).some(x => x != null) ? `<dt>Dérogations</dt><dd>${esc(JSON.stringify(e.derogations))}</dd>` : ''}
          </dl>
          <div class="actions" style="margin-bottom:0">
            <button class="btn sm" data-pf="abo" data-id="${e.id}">Abonnement</button>
            <button class="btn sm" data-pf="site" data-id="${e.id}">+ Site</button>
            <button class="btn sm" data-pf="inviter" data-id="${e.id}">Inviter un responsable</button>
            ${e.demo ? `<button class="btn sm danger" data-pf="reinit" data-id="${e.id}">Réinitialiser la démo</button>` : ''}</div></div>`;
      }).join('') || empty('Aucune entreprise.');
      box.querySelectorAll('[data-pf]').forEach(b => b.onclick = async () => {
        const e = liste.find(x => x.id === b.dataset.id), a = e.abonnement || {}, d = e.derogations || {};
        try {
          if (b.dataset.pf === 'abo') {
            const v = await askForm({ title: `Abonnement — ${e.nom}`, values: { pack: a.pack, statut: a.statut, fin: a.fin, ...d }, fields: [
              { name: 'pack', label: 'Pack', type: 'chips', options: PACKS, required: true },
              { name: 'statut', label: 'Statut', type: 'chips', options: STATUTS_ABO, required: true },
              { name: 'fin', label: 'Échéance', type: 'date' },
              { type: 'info', text: 'Dérogations : laisser vide pour appliquer les limites du pack.' },
              { name: 'maxSites', label: 'Sites maximum', type: 'number' },
              { name: 'maxUtilisateursSite', label: 'Utilisateurs maximum par site', type: 'number' },
              { name: 'maxUtilisateursTotal', label: 'Utilisateurs maximum au total', type: 'number' }] });
            if (!v) return;
            await Sync.pf.abonnement(e.id, v); toast('Abonnement mis à jour');
          } else if (b.dataset.pf === 'site') {
            const v = await askForm({ title: `Nouveau site — ${e.nom}`, fields: [{ name: 'nom', label: 'Nom', type: 'text', required: true }, { name: 'code', label: 'Code', type: 'text', required: true }] });
            if (!v) return;
            await Sync.pf.ajouterSite(e.id, v.code, v.nom); toast('Site ajouté');
          } else if (b.dataset.pf === 'inviter') {
            const v = await askForm({ title: `Inviter un responsable — ${e.nom}`, ok: 'Envoyer l’invitation', fields: [
              { name: 'email', label: 'E-mail', type: 'email', required: true }, { name: 'nom', label: 'Nom affiché', type: 'text' },
              { name: 'sites', label: 'Sites', type: 'chipsMulti', options: Object.fromEntries((e.sites || []).filter(s => s.actif).map(s => [s.id, s.nom])) }] });
            if (!v) return;
            if (!v.sites.length) { toast('Choisissez au moins un site'); return; }
            const r = await Sync.inviter({ ...v, role: 'responsable', entrepriseId: e.id, redirectTo: adressePublique() });
            await alertBox('Invitation', [r.emailEnvoye ? `E-mail envoyé à ${v.email}.` : `${v.email} est rattaché comme responsable.`]);
          } else if (b.dataset.pf === 'reinit') {
            if (!(await askConfirm('Réinitialiser la démo', `Toutes les données de « ${e.nom} » seront remplacées par le jeu de démonstration. Les appareils connectés à cette démo se resynchroniseront d’eux-mêmes.`, 'Réinitialiser'))) return;
            const r = await Sync.pf.reinitialiserDemo(e.id); toast(`Démo réinitialisée (${r.fiches} fiches)`);
          }
        } catch (err) { await alertBox('Action refusée', [err.message]); }
        recharger();
      });
    } catch (e) { box.innerHTML = `<p class="warn">Console indisponible : ${esc(e.message)}</p>`; }
  };
  AFTER.signaler = r => {
    const form = $('#sig');
    const pick = id => {
      const e = eq(id);
      form.equipementId.value = id || '';
      if (e) {
        $('#eqpick').innerHTML = `<div class="picked"><span class="dot ${etatEquipement(e.id)}"></span><div class="grow"><b>${esc(e.designation)}</b><div class="small muted">${esc(e.code)} · ${esc(locPath(e.localisationId))}</div></div><button type="button" class="btn sm ghost" id="eqchange">Changer</button></div>`;
        $('#eqchange').onclick = () => pick(null);
        const ouv = list('demandes').filter(d => d.equipementId === id && demandeOuverte(d));
        $('#dupl').innerHTML = ouv.length ? `<p class="warn">Déjà signalé sur cet équipement : ${ouv.map(d => `<a href="#/demande/${d.id}">${esc(d.ref)}</a> (${esc(trunc(d.constat, 40))})`).join(', ')}. Vérifiez qu’il ne s’agit pas du même fait.</p>` : '';
      } else {
        const canScan = 'BarcodeDetector' in window && isSecureContext && navigator.mediaDevices;
        $('#eqpick').innerHTML = `<div class="row"><input type="search" id="eqsearch" class="grow" placeholder="Code ou nom (ex. PRESSE)" autocomplete="off" style="flex:1">${canScan ? '<button type="button" class="btn" id="scan">QR</button>' : ''}</div><div class="picker-results" id="eqres"></div>`;
        $('#dupl').innerHTML = '';
        const s = $('#eqsearch');
        const show = () => {
          const q = s.value.trim().toLowerCase();
          const res = list('equipements').filter(e => e.actif !== false && (!q || (e.code + ' ' + e.designation + ' ' + locPath(e.localisationId)).toLowerCase().includes(q))).slice(0, 8);
          $('#eqres').innerHTML = res.map(e => `<button type="button" data-pick="${e.id}"><b>${esc(e.designation)}</b> <span class="muted small">${esc(e.code)} · ${esc(locPath(e.localisationId))}</span></button>`).join('') || '<p class="muted small">Aucun équipement trouvé.</p>';
        };
        s.oninput = show; show();
        $('#eqres').onclick = ev => { const b = ev.target.closest('[data-pick]'); if (b) pick(b.dataset.pick); };
        if (canScan) $('#scan').onclick = async () => { const code = await scanQR(); if (!code) return; const e = byCode(code); e ? pick(e.id) : toast('QR non reconnu : ' + code); };
      }
    };
    const photos = [];
    const showThumbs = () => {
      $('#thumbs').innerHTML = photos.map((u, i) => `<button type="button" data-rm="${i}" title="Retirer"><img src="${u}" alt="Photo ${i + 1}"><span class="rm">×</span></button>`).join('');
      $('#photoBtn').classList.toggle('hidden', photos.length >= 4);
    };
    $('#photoBtn').onclick = () => $('#photoIn').click();
    $('#photoIn').onchange = async ev => {
      const f = ev.target.files[0]; ev.target.value = '';
      if (!f) return;
      try { photos.push(await compresserPhoto(f)); showThumbs(); } catch { toast('Image illisible'); }
    };
    $('#thumbs').onclick = ev => { const b = ev.target.closest('[data-rm]'); if (b) { photos.splice(Number(b.dataset.rm), 1); showThumbs(); } };
    const pre = r.q.get('eq'); const preE = pre && byCode(pre);
    pick(preE ? preE.id : null);
    if (pre && !preE) $('#dupl').innerHTML = `<p class="warn">Le QR désigne l’équipement <b>${esc(pre)}</b>, inconnu sur cet appareil. Les données ne sont pas encore partagées entre appareils : importez une sauvegarde du PC (Réglages → Importer), ou choisissez l’équipement ci-dessus.</p>`;
    form.addEventListener('change', () => {
      $('#quandAutre').classList.toggle('hidden', form.quand.value !== 'autre');
      $('#tiers').classList.toggle('hidden', form.origine.value !== 'tiers');
    });
    form.addEventListener('submit', async ev => {
      ev.preventDefault();
      const v = Object.fromEntries(new FormData(form).entries());
      const miss = [];
      if (!v.equipementId) miss.push('l’équipement');
      if (!v.etat) miss.push('l’état');
      if (!v.besoin) miss.push('le besoin');
      if (!(v.constat || '').trim()) miss.push('le constat');
      if (v.quand === 'autre' && !v.heureFait) miss.push('l’heure du fait');
      if (miss.length) { toast('À renseigner : ' + miss.join(', ')); return; }
      const me = Store.currentUser();
      const now = Store.now();
      const heureFait = v.quand === 'maintenant' ? now : v.quand === 'autre' ? v.heureFait : null;
      const d = {
        id: Store.uid(), ref: await Store.nextRef('DEM'), origine: v.origine, equipementId: v.equipementId, besoin: v.besoin,
        constat: v.constat.trim(), etat: v.etat, impact: v.impact || 'a_confirmer', heureFait,
        precisionHeure: v.quand === 'maintenant' ? 'exacte' : v.quand === 'autre' ? v.precisionHeure : 'inconnue',
        tiers: v.origine === 'tiers' && (v.tiersNom || v.tiersService) ? { nom: v.tiersNom || null, service: v.tiersService || null } : null,
        statut: 'a_examiner', priseEnChargePar: null, priseEnChargeLe: null, motifClassement: null,
      };
      if (v.jInterviens && me) Object.assign(d, { statut: 'prise_en_charge', priseEnChargePar: me.id, priseEnChargeLe: now });
      await Store.save('demandes', d);
      for (const u of photos) await Store.save('photos', { id: Store.uid(), parentType: 'demandes', parentId: d.id, dataUrl: u, le: now });
      if (v.jInterviens && me) {
        const o = await otDepuisDemande(d, true);
        toast(`${d.ref} enregistrée · ${o.ref} démarrée`);
        location.hash = '#/ot/' + o.id;
      } else {
        toast(`${d.ref} enregistrée sur l’appareil`);
        location.hash = '#/demande/' + d.id;
      }
    });
  };
  function byCode(raw) {
    let code = raw;
    const m = /[?&]eq=([^&#]+)/.exec(raw); if (m) code = decodeURIComponent(m[1]);
    // Tous les sites de l'appareil : un QR scanné ailleurs que sur le site affiché reste reconnu.
    return [...data.equipements.values()].find(e => e.code.toLowerCase() === code.trim().toLowerCase());
  }
  function scanQR() {
    return new Promise(resolve => {
      const d = document.createElement('dialog'); d.className = 'sheet';
      d.innerHTML = `<form method="dialog"><h3>Scanner le QR code</h3><video class="scan" playsinline muted></video><div class="sheet-actions"><button class="btn">Fermer</button></div></form>`;
      document.body.append(d);
      let stream = null, done = false, result = null;
      d.addEventListener('close', () => { done = true; stream?.getTracks().forEach(t => t.stop()); d.remove(); resolve(result); });
      d.showModal();
      (async () => {
        try {
          const v = d.querySelector('video');
          stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
          v.srcObject = stream; await v.play();
          const det = new BarcodeDetector({ formats: ['qr_code'] });
          const loop = async () => { if (done) return; try { const c = await det.detect(v); if (c.length) { result = c[0].rawValue; d.close(); return; } } catch { /* image pas prête */ } requestAnimationFrame(loop); };
          loop();
        } catch { toast('Caméra indisponible'); d.close(); }
      })();
    });
  }

  // ---------- actions ----------
  const personnesOpts = () => list('personnes').filter(p => p.actif !== false).map(p => [p.id, `${p.nom} (${L.role[p.role]})`]);
  const A = {};

  A.site = async () => {
    const sites = mesSites();
    if (sites.length < 2) { toast(sites[0] ? `Site : ${sites[0].nom}` : 'Aucun site'); return; }
    const opts = Object.fromEntries([...sites.map(s => [s.id, s.nom]), ['tous', 'Tous mes sites']]);
    const v = await askForm({ title: 'Site affiché', ok: 'Afficher', values: { s: siteActif() }, fields: [
      { name: 's', label: 'Site', type: 'chips', options: opts, required: true },
      { type: 'info', text: 'Accueil, listes et indicateurs se limitent à ce site. Les nouvelles fiches prennent le site de leur équipement, sinon ce site.' }] });
    if (!v) return;
    await Store.persistMeta({ ...Store.device(), siteActif: v.s });
    render();
  };
  A.who = async () => {
    if (Sync.profil()) { location.hash = '#/reglages'; return; }
    const v = await askForm({ title: 'Qui utilise cet appareil ?', ok: 'Valider', values: { p: Store.device().personneId }, fields: [
      { name: 'p', label: 'Personne', type: 'select', options: personnesOpts(), empty: '— Choisir —' },
      { name: 'nom', label: 'Ou nouvelle personne : nom', type: 'text' },
      { name: 'role', label: 'Rôle (nouvelle personne)', type: 'chips', options: L.role, default: 'technicien' }] });
    if (!v) return;
    let id = v.p;
    if (v.nom) { const p = { id: Store.uid(), nom: v.nom, role: v.role || 'technicien', actif: true }; await Store.save('personnes', p); id = p.id; }
    await Store.persistMeta({ ...Store.device(), personneId: id || null });
    render();
  };

  A['dem-pec'] = async el => {
    const me = Store.currentUser();
    if (!me) { toast('Choisissez d’abord qui utilise cet appareil'); return A.who(); }
    await edit('demandes', el.dataset.id, { statut: 'prise_en_charge', priseEnChargePar: me.id, priseEnChargeLe: Store.now() }, { action: 'prise_en_charge' });
    toast('Prise en charge enregistrée');
  };
  A['dem-ot'] = async el => {
    const d = data.demandes.get(el.dataset.id);
    const v = await askForm({ title: 'Créer l’intervention', ok: 'Créer', fields: [{ name: 'go', label: 'Je démarre maintenant', type: 'checkbox' }] });
    if (!v) return;
    const o = await otDepuisDemande(d, v.go);
    location.hash = '#/ot/' + o.id;
  };
  A['dem-classer'] = async el => {
    const m = await askText('Classer sans travail', 'Motif (doublon de…, pas de défaut constaté…)');
    if (m) await edit('demandes', el.dataset.id, { statut: 'close_sans_travail', motifClassement: m }, { motif: m, action: 'classement' });
  };
  A['dem-annuler'] = async el => {
    const m = await askText('Annuler la demande', 'Motif de l’annulation');
    if (m) await edit('demandes', el.dataset.id, { statut: 'annulee', motifClassement: m }, { motif: m, action: 'annulation' });
  };
  A['dem-edit'] = async el => {
    const d = data.demandes.get(el.dataset.id);
    const v = await askForm({ title: 'Compléter / corriger', values: { ...d, motif: null }, fields: [
      { name: 'etat', label: 'État', type: 'chips', options: L.etat, required: true },
      { name: 'impact', label: 'Impact', type: 'chips', options: L.impact, required: true },
      { name: 'constat', label: 'Constat', type: 'textarea', required: true },
      { name: 'heureFait', label: 'Heure du fait', type: 'datetime-local' },
      { name: 'precisionHeure', label: 'Précision de l’heure', type: 'chips', options: { ...L.precision, inconnue: 'Inconnue' } },
      { name: 'motif', label: 'Motif de la correction', type: 'text' }] });
    if (!v) return;
    const { motif, ...patch } = v;
    if (!patch.heureFait) patch.precisionHeure = 'inconnue';
    await edit('demandes', d.id, patch, { motif });
  };

  A['ot-new'] = async () => {
    const v = await askForm({ title: 'Nouvelle intervention', ok: 'Créer', fields: [
      { name: 'equipementId', label: 'Équipement', type: 'select', required: true, empty: '— Choisir —', options: list('equipements').filter(e => e.actif !== false).map(e => [e.id, `${e.designation} (${e.code})`]) },
      { name: 'nature', label: 'Nature', type: 'chips', options: L.nature, default: 'a_qualifier', required: true },
      { name: 'travaux', label: 'Objet du travail', type: 'textarea' }] });
    if (!v) return;
    const o = await newOT({ ...v, intervenants: moiIntervenant('coordinateur') });
    location.hash = '#/ot/' + o.id;
  };
  A['ot-demarrer'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const me = Store.currentUser();
    const intervenants = actifs(o).length || !me ? o.intervenants : [...o.intervenants, ...moiIntervenant()];
    await edit('ots', o.id, { statut: 'en_cours', intervenants }, { action: 'demarrage' });
  };
  A['ot-planifier'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const v = await askForm({ title: 'Planifier', values: o, fields: [{ name: 'creneau', label: 'Créneau prévu', type: 'datetime-local', required: true }] });
    if (v) await edit('ots', o.id, { creneau: v.creneau }, { action: 'planification' });
  };
  A['ot-annuler'] = async el => {
    const m = await askText('Annuler l’intervention', 'Motif');
    if (m) await edit('ots', el.dataset.id, { statut: 'annulee' }, { motif: m, action: 'annulation' });
  };
  A['ot-suspendre'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const v = await askForm({ title: 'Mettre en attente', fields: [
      { name: 'motif', label: 'Motif', type: 'chips', options: L.attente, required: true },
      { name: 'detail', label: 'Précision', type: 'text', placeholder: 'ex. joint Ø80 commandé' },
      { name: 'responsableId', label: 'Qui lève l’attente ?', type: 'select', options: personnesOpts(), empty: '—' }] });
    if (!v) return;
    await edit('ots', o.id, { statut: 'suspendue', attentes: [...(o.attentes || []), { id: Store.uid(), ...v, depuis: Store.now(), fin: null }] }, { action: 'mise_en_attente' });
  };
  const fermerAttentes = o => (o.attentes || []).map(a => a.fin ? a : { ...a, fin: Store.now() });
  A['ot-reprendre'] = async el => {
    const o = data.ots.get(el.dataset.id);
    await edit('ots', o.id, { statut: 'en_cours', attentes: fermerAttentes(o) }, { action: 'reprise' });
  };
  A['ot-terminer'] = async el => edit('ots', el.dataset.id, { statut: 'travail_termine' }, { action: 'travail_termine' });
  A['ot-cloturer'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const err = Calculs.verifierCloture(o);
    if (err.length) { await alertBox('Avant de clôturer', err.map(e => '• ' + e)); return; }
    const enMain = Calculs.piecesDetenues(besoinsDe(o), [...data.mouvements.values()], o.pieces);
    if (enMain.length && !(await askConfirm('Pièces encore en main', `${enMain.map(r => r.detenu + ' × ' + desigBesoin(r.besoin)).join(' ; ')} : remises mais ni déclarées utilisées ni rendues. Clôturer quand même ? L’écart restera visible au magasin.`, 'Clôturer quand même'))) return;
    const me = Store.currentUserName(), now = Store.now();
    await Store.save('ots', { ...o, statut: 'cloturee', clotureLe: now, cloturePar: me, attentes: fermerAttentes(o) }, { action: 'cloture' });
    if (o.programmeId) {
      const p = data.programmes.get(o.programmeId);
      if (p && p.prochaineEcheance === o.echeance) {
        await Store.update('programmes', p.id, { prochaineEcheance: Calculs.echeanceSuivante(p, o.echeance, now), derniereRealisation: now }, { action: 'echeance_suivante' });
      }
    }
    toast(`${o.ref} clôturée`);
    render();
  };
  A['ot-rouvrir'] = async el => {
    const m = await askText('Rouvrir l’intervention', 'Motif de la réouverture');
    if (m) await edit('ots', el.dataset.id, { statut: 'en_cours', clotureLe: null, cloturePar: null }, { motif: m, action: 'reouverture' });
  };
  A['ot-ajout-int'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const v = await askForm({ title: 'Ajouter un intervenant', ok: 'Ajouter', fields: [
      { name: 'personneId', label: 'Personne', type: 'select', options: personnesOpts(), empty: '— Choisir —' },
      ...(estResp() ? [{ name: 'nom', label: 'Ou nom d’un prestataire / renfort', type: 'text' }] : []),
      { name: 'role', label: 'Rôle', type: 'chips', options: L.roleOT, default: 'intervenant', required: true }] });
    if (!v || (!v.personneId && !v.nom)) return;
    let pid = v.personneId;
    if (!pid) { const p = { id: Store.uid(), nom: v.nom, role: v.role === 'prestataire' ? 'prestataire' : 'technicien', actif: true }; await Store.save('personnes', p); pid = p.id; }
    await edit('ots', o.id, { intervenants: [...(o.intervenants || []), { id: Store.uid(), personneId: pid, role: v.role, depuis: Store.now(), fin: null, par: Store.currentUserName() }] }, { action: 'affectation' });
  };
  A['ot-retirer'] = async el => {
    const o = data.ots.get(el.dataset.id);
    await edit('ots', o.id, { intervenants: o.intervenants.map(i => i.id === el.dataset.sub ? { ...i, fin: Store.now() } : i) }, { action: 'fin_affectation' });
  };
  A['ot-ajout-piece'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const v = await askForm({ title: 'Pièce hors stock utilisée', ok: 'Ajouter', values: { qte: 1 }, fields: [
      { type: 'info', text: 'Pour une pièce du magasin : « Demander une pièce » ou « Retrait urgent ».' },
      { name: 'libelle', label: 'Désignation', type: 'text', required: true },
      { name: 'qte', label: 'Quantité', type: 'number', required: true }] });
    if (!v || !(v.qte > 0) || !v.libelle) return;
    await edit('ots', o.id, { pieces: [...(o.pieces || []), { id: Store.uid(), articleId: null, libelle: v.libelle, qte: v.qte, mouvementId: null, annulee: false }] }, { action: 'piece' });
  };
  A['ot-annuler-piece'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const p = o.pieces.find(x => x.id === el.dataset.sub);
    const nom = p.articleId ? data.articles.get(p.articleId)?.designation : p.libelle;
    const retour = p.articleId && !p.besoinId; // pièce ancienne sortie directement : on la remet en stock
    if (!(await askConfirm(retour ? 'Retour de pièce' : 'Annuler la déclaration', retour ? `Retourner ${p.qte} × ${nom} ? Un mouvement de retour est créé (l’historique est conservé).`
      : `Annuler « ${p.qte} × ${nom} utilisée » ? ${p.besoinId ? 'La pièce redevient « en main » : vous pourrez la rendre au magasin.' : ''}`))) return;
    if (retour) await Store.save('mouvements', { id: Store.uid(), articleId: p.articleId, type: 'retour', qte: Number(p.qte), otId: o.id, le: Store.now(), motif: 'Retour depuis ' + o.ref });
    await edit('ots', o.id, { pieces: o.pieces.map(x => x.id === p.id ? { ...x, annulee: true } : x) }, { action: 'retour_piece' });
  };
  A['bes-new'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const enAttente = o.statut === 'suspendue';
    const v = await askForm({ title: 'Demander une pièce', ok: 'Demander', values: { qte: 1 }, fields: [
      { name: 'articleId', label: 'Article du magasin', type: 'select', empty: '— Hors catalogue —', options: optsArticles(o.siteId) },
      { name: 'description', label: 'Description (si hors catalogue)', type: 'text', placeholder: 'ex. roulement 6204 ou équivalent' },
      { name: 'qte', label: 'Quantité', type: 'number', required: true },
      { name: 'urgent', label: 'Urgent', type: 'checkbox' },
      { name: 'note', label: 'Précision pour le magasin', type: 'text' },
      ...(enAttente ? [] : [{ name: 'attente', label: 'Mettre l’intervention en attente de cette pièce', type: 'checkbox' }])] });
    if (!v || !(v.qte > 0)) return;
    if (!v.articleId && !v.description) { toast('Choisissez un article ou décrivez la pièce'); return; }
    const art = v.articleId ? data.articles.get(v.articleId) : null;
    // Pas de qteReservee ni de délai : la réservation appartient au magasin.
    const b = { id: Store.uid(), ref: await Store.nextRef('BES'), otId: o.id, equipementId: o.equipementId, articleId: v.articleId, description: art ? null : v.description,
      qte: v.qte, unite: art?.unite || null, urgent: !!v.urgent, note: v.note, statut: 'demande', demandeur: Store.currentUserName(), demandeLe: Store.now() };
    await Store.save('besoins', b, { action: 'demande_piece' });
    if (v.attente) await edit('ots', o.id, { statut: 'suspendue', attentes: [...(o.attentes || []), { id: Store.uid(), motif: 'piece', besoinId: b.id, detail: desigBesoin(b), depuis: Store.now(), fin: null, responsableId: null }] }, { action: 'mise_en_attente', render: false });
    toast('Demande transmise au magasin' + (v.attente ? ' · intervention en attente' : ''));
    render();
  };
  /** Retrait urgent : le technicien prend la pièce lui-même. Vaut remise, marqué « à vérifier » par le magasin. */
  A['bes-urgent'] = async el => {
    const o = data.ots.get(el.dataset.id);
    let b = el.dataset.sub ? data.besoins.get(el.dataset.sub) : null;
    const mvts = [...data.mouvements.values()];
    const reste = b ? Math.max(1, Number(b.qte) - Calculs.qteRemise(mvts, b.id)) : 1;
    const v = await askForm({ title: 'Retrait urgent', ok: 'J’ai pris la pièce', values: { qte: reste }, fields: [
      { type: 'info', cls: 'warn', text: 'Vous prenez la pièce vous-même : le stock est débité et le magasin vérifiera ce retrait.' },
      ...(b ? [{ type: 'info', text: `${desigBesoin(b)} · disponible ${dispo(b.articleId, o.siteId)}` }] : [{ name: 'articleId', label: 'Article', type: 'select', required: true, empty: '— Choisir —', options: optsArticles(o.siteId) }]),
      { name: 'qte', label: 'Quantité prise', type: 'number', required: true },
      { name: 'monte', label: 'Pièce déjà montée (utilisée)', type: 'checkbox' }] });
    if (!v || !(v.qte > 0)) return;
    if (!b) {
      if (!v.articleId) return;
      const art = data.articles.get(v.articleId);
      b = { id: Store.uid(), ref: await Store.nextRef('BES'), otId: o.id, equipementId: o.equipementId, articleId: v.articleId, description: null,
        qte: v.qte, unite: art?.unite || null, urgent: true, note: 'Retrait urgent', statut: 'demande', demandeur: Store.currentUserName(), demandeLe: Store.now() };
      await Store.save('besoins', b, { action: 'demande_piece' });
    }
    await Store.save('mouvements', { id: Store.uid(), articleId: b.articleId, type: 'remise', qte: -v.qte, urgent: true, aVerifier: true, besoinId: b.id, otId: o.id, le: Store.now(), motif: 'Retrait urgent ' + o.ref }, { action: 'retrait_urgent' });
    if (v.monte) await edit('ots', o.id, { pieces: [...(data.ots.get(o.id).pieces || []), { id: Store.uid(), besoinId: b.id, articleId: b.articleId, libelle: null, qte: v.qte, mouvementId: null, annulee: false }] }, { action: 'utilisation_piece', render: false });
    toast('Retrait enregistré · à vérifier par le magasin');
    await leverAttentesPieces();
    render();
  };
  A['bes-utilise'] = async el => {
    const o = data.ots.get(el.dataset.id), b = data.besoins.get(el.dataset.sub);
    const r = Calculs.rapprochementBesoin(b, [...data.mouvements.values()], o.pieces);
    const v = await askForm({ title: 'J’ai utilisé', ok: 'Déclarer', values: { qte: r.detenu }, fields: [
      { type: 'info', text: `${desigBesoin(b)} · en main : ${r.detenu}` }, { name: 'qte', label: 'Quantité montée', type: 'number', required: true }] });
    if (!v || !(v.qte > 0)) return;
    if (v.qte > r.detenu) { toast(`Au plus ${r.detenu} : quantité remise et pas encore déclarée`); return; }
    await edit('ots', o.id, { pieces: [...(o.pieces || []), { id: Store.uid(), besoinId: b.id, articleId: b.articleId, libelle: b.articleId ? null : b.description, qte: v.qte, mouvementId: null, annulee: false }] }, { action: 'utilisation_piece' });
  };
  A['bes-rendre'] = async el => {
    const o = data.ots.get(el.dataset.id), b = data.besoins.get(el.dataset.sub);
    const r = Calculs.rapprochementBesoin(b, [...data.mouvements.values()], o.pieces);
    if (!b.articleId) { toast('Pièce hors catalogue : voir avec le magasin'); return; }
    const v = await askForm({ title: 'Je rends au magasin', ok: 'Rendre', values: { qte: r.detenu }, fields: [
      { type: 'info', text: `${desigBesoin(b)} · en main : ${r.detenu}` }, { name: 'qte', label: 'Quantité rendue', type: 'number', required: true }] });
    if (!v || !(v.qte > 0)) return;
    if (v.qte > r.detenu) { toast(`Au plus ${r.detenu}`); return; }
    await Store.save('mouvements', { id: Store.uid(), articleId: b.articleId, type: 'retour', qte: v.qte, besoinId: b.id, otId: o.id, le: Store.now(), motif: 'Retour depuis ' + o.ref }, { action: 'retour_piece' });
    toast('Retour enregistré : stock remis à jour');
    render();
  };
  A['bes-annuler'] = async el => {
    const o = data.ots.get(el.dataset.id), b = data.besoins.get(el.dataset.sub);
    if (!(await askConfirm('Annuler la demande', `Annuler la demande « ${b.qte} × ${desigBesoin(b)} » ? Elle reste visible, barrée.`, 'Annuler la demande'))) return;
    await Store.update('besoins', b.id, { statut: 'annule', annuleLe: Store.now(), annulePar: Store.currentUserName() }, { action: 'annulation' });
    // L'attente liée à cette pièce n'a plus d'objet : elle est close (l'intervention redevient prête si plus rien n'est attendu).
    if ((o.attentes || []).some(a => a.besoinId === b.id && !a.fin)) {
      const attentes = o.attentes.map(a => a.besoinId === b.id && !a.fin ? { ...a, fin: Store.now() } : a);
      await edit('ots', o.id, { attentes, statut: o.statut === 'suspendue' && !attentes.some(a => !a.fin) ? 'prete' : o.statut }, { action: 'attente_levee', render: false });
    }
    render();
  };

  /** Levée automatique des attentes « pièce » dont le besoin est entièrement remis (remise du magasin reçue
      ou retrait urgent). Date de fin = date de la remise : toutes les copies écrivent la même valeur.
      Seuls les comptes qui peuvent modifier l'intervention le font (pas le magasinier ni le pilote). */
  let levee = false;
  async function leverAttentesPieces() {
    if (levee || !ecritureOK()) return 0;
    levee = true;
    const prets = [];
    try {
      const bes = [...data.besoins.values()], mv = [...data.mouvements.values()];
      for (const o of [...data.ots.values()]) {
        if (!otOuvert(o) || !peutModifierOT(o)) continue;
        const lev = Calculs.attentesALever(o, bes, mv);
        if (!lev.length) continue;
        const parId = new Map(lev.map(a => [a.id, a]));
        const attentes = o.attentes.map(a => parId.get(a.id) || a);
        const statut = o.statut === 'suspendue' && !attentes.some(a => !a.fin) ? 'prete' : o.statut;
        await Store.save('ots', { ...o, attentes, statut }, { action: 'attente_levee' });
        prets.push(o.ref);
      }
    } finally { levee = false; }
    if (prets.length) toast(`Pièce remise : ${prets.join(', ')} ${prets.length > 1 ? 'peuvent reprendre' : 'peut reprendre'}`);
    return prets.length;
  }

  A['ot-ajout-suite'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const v = await askForm({ title: 'Réserve ou suite', ok: 'Ajouter', fields: [
      { name: 'type', label: 'Type', type: 'chips', options: L.typeSuite, default: 'suite', required: true },
      { name: 'texte', label: 'Description', type: 'textarea', required: true },
      { name: 'responsableId', label: 'Responsable', type: 'select', options: personnesOpts(), empty: '—' },
      { name: 'echeance', label: 'Échéance', type: 'date' },
      { name: 'bloquante', label: 'Bloquante (empêche la clôture)', type: 'checkbox' }] });
    if (!v) return;
    await edit('ots', o.id, { reserves: [...(o.reserves || []), { id: Store.uid(), ...v, statut: 'ouverte', creeLe: Store.now() }] }, { action: 'reserve' });
  };
  A['ot-lever'] = async el => {
    const o = data.ots.get(el.dataset.id);
    const v = await askForm({ title: 'Lever la réserve / suite', ok: 'Lever', fields: [{ name: 'preuve', label: 'Preuve ou commentaire', type: 'text' }] });
    if (!v) return;
    await edit('ots', o.id, { reserves: o.reserves.map(s => s.id === el.dataset.sub ? { ...s, statut: 'levee', leveeLe: Store.now(), leveePar: Store.currentUserName(), preuve: v.preuve } : s) }, { action: 'levee_reserve', motif: v.preuve });
  };

  const eqFields = () => [
    { name: 'code', label: 'Code (= QR code)', type: 'text', required: true, placeholder: 'ex. PRESSE-01' },
    { name: 'designation', label: 'Désignation', type: 'text', required: true },
    { name: 'localisationId', label: 'Lieu', type: 'select', required: true, empty: '— Choisir —', options: list('localisations').map(l => [l.id, locPath(l.id)]) },
    { name: 'famille', label: 'Famille', type: 'text' },
    { name: 'criticite', label: 'Criticité', type: 'chips', options: { 1: '1', 2: '2', 3: '3', 4: '4' }, default: '2' }];
  A['eq-new'] = async () => {
    if (!data.localisations.size) { toast('Créez d’abord un lieu'); return A['loc-new'](); }
    const v = await askForm({ title: 'Nouvel équipement', fields: eqFields() });
    if (!v) return;
    if (list('equipements').some(e => e.code.toLowerCase() === v.code.toLowerCase())) { toast('Ce code existe déjà'); return; }
    const e = { id: Store.uid(), ...v, actif: true };
    await Store.save('equipements', e);
    location.hash = '#/eq/' + e.id;
  };
  A['eq-edit'] = async el => {
    const e = data.equipements.get(el.dataset.id);
    const v = await askForm({ title: 'Modifier l’équipement', values: e, fields: [...eqFields(), { name: 'reforme', label: 'Réformé (masqué des listes, historique conservé)', type: 'checkbox' }] });
    if (!v) return;
    const { reforme, ...rest } = v;
    if (list('equipements').some(x => x.id !== e.id && x.code.toLowerCase() === rest.code.toLowerCase())) { toast('Ce code existe déjà'); return; }
    await edit('equipements', e.id, { ...rest, actif: !reforme, reforme });
  };
  A['loc-new'] = async () => {
    const v = await askForm({ title: 'Nouveau lieu', fields: [
      { name: 'nom', label: 'Nom', type: 'text', required: true, placeholder: 'ex. Atelier presses' },
      { name: 'code', label: 'Code', type: 'text', required: true, placeholder: 'ex. TNG-A1' },
      { name: 'parentId', label: 'Dans', type: 'select', empty: '— Niveau site —', options: list('localisations').map(l => [l.id, locPath(l.id)]) }] });
    if (!v) return;
    await Store.save('localisations', { id: Store.uid(), ...v });
    render();
  };
  const persFields = [
    { name: 'nom', label: 'Nom', type: 'text', required: true },
    { name: 'role', label: 'Rôle', type: 'chips', options: L.role, default: 'technicien', required: true },
    { name: 'societe', label: 'Société (prestataire)', type: 'text' }];
  A['pers-new'] = async () => { const v = await askForm({ title: 'Nouvelle personne', fields: persFields }); if (v) { await Store.save('personnes', { id: Store.uid(), ...v, actif: true }); render(); } };
  A['pers-edit'] = async el => {
    const p = data.personnes.get(el.dataset.id);
    const v = await askForm({ title: 'Modifier', values: { ...p, inactif: p.actif === false }, fields: [...persFields, { name: 'inactif', label: 'Inactive (historique conservé)', type: 'checkbox' }] });
    if (!v) return;
    const { inactif, ...rest } = v;
    await edit('personnes', p.id, { ...rest, actif: !inactif });
  };

  const progFields = () => [
    { name: 'equipementId', label: 'Équipement', type: 'select', required: true, empty: '— Choisir —', options: list('equipements').filter(e => e.actif !== false).map(e => [e.id, `${e.designation} (${e.code})`]) },
    { name: 'libelle', label: 'Libellé', type: 'text', required: true, placeholder: 'ex. Vidange compresseur' },
    { name: 'modele', label: 'Modèle', type: 'chips', options: L.modele, default: 'entretien', required: true },
    { name: 'periodiciteJours', label: 'Périodicité (jours)', type: 'number', required: true },
    { name: 'prochaineEcheance', label: 'Prochaine échéance', type: 'date', required: true },
    { name: 'regle', label: 'Échéance suivante', type: 'chips', options: L.regle, default: 'fixe', required: true },
    { name: 'instruction', label: 'Instruction / gamme', type: 'textarea' }];
  A['prog-new'] = async () => { const v = await askForm({ title: 'Nouveau programme préventif', fields: progFields() }); if (v) { await Store.save('programmes', { id: Store.uid(), ...v, actif: true }); render(); } };
  A['prog-edit'] = async el => {
    const p = data.programmes.get(el.dataset.id);
    const v = await askForm({ title: 'Modifier le programme', values: p, fields: [...progFields(), { name: 'motif', label: 'Motif (report d’échéance…)', type: 'text' }] });
    if (!v) return;
    const { motif, ...rest } = v;
    await edit('programmes', p.id, rest, { motif });
  };
  A['prog-ot'] = async el => {
    const p = data.programmes.get(el.dataset.id);
    const o = await newOT({ programmeId: p.id, echeance: p.prochaineEcheance, equipementId: p.equipementId, nature: 'preventive', priorite: 'planifiable', travaux: null, activites: [] });
    location.hash = '#/ot/' + o.id;
  };

  A['photo-ajout'] = el => {
    const inp = Object.assign(document.createElement('input'), { type: 'file', accept: 'image/*' });
    inp.onchange = async () => {
      const f = inp.files[0]; if (!f) return;
      try {
        await Store.save('photos', { id: Store.uid(), parentType: el.dataset.type, parentId: el.dataset.id, dataUrl: await compresserPhoto(f), le: Store.now() });
        toast('Photo enregistrée sur l’appareil'); render();
      } catch { toast('Image illisible'); }
    };
    inp.click();
  };
  A['photo-voir'] = el => {
    const p = data.photos.get(el.dataset.id);
    const d = document.createElement('dialog'); d.className = 'sheet';
    d.innerHTML = `<form method="dialog"><img src="${p.dataUrl}" alt="" style="width:100%;border-radius:10px"><p class="small muted">${fmtY(p.le)} · ${esc(p.creePar)}</p><div class="sheet-actions"><button class="btn">Fermer</button></div></form>`;
    document.body.append(d); d.addEventListener('close', () => d.remove()); d.showModal();
  };
  A.imprimer = () => window.print();
  A.copy = async el => { try { await navigator.clipboard.writeText(el.dataset.v); toast('Lien copié'); } catch { toast('Copie impossible : sélectionnez le lien'); } };
  A.export = () => {
    const blob = new Blob([JSON.stringify(Store.exportAll(), null, 1)], { type: 'application/json' });
    download(blob, `gmao-sauvegarde-${Store.device().code}-${Store.now().replace(/[-:T]/g, '').slice(0, 12)}.json`);
    Store.persistMeta({ id: 'sauvegarde', le: Store.now() }).then(() => { toast('Sauvegarde exportée'); render(); });
  };
  A.import = () => {
    const inp = $('#importFile');
    inp.onchange = async () => {
      const f = inp.files[0]; if (!f) return;
      try { const n = await Store.importAll(JSON.parse(await f.text())); toast(`${n} fiche(s) ajoutée(s) ou mises à jour`); render(); }
      catch (e) { toast('Import impossible : ' + e.message); }
      inp.value = '';
    };
    inp.click();
  };
  /** Export CSV pour Excel (point-virgule, UTF-8 avec BOM). Texte protégé contre l'injection de formules ;
      les nombres restent des nombres. */
  function exportCsv(head, rows, nom) {
    const cell = v => { if (typeof v === 'number' && Number.isFinite(v)) return String(v).replace('.', ','); let s = String(v ?? ''); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return '"' + s.replace(/"/g, '""') + '"'; };
    download(new Blob(['\ufeff' + [head, ...rows].map(r => r.map(cell).join(';')).join('\r\n')], { type: 'text/csv;charset=utf-8' }), nom);
  }
  A.csv = () => {
    const head = ['Référence', 'Code équipement', 'Équipement', 'Nature', 'Priorité', 'Statut', 'Créée le', 'Clôturée le', 'Intervenants', 'Activités', 'Travaux', 'Résultat', 'Cause', 'Certitude', 'Avec arrêt', 'Début arrêt', 'Fin arrêt', 'Demandes'];
    const rows = list('ots').sort((a, b) => a.creeLe.localeCompare(b.creeLe)).map(o => [o.ref, eq(o.equipementId)?.code, eq(o.equipementId)?.designation, L.nature[o.nature], L.priorite[o.priorite], L.statutOT[o.statut], o.creeLe, o.clotureLe,
      (o.intervenants || []).map(i => persNom(i.personneId)).join(', '), (o.activites || []).map(a => L.activite[a]).join(', '), o.travaux, L.resultat[o.resultat], o.cause, L.certitude[o.certitudeCause], L.arret[o.avecArret], o.arretDebut, o.arretFin,
      (o.demandeIds || []).map(id => refDe('demandes', id)).join(', ')]);
    exportCsv(head, rows, `gmao-interventions-${today()}.csv`);
  };
  function download(blob, name) { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 5000); }
  A['sync-ouvrir'] = () => { location.hash = '#/reglages'; setTimeout(() => $('#bloc-sync')?.scrollIntoView({ block: 'center' }), 50); };
  A['sync-config'] = async () => {
    const c = data.meta.get('cloud') || {};
    // Projet Supabase du site (adresse et clé publique : publiques par conception, protégées par les règles RLS).
    const v = await askForm({ title: 'Connexion au serveur', ok: 'Se connecter', values: { url: c.url || Sync.PROJET.url, cle: c.cle || Sync.PROJET.cle, email: c.email }, fields: [
      { type: 'info', text: 'Adresse et clé publique : Supabase → Project Settings → API. Le compte est créé par le responsable dans Supabase → Authentication → Users.' },
      { name: 'url', label: 'Adresse du projet (https://….supabase.co)', type: 'url', required: true },
      { name: 'cle', label: 'Clé publique (anon / publishable)', type: 'text', required: true },
      { name: 'email', label: 'E-mail', type: 'email', required: true },
      { name: 'motDePasse', label: 'Mot de passe', type: 'password', required: true }] });
    if (!v) return;
    try {
      toast('Connexion…');
      const premiere = await Sync.connecter(v);
      try { await Sync.chargerProfil(); } catch (e) { toast(e.message); }
      // Premier branchement : tout ce qui existe déjà sur l'appareil part au serveur (fusion, sans
      // suppression), sinon une fiche modifiée plus tard n'arriverait qu'en partie ailleurs.
      await premierEnvoiSiBesoin(premiere);
      toast('Connecté · synchronisation en cours');
      await Sync.synchroniser();
      render();
    } catch (e) {
      if (/incorrect/.test(e.message)) await alertBox('Connexion refusée', ['E-mail ou mot de passe incorrect.', 'Si vous n’avez jamais choisi de mot de passe (compte créé par invitation), utilisez « Première connexion ou mot de passe oublié » : vous recevrez un lien par e-mail.']);
      else toast('Échec : ' + e.message);
    }
  };
  A['sync-lien'] = async () => {
    const v = await askForm({ title: 'Recevoir un lien par e-mail', ok: 'Envoyer le lien', values: { email: data.meta.get('cloud')?.email }, fields: [
      { type: 'info', text: 'Un e-mail vous permettra de choisir votre mot de passe. Ouvrez-le de préférence sur l’appareil à connecter.' },
      { name: 'email', label: 'Votre e-mail (compte créé par le responsable)', type: 'email', required: true }] });
    if (!v) return;
    try {
      await Sync.demanderLien(v.email, adressePublique());
      await alertBox('E-mail envoyé', [`Si ${v.email} correspond à un compte, un lien vient d’être envoyé.`, 'Cliquez dessus : l’appli s’ouvrira et vous demandera de choisir votre mot de passe.', 'Pensez à regarder dans les courriers indésirables.']);
    } catch (e) { toast('Échec : ' + e.message); }
  };
  async function premierEnvoiSiBesoin(premiere) {
    const nb = data.equipements.size + data.demandes.size + data.ots.size;
    if (!premiere || !nb) return;
    const ent = Sync.profil()?.entreprise?.nom || 'votre entreprise';
    if (await askConfirm('Données déjà présentes sur cet appareil', `Cet appareil contient ${data.equipements.size} équipement(s), ${data.demandes.size} demande(s) et ${data.ots.size} intervention(s). Les envoyer dans « ${ent} » ? Sinon, elles seront effacées de l’appareil et remplacées par les données du serveur.`, 'Envoyer')) {
      const n = await Store.toutEnvoyer();
      toast(`${n} fiche(s) envoyées vers ${ent}`);
    } else {
      await Store.viderMetier();
      toast('Données locales effacées : chargement depuis le serveur');
    }
  }
  /** Retour d'un lien reçu par e-mail : invitation ou mot de passe oublié. */
  async function traiterLienEmail() {
    const l = Sync.lireLienEmail(location.hash);
    if (!l) return false;
    history.replaceState(null, '', location.pathname + '#/reglages');
    if (l.erreur) { await alertBox('Lien de connexion', [l.erreur]); return true; }
    try {
      const { premiere, email } = await Sync.sessionDepuisLien(l);
      try { await Sync.chargerProfil(); } catch { /* sera réessayé à la synchro */ }
      if (['invite', 'recovery', 'signup'].includes(l.type)) {
        for (;;) {
          const v = await askForm({ title: 'Choisissez votre mot de passe', ok: 'Enregistrer', cancel: null, fields: [
            { type: 'info', text: `Compte : ${email}. Ce mot de passe servira à vous connecter sur vos autres appareils.` },
            { name: 'p1', label: 'Nouveau mot de passe (8 caractères minimum)', type: 'password', required: true },
            { name: 'p2', label: 'Confirmer', type: 'password', required: true }] });
          if (!v) continue;
          if (v.p1 !== v.p2) { toast('Les deux saisies diffèrent'); continue; }
          if (v.p1.length < 8) { toast('8 caractères minimum'); continue; }
          try { await Sync.changerMotDePasse(v.p1); break; } catch (e) { toast(e.message); }
        }
      }
      await premierEnvoiSiBesoin(premiere);
      toast(`Connecté : ${email}`);
      await Sync.synchroniser();
    } catch (e) { await alertBox('Lien de connexion', [e.message]); }
    render();
    return true;
  }

  A['sync-maintenant'] = async () => { try { await Sync.chargerProfil(); } catch (e) { toast(e.message); } await Sync.synchroniser(); render(); const s = Sync.etatCourant(); toast(s.erreur ? 'Erreur : ' + s.erreur : 'Synchronisation terminée'); };
  A['sync-tout'] = async () => {
    if (!(await askConfirm('Tout envoyer', 'Toutes les fiches de cet appareil seront envoyées au serveur (fusion, rien n’est supprimé). Utile au premier branchement ou après l’import d’une sauvegarde.', 'Envoyer'))) return;
    const n = await Store.toutEnvoyer(); toast(`${n} fiche(s) mises en file d’envoi`); await Sync.synchroniser(); render();
  };
  A['sync-deconnecter'] = async () => {
    if (!(await askConfirm('Se déconnecter', 'Les saisies resteront sur l’appareil et partiront à la prochaine connexion.', 'Se déconnecter'))) return;
    await Sync.deconnecter(); render();
  };
  A.wipe = async () => {
    const v = await askForm({ title: 'Effacer cet appareil', ok: 'Effacer', fields: [{ type: 'info', cls: 'warn', text: 'Toutes les données de cet appareil seront effacées. Les autres appareils et vos sauvegardes ne sont pas touchés.' }, { name: 'c', label: 'Tapez EFFACER pour confirmer', type: 'text', required: true }] });
    if (v?.c !== 'EFFACER') return;
    await Store.wipe(); location.hash = '#/accueil'; render();
  };
  A.demo = async () => { if (data.equipements.size) return; await chargerDemo(); toast('Démo chargée'); location.hash = '#/accueil'; render(); };

  // ---------- démo (exemple de la procédure, sans chronologie détaillée) ----------
  async function chargerDemo() {
    const S = (t, o) => Store.save(t, o);
    const id = Store.uid;
    const J = (n, hm) => addDays(today(), n) + (hm ? 'T' + hm : '');
    const site = { id: id(), code: 'TNG', nom: 'Site Tanger', parentId: null };
    const at = { id: id(), code: 'TNG-A1', nom: 'Atelier presses', parentId: site.id };
    const li = { id: id(), code: 'TNG-A2', nom: 'Ligne conditionnement', parentId: site.id };
    const ut = { id: id(), code: 'TNG-UT', nom: 'Utilités', parentId: site.id };
    for (const l of [site, at, li, ut]) await S('localisations', l);
    const E = (code, designation, loc, famille, criticite) => ({ id: id(), code, designation, localisationId: loc.id, famille, criticite: String(criticite), actif: true });
    const presse = E('PRESSE-01', 'Presse hydraulique 200 t', at, 'presse', 4);
    const emb = E('EMB-02', 'Emballeuse ligne 2', li, 'emballage', 3);
    const conv = E('CONV-03', 'Convoyeur sortie ligne 2', li, 'convoyage', 2);
    const comp = E('COMP-01', 'Compresseur d’air 55 kW', ut, 'utilité', 4);
    for (const e of [presse, emb, conv, comp]) await S('equipements', e);
    const P = (nom, role) => ({ id: id(), nom, role, actif: true });
    const resp = P('Responsable maintenance', 'responsable'), ta = P('Technicien A (mécanique)', 'technicien'), tb = P('Technicien B (automatisme)', 'technicien'), mag = P('Magasinier', 'magasinier');
    for (const p of [resp, ta, tb, mag]) await S('personnes', p);
    // Appareil sans compte : on signe comme le technicien A de la démo. Avec un compte, la signature reste celle du compte.
    if (!Sync.profil()) await Store.persistMeta({ ...Store.device(), personneId: ta.id });
    const A1 = { id: id(), ref: 'J-VER-80', designation: 'Joint de vérin Ø80', unite: 'u', stockMin: 2, actif: true };
    const A2 = { id: id(), ref: 'HUI-HV46', designation: 'Huile hydraulique HV46', unite: 'L', stockMin: 20, actif: true };
    const A3 = { id: id(), ref: 'FIL-AIR', designation: 'Filtre à air compresseur', unite: 'u', stockMin: 1, actif: true };
    for (const a of [A1, A2, A3]) await S('articles', a);
    for (const [a, q] of [[A1, 3], [A2, 60], [A3, 1]]) await S('mouvements', { id: id(), articleId: a.id, type: 'entree', qte: q, otId: null, le: J(-20, '09:00'), motif: 'Stock initial' });
    const I = (p, role = 'intervenant') => ({ id: id(), personneId: p.id, role, depuis: J(-3, '08:10'), fin: null, par: resp.nom });

    // 1. Panne presse : une demande, deux interventions, un seul arrêt (bornes connues)
    const d1 = { id: id(), ref: 'DEM-DM-0001', origine: 'tiers', tiers: { nom: 'Opérateur presse', service: 'Production' }, equipementId: presse.id, besoin: 'corriger', constat: 'Le vérin ne tient plus la position', etat: 'indisponible', impact: 'interrompu', heureFait: J(-3, '08:00'), precisionHeure: 'exacte', statut: 'traitement_organise', priseEnChargePar: ta.id, priseEnChargeLe: J(-3, '08:05'), creeLe: J(-3, '08:03'), creePar: ta.nom };
    await S('demandes', d1);
    const m1 = { id: id(), articleId: A1.id, type: 'sortie', qte: -1, otId: null, le: J(-3, '09:00'), motif: null };
    const o1 = { id: id(), ref: 'OT-DM-0001', demandeIds: [d1.id], equipementId: presse.id, nature: 'corrective', priorite: 'critique_service', statut: 'cloturee', intervenants: [I(ta)], activites: ['diagnostic', 'remplacement'], travaux: 'Remplacement du joint de vérin, purge du circuit.', resultat: 'resolu', cause: 'Joint de vérin usé', certitudeCause: 'probable', familleDefaut: 'hydraulique', avecArret: 'oui', arretDebut: J(-3, '08:00'), arretFin: J(-3, '10:30'), pieces: [{ id: id(), articleId: A1.id, libelle: null, qte: 1, mouvementId: m1.id, annulee: false }], reserves: [], attentes: [{ id: id(), motif: 'piece', detail: 'Matériel complémentaire', depuis: J(-3, '09:15'), fin: J(-3, '09:30'), responsableId: resp.id }], clotureLe: J(-3, '11:20'), cloturePar: resp.nom, creeLe: J(-3, '08:05'), creePar: ta.nom, programmeId: null, echeance: null, creneau: null };
    m1.otId = o1.id;
    await S('mouvements', m1); await S('ots', o1);
    await S('ots', { ...o1, id: id(), ref: 'OT-DM-0002', intervenants: [I(tb)], activites: ['reglage', 'essai'], travaux: 'Réglage capteur de position et essais.', cause: null, certitudeCause: null, familleDefaut: null, pieces: [], attentes: [], clotureLe: J(-3, '11:40'), creeLe: J(-3, '09:25'), creePar: resp.nom });

    // 2. Anomalie sans arrêt, à examiner
    await S('demandes', { id: id(), ref: 'DEM-DM-0002', origine: 'tiers', tiers: { nom: 'Chef de ligne', service: 'Conditionnement' }, equipementId: emb.id, besoin: 'verifier', constat: 'Bruit anormal au niveau du convoyeur d’entrée', etat: 'degrade', impact: 'aucun_constate', heureFait: J(-1, '14:20'), precisionHeure: 'estimee', statut: 'a_examiner', priseEnChargePar: null, priseEnChargeLe: null, creeLe: J(-1, '14:35'), creePar: resp.nom });

    // 3. Convoyeur : en attente de pièce (répétitif)
    const d3 = { id: id(), ref: 'DEM-DM-0003', origine: 'observation', tiers: null, equipementId: conv.id, besoin: 'corriger', constat: 'Bande qui dévie, frottement côté moteur', etat: 'indisponible', impact: 'interrompu', heureFait: J(0, '07:40'), precisionHeure: 'estimee', statut: 'traitement_organise', priseEnChargePar: tb.id, priseEnChargeLe: J(0, '07:50'), creeLe: J(0, '07:45'), creePar: tb.nom };
    await S('demandes', d3);
    // Volet B : le rouleau est demandé en urgence (en stock, à remettre) ; 2 L d'huile pris en urgence, à vérifier.
    const A4 = { id: id(), ref: 'ROUL-TD-50', designation: 'Rouleau tendeur convoyeur Ø50', unite: 'u', stockMin: 1, actif: true };
    await S('articles', A4);
    await S('mouvements', { id: id(), articleId: A4.id, type: 'entree', qte: 2, otId: null, le: J(0, '09:15'), motif: 'Livraison fournisseur' });
    const o3 = id(), b3 = id(), b4 = id();
    await S('besoins', { id: b3, ref: 'BES-DM-0001', otId: o3, equipementId: conv.id, articleId: A4.id, qte: 1, unite: 'u', urgent: true, note: 'Arrêt ligne 2', statut: 'demande', demandeur: tb.nom, demandeLe: J(0, '08:30') });
    await S('besoins', { id: b4, ref: 'BES-DM-0002', otId: o3, equipementId: conv.id, articleId: A2.id, qte: 2, unite: 'L', urgent: true, note: 'Retrait urgent', statut: 'demande', demandeur: tb.nom, demandeLe: J(0, '08:10') });
    await S('mouvements', { id: id(), articleId: A2.id, type: 'remise', qte: -2, urgent: true, aVerifier: true, besoinId: b4, otId: o3, le: J(0, '08:10'), motif: 'Retrait urgent OT-DM-0003', creePar: tb.nom });
    await S('ots', { id: o3, ref: 'OT-DM-0003', demandeIds: [d3.id], equipementId: conv.id, nature: 'corrective', priorite: 'critique_service', statut: 'suspendue', intervenants: [I(tb)], activites: ['diagnostic'], travaux: 'Rouleau tendeur grippé.', resultat: null, cause: null, certitudeCause: null, familleDefaut: 'mecanique', avecArret: 'oui', arretDebut: J(0, '07:40'), arretFin: null, pieces: [{ id: id(), besoinId: b4, articleId: A2.id, libelle: null, qte: 2, mouvementId: null, annulee: false }], reserves: [], attentes: [{ id: id(), motif: 'piece', besoinId: b3, detail: 'Rouleau tendeur convoyeur Ø50', depuis: J(0, '08:30'), fin: null, responsableId: mag.id }], clotureLe: null, cloturePar: null, creeLe: J(0, '07:50'), creePar: tb.nom, programmeId: null, echeance: null, creneau: null });
    await S('demandes', { id: id(), ref: 'DEM-DM-0004', origine: 'observation', tiers: null, equipementId: conv.id, besoin: 'corriger', constat: 'Bande qui dévie', etat: 'degrade', impact: 'reduit', heureFait: null, precisionHeure: 'inconnue', statut: 'close_sans_travail', motifClassement: 'Recentrage par l’opérateur', creeLe: J(-12, '10:00'), creePar: tb.nom });
    await S('demandes', { id: id(), ref: 'DEM-DM-0005', origine: 'observation', tiers: null, equipementId: conv.id, besoin: 'corriger', constat: 'Déviation de bande, réglage tendeur', etat: 'anomalie', impact: 'aucun_constate', heureFait: null, precisionHeure: 'inconnue', statut: 'traitement_organise', creeLe: J(-25, '15:00'), creePar: ta.nom });

    // 4. Préventif : un en retard, un à venir
    await S('programmes', { id: id(), equipementId: comp.id, libelle: 'Vidange et filtre compresseur', modele: 'entretien', periodiciteJours: 90, prochaineEcheance: J(-2), regle: 'fixe', instruction: '1. Consigner selon procédure site\n2. Vidanger, remplacer filtre à air\n3. Essai à vide puis en charge', actif: true });
    await S('programmes', { id: id(), equipementId: presse.id, libelle: 'Contrôle niveau et fuites hydrauliques', modele: 'inspection', periodiciteJours: 30, prochaineEcheance: J(5), regle: 'apres_realisation', instruction: 'Niveau bâche, état flexibles, traces de fuite.', actif: true });
  }

  // ---------- routeur ----------
  let R = null;
  function parseHash() {
    const h = location.hash.replace(/^#\/?/, '') || 'accueil';
    const [path, qs] = h.split('?');
    const [name, id] = path.split('/');
    return { name, id: id ? decodeURIComponent(id) : null, q: new URLSearchParams(qs || '') };
  }
  const TAB_OF = { demande: 'demandes', ot: 'ots', eq: 'parc', article: 'magasin', reappro: 'magasin', achat: 'plus', achats: 'plus', valeur: 'plus', signaler: '', qr: 'parc', plateforme: 'plus' };
  const MOBILE_PLUS = ['preventif', 'magasin', 'article', 'reappro', 'achat', 'achats', 'valeur', 'indicateurs', 'journal', 'reglages', 'plus'];
  function render() {
    cacheEtat = null;
    R = parseHash();
    const fn = V[R.name] || V.accueil;
    $('#view').innerHTML = fn(R);
    const tab = TAB_OF[R.name] ?? R.name;
    document.querySelectorAll('.tabs a').forEach(a => {
      const t = a.dataset.tab;
      a.classList.toggle('on', t === tab || (t === 'plus' && MOBILE_PLUS.includes(R.name)));
    });
    $('#fab').classList.toggle('hidden', R.name === 'signaler');
    const pf = Sync.profil();
    const bs = $('#site');
    if (bs) {
      bs.classList.toggle('hidden', !pf);
      const sa = siteActif();
      bs.textContent = pf ? '📍 ' + (sa === 'tous' ? 'Tous les sites' : nomSite(sa) || 'Site') : '';
    }
    document.querySelectorAll('.tabs a[data-tab=magasin]').forEach(a => a.classList.toggle('hidden', !aModule('magasin')));
    document.querySelectorAll('.tabs a[data-tab=preventif]').forEach(a => a.classList.toggle('hidden', !aModule('preventif')));
    if (pf && !ecritureOK()) $('#view').insertAdjacentHTML('afterbegin', '<p class="warn">Abonnement suspendu ou expiré : consultation seule. Vos données restent accessibles et exportables.</p>');
    const me = Store.currentUser();
    $('#who').textContent = me ? '👤 ' + me.nom : '👤 Qui êtes-vous ?';
    if (role()) {
      document.querySelectorAll('#view [data-act]').forEach(b => { if (!autorise(b.dataset.act)) b.remove(); });
      $('#fab').classList.toggle('hidden', R.name === 'signaler' || !autorise('signaler'));
      if (R.name === 'ot') {
        const o = data.ots.get(R.id);
        if (o && !peutModifierOT(o)) {
          document.querySelectorAll('#view [data-bind]').forEach(i => { i.disabled = true; });
          document.querySelectorAll('#view [data-act^="ot-"]').forEach(b => b.remove());
        }
      }
    }
    const p = Sync.profil();
    if (p) $('#who').textContent = `👤 ${Store.currentUser()?.nom || p.nom || p.email} · ${L.role[p.role] || p.role}`;
    AFTER[R.name]?.(R);
  }

  // ---------- événements globaux ----------
  document.addEventListener('click', e => {
    const el = e.target.closest('[data-act]');
    if (!el) return;
    e.preventDefault();
    if (!autorise(el.dataset.act)) { toast(motifRefus(el.dataset.act)); return; }
    A[el.dataset.act]?.(el, e);
  });
  document.addEventListener('change', async e => {
    const el = e.target;
    if (el.dataset?.nav !== undefined) { location.hash = el.dataset.nav + encodeURIComponent(el.value); return; }
    const b = el.dataset?.bind;
    if (!b) return;
    const [t, id, field] = b.split('|');
    let v;
    if (el.type === 'checkbox' && el.closest('.chips')) v = [...el.closest('.chips').querySelectorAll('input:checked')].map(i => i.value);
    else if (el.type === 'checkbox') v = el.checked;
    else v = (el.value || '').trim() || null;
    if (t === 'meta') {
      const urlOk = u => { try { return /^https:\/\//.test(u) && !estLocale(new URL(u).hostname); } catch { return false; } };
      if (id === 'adresse' && v && !urlOk(v)) { toast('Adresse refusée : elle doit commencer par https:// et ne pas être locale'); render(); return; }
      await Store.persistMeta({ ...(data.meta.get(id) || {}), id, [field]: v }); render(); return;
    }
    const rr = el.type === 'radio' || el.tagName === 'SELECT' || 'rerender' in el.dataset;
    await edit(t, id, { [field]: v }, { render: rr });
  });
  document.addEventListener('input', e => {
    const f = e.target.dataset?.filter;
    if (!f) return;
    const q = e.target.value.trim().toLowerCase();
    document.querySelectorAll(f + ' > .card').forEach(c => { c.style.display = !q || c.textContent.toLowerCase().includes(q) ? '' : 'none'; });
  });
  window.addEventListener('hashchange', async () => { if (await traiterLienEmail()) return; render(); window.scrollTo(0, 0); });
  const net = () => { const n = $('#net'); n.textContent = navigator.onLine ? '' : 'Hors ligne · enregistré sur l’appareil'; n.className = 'net' + (navigator.onLine ? ' hidden' : ' off'); };
  window.addEventListener('online', net); window.addEventListener('offline', net);

  // ---------- démarrage ----------
  function voyantSynchro(s) {
    const b = $('#sync');
    if (!b) return;
    b.classList.toggle('hidden', !s.configure);
    let t, c;
    if (!s.connecte) [t, c] = ['☁ Reconnexion', 'err'];
    else if (s.enCours) [t, c] = ['☁ Synchro…', ''];
    else if (s.erreur) [t, c] = [`☁ Erreur${s.attente ? ' · ' + s.attente : ''}`, 'err'];
    else if (s.attente) [t, c] = [`☁ ${s.attente} à envoyer`, 'wait'];
    else [t, c] = ['☁ À jour', 'ok'];
    b.textContent = t; b.className = 'sync ' + c + (s.configure ? '' : ' hidden');
    b.title = s.erreur || (s.dernier ? 'Dernière synchro : ' + fmtY(s.dernier) : '');
    if (R?.name === 'reglages' && $('#bloc-sync') && !enSaisie()) $('#bloc-sync').outerHTML = blocSynchro().replace(/^[\s\S]*?(<div class="card" id="bloc-sync">)/, '$1');
  }
  const enSaisie = () => !!document.querySelector('dialog[open]') || !!document.activeElement?.matches?.('#view input, #view textarea, #view select');
  async function quandRecu(n) {
    toast(`☁ ${n} mise(s) à jour reçue(s)`);
    await leverAttentesPieces();
    if (!enSaisie()) render();
  }

  // Aides communes pour les écrans par domaine (js/vues/*.js, scripts classiques chargés après app.js).
  window.App = { V, A, L, esc, badge, empty, seg, search, askForm, askConfirm, askText, alertBox, toast, edit, list, render, fmt, fmtY, today, refDe,
    role, autorise, aModule, siteActif, nomSite, mesSites, desigBesoin, CLS_BESOIN, leverAttentesPieces, exportCsv };

  const lancer = () => Store.open().then(async () => {
    net();
    const lien = !!Sync.lireLienEmail(location.hash); // retour d'un e-mail d'invitation : pas d'affichage de page avant
    if (!lien) render();
    if (await leverAttentesPieces() && !lien) render();
    Sync.demarrer({ etat: voyantSynchro, reception: quandRecu, refus: liste => {
      if (!liste.length) return;
      alertBox('Modification refusée par le serveur', [...liste.slice(0, 5).map(r => `• ${L.entite[r.type] || r.type} ${refDe(r.type, r.id)} : ${r.motif}`), 'La version du serveur a été rétablie sur cet appareil.']);
      if (!enSaisie()) render();
    } });
    if (lien) await traiterLienEmail();
  }).catch(err => {
    $('#view').innerHTML = `<p class="warn">Stockage local indisponible : ${esc(err.message)}. Vérifiez que le navigateur n’est pas en navigation privée.</p>`;
  });
  // Démarrage une fois tous les scripts chargés (les écrans de js/vues/ s'enregistrent avant le premier affichage).
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', lancer); else lancer();
  if ('serviceWorker' in navigator && isSecureContext && location.protocol !== 'file:') {
    const avait = !!navigator.serviceWorker.controller;
    navigator.serviceWorker.register('sw.js').catch(() => {});
    // Nouvelle version installée : proposer de recharger (jamais de rechargement forcé en pleine saisie).
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (!avait || $('#maj')) return;
      const d = document.createElement('div');
      d.id = 'maj'; d.className = 'maj';
      d.innerHTML = 'Nouvelle version disponible <button class="btn sm primary" type="button">Recharger</button>';
      d.querySelector('button').onclick = () => location.reload();
      document.body.append(d);
    });
  }
})();
