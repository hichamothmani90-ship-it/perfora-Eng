/* Règles métier et indicateurs — fonctions pures, sans accès au stockage.
   Utilisées par l'interface (window.Calculs) et par les tests (node --test).
   Conventions : PR MAINT 01 V3 §11 et décision du 6 nov. 2026 (pas de chronomètre). */
(function (root) {
  // ---------- dates (chaînes locales du site "YYYY-MM-DDTHH:mm") ----------
  function addDays(s, n) {
    const [y, m, d] = s.slice(0, 10).split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
  }
  const daysBetween = (a, b) => Math.round((Date.parse(b.slice(0, 10)) - Date.parse(a.slice(0, 10))) / 864e5);
  const minutesBetween = (a, b) => (Date.parse(b) - Date.parse(a)) / 6e4;

  /** Durée de l'union d'intervalles [début, fin[ : les chevauchements ne comptent qu'une fois. */
  function dureeUnion(intervalles) {
    const iv = intervalles.filter(([d, f]) => d && f && f > d).sort((a, b) => a[0].localeCompare(b[0]));
    if (!iv.length) return 0;
    let total = 0, [cd, cf] = iv[0];
    for (const [d, f] of iv.slice(1)) {
      if (d <= cf) { if (f > cf) cf = f; } else { total += minutesBetween(cd, cf); [cd, cf] = [d, f]; }
    }
    return total + minutesBetween(cd, cf);
  }

  function mediane(v) {
    if (!v.length) return null;
    const s = [...v].sort((a, b) => a - b), m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  // ---------- règles ----------
  /** Le besoin oriente la nature proposée ; « planifié » ne veut jamais dire préventif. */
  const NATURE_DU_BESOIN = { corriger: 'corrective', verifier: 'a_qualifier', entretien: 'preventive', serie: 'assistance_production', demarrage: 'assistance_production', derive: 'a_qualifier', travaux: 'travaux_techniques', autre: 'a_qualifier' };
  const ETAT_RANK = { indisponible: 0, degrade: 1, anomalie: 2, inconnu: 3, normal: 4 };
  const ETATS_DEFAUT = ['indisponible', 'degrade', 'anomalie'];

  const otOuvert = o => !['cloturee', 'annulee'].includes(o.statut);

  /** Une demande organisée reste ouverte tant qu'une de ses interventions l'est. */
  function demandeOuverte(d, otsDeLaDemande) {
    if (['a_examiner', 'prise_en_charge'].includes(d.statut)) return true;
    if (d.statut === 'traitement_organise') return !otsDeLaDemande.length || otsDeLaDemande.some(otOuvert);
    return false;
  }

  function indexOtsParDemande(ots) {
    const m = new Map();
    for (const o of ots) for (const id of o.demandeIds || []) { if (!m.has(id)) m.set(id, []); m.get(id).push(o); }
    return m;
  }

  /** État courant d'un équipement = pire état parmi ses demandes ouvertes. */
  function etatEquipement(eqId, demandes, ots, idx = indexOtsParDemande(ots)) {
    let w = 'normal';
    for (const d of demandes) if (d.equipementId === eqId && demandeOuverte(d, idx.get(d.id) || []) && ETAT_RANK[d.etat] < ETAT_RANK[w]) w = d.etat;
    return w;
  }

  /** Conditions de clôture (V3 §31 « obligatoire au bon moment »). Retourne la liste des manques. */
  function verifierCloture(o) {
    const err = [];
    const ouvertes = (o.reserves || []).filter(r => r.statut === 'ouverte');
    if (o.nature === 'a_qualifier') err.push('Qualifier la nature (corrective, préventive…).');
    if (!o.resultat) err.push('Indiquer le résultat du travail.');
    if (['partiel', 'non_resolu'].includes(o.resultat) && !ouvertes.length) err.push('Résultat partiel ou non résolu : ajouter une suite avec responsable.');
    if (ouvertes.some(r => r.bloquante)) err.push('Une réserve bloquante est encore ouverte.');
    if (o.arretDebut && o.arretFin && o.arretFin < o.arretDebut) err.push('La fin d’arrêt précède le début.');
    return err;
  }

  /** Échéance suivante d'un programme après clôture d'une occurrence.
      fixe : depuis l'échéance initiale (un retard ne décale pas le calendrier) ;
      apres_realisation : depuis la date de réalisation. */
  function echeanceSuivante(programme, echeanceRealisee, clotureLe) {
    const base = programme.regle === 'apres_realisation' ? clotureLe : echeanceRealisee;
    return addDays(base, Number(programme.periodiciteJours) || 30);
  }

  /** Un même fait (demande) n'est compté qu'une fois, quel que soit le nombre d'OT. */
  const cleFait = o => (o.demandeIds || [])[0] || o.id;

  /** Tous les indicateurs de pilotage sur [from ; today]. D = { demandes, ots, programmes } (tableaux). */
  function indicateurs(D, { from, today }) {
    const tous = D.ots;
    const ots = tous.filter(o => o.statut !== 'annulee' && o.creeLe.slice(0, 10) >= from);
    const idx = indexOtsParDemande(tous);

    const parNature = {};
    for (const o of ots) parNature[o.nature] = (parNature[o.nature] || 0) + 1;

    const clos = tous.filter(o => o.statut === 'cloturee' && o.clotureLe && o.clotureLe.slice(0, 10) >= from);
    const delais = clos.map(o => minutesBetween(o.creeLe, o.clotureLe)).filter(x => x >= 0);

    const dus = tous.filter(o => o.programmeId && o.echeance && o.echeance >= from && o.echeance < today && o.statut !== 'annulee');
    const aTemps = dus.filter(o => o.statut === 'cloturee' && o.clotureLe.slice(0, 10) <= o.echeance).length;
    const nonLances = D.programmes.filter(p => p.actif !== false && p.prochaineEcheance >= from && p.prochaineEcheance < today &&
      !tous.some(o => o.programmeId === p.id && o.echeance === p.prochaineEcheance && o.statut !== 'annulee')).length;

    const pieces = new Map();
    for (const o of ots) {
      const n = (o.pieces || []).filter(x => !x.annulee).reduce((s, x) => s + Number(x.qte || 0), 0);
      if (n) pieces.set(o.equipementId, (pieces.get(o.equipementId) || 0) + n);
    }

    const faits = new Map();
    for (const d of D.demandes) {
      if (d.creeLe.slice(0, 10) >= from && !['annulee', 'close_sans_travail'].includes(d.statut) && ETATS_DEFAUT.includes(d.etat)) faits.set(d.equipementId, (faits.get(d.equipementId) || 0) + 1);
    }
    for (const o of ots) if (o.nature === 'corrective' && !(o.demandeIds || []).length) faits.set(o.equipementId, (faits.get(o.equipementId) || 0) + 1);

    const avecArret = ots.filter(o => o.avecArret === 'oui');
    const bornees = avecArret.filter(o => o.arretDebut && o.arretFin && o.arretFin > o.arretDebut);
    const parEq = new Map();
    for (const o of bornees) { if (!parEq.has(o.equipementId)) parEq.set(o.equipementId, []); parEq.get(o.equipementId).push([o.arretDebut, o.arretFin]); }
    let dureeArrets = 0;
    for (const iv of parEq.values()) dureeArrets += dureeUnion(iv);

    const ouvertes = D.demandes.filter(d => demandeOuverte(d, idx.get(d.id) || []));

    return {
      interventions: ots.length,
      parNature,
      delaiCloture: { n: delais.length, mediane: mediane(delais), moyenne: delais.length ? delais.reduce((a, b) => a + b, 0) / delais.length : null },
      preventif: { dus: dus.length + nonLances, aTemps, nonLances },
      piecesParEquipement: [...pieces.entries()].sort((a, b) => b[1] - a[1]),
      repetitives: [...faits.entries()].filter(([, n]) => n >= 2).sort((a, b) => b[1] - a[1]),
      arrets: { faits: new Set(avecArret.map(cleFait)).size, faitsBornes: new Set(bornees.map(cleFait)).size, dureeConnue: bornees.length ? dureeArrets : null },
      demandesOuvertes: { n: ouvertes.length, plusAncienneJours: ouvertes.length ? Math.max(...ouvertes.map(d => daysBetween(d.creeLe, today))) : 0 },
    };
  }

  const Calculs = { addDays, daysBetween, minutesBetween, dureeUnion, mediane, NATURE_DU_BESOIN, ETAT_RANK, otOuvert, demandeOuverte, indexOtsParDemande, etatEquipement, verifierCloture, echeanceSuivante, indicateurs };
  if (typeof module === 'object' && module.exports) module.exports = Calculs; else root.Calculs = Calculs;
})(this);
