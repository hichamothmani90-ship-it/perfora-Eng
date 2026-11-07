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
  /** Signalement allégé (R2) : l'état choisi remplit état, impact et besoin. */
  const ETAT_SIGNALE = {
    arret: { etat: 'indisponible', impact: 'interrompu', besoin: 'corriger' },
    mal: { etat: 'degrade', impact: 'reduit', besoin: 'corriger' },
    verifier: { etat: 'anomalie', impact: 'aucun_constate', besoin: 'verifier' },
  };
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
  // ---------- lot R2 : qualification proposée / validée, type d'arrêt ----------
  /** Qualification effective. Une intervention sans le champ qualificationValidee (antérieure à R2, ou créée par le
      responsable) est considérée validée ; sinon la nature proposée par le technicien sert en attendant la validation. */
  function qualification(o) {
    const validee = o.qualificationValidee !== false;
    const nature = validee ? (o.nature || 'a_qualifier') : (o.natureProposee || o.nature || 'a_qualifier');
    const priorite = validee ? (o.priorite || 'a_qualifier') : (o.prioriteProposee || o.priorite || 'a_qualifier');
    return { nature, priorite, validee };
  }
  const ARRET_PLANIFIE = ['preventive', 'travaux_techniques'];
  /** Type proposé selon la nature : préventive, travaux → planifié ; le reste → non planifié. */
  const typeArretPropose = nature => ARRET_PLANIFIE.includes(nature) ? 'planifie' : 'non_planifie';
  /** Type d'arrêt effectif (null sans arrêt) ; déduit de la nature s'il n'a pas été choisi (interventions antérieures). */
  function typeArret(o) {
    if (o.avecArret !== 'oui') return null;
    return o.arretType || typeArretPropose(qualification(o).nature);
  }
  /** À qualifier par le responsable : qualification proposée, pas encore validée (interventions non annulées). */
  const aQualifier = o => o.qualificationValidee === false && o.statut !== 'annulee';

  function verifierCloture(o) {
    const err = [];
    const ouvertes = (o.reserves || []).filter(r => r.statut === 'ouverte');
    if (qualification(o).nature === 'a_qualifier') err.push('Qualifier la nature (corrective, préventive…).');
    if (!o.resultat) err.push('Indiquer le résultat du travail.');
    if (['partiel', 'non_resolu'].includes(o.resultat) && !ouvertes.length) err.push('Résultat partiel ou non résolu : ajouter une suite avec responsable.');
    if (ouvertes.some(r => r.bloquante)) err.push('Une réserve bloquante est encore ouverte.');
    if (o.arretDebut && o.arretFin && o.arretFin < o.arretDebut) err.push('La fin d’arrêt précède le début.');
    if (typeArret(o) === 'non_planifie' && !o.arretFin && !o.arretHeuresInconnues) err.push('Arrêt non planifié : indiquer la remise à disposition, ou cocher « heures inconnues ».');
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
    const ots = tous.filter(o => o.statut !== 'annulee' && (o.creeLe || "").slice(0, 10) >= from);
    const idx = indexOtsParDemande(tous);

    const parNature = {};
    for (const o of ots) { const n = qualification(o).nature; parNature[n] = (parNature[n] || 0) + 1; }

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
      if ((d.creeLe || "").slice(0, 10) >= from && !['annulee', 'close_sans_travail'].includes(d.statut) && ETATS_DEFAUT.includes(d.etat)) faits.set(d.equipementId, (faits.get(d.equipementId) || 0) + 1);
    }
    for (const o of ots) if (qualification(o).nature === 'corrective' && !(o.demandeIds || []).length) faits.set(o.equipementId, (faits.get(o.equipementId) || 0) + 1);

    const avecArret = ots.filter(o => o.avecArret === 'oui');
    const bornees = avecArret.filter(o => o.arretDebut && o.arretFin && o.arretFin > o.arretDebut);
    const parEq = new Map();
    for (const o of bornees) { if (!parEq.has(o.equipementId)) parEq.set(o.equipementId, []); parEq.get(o.equipementId).push([o.arretDebut, o.arretFin]); }
    let dureeArrets = 0;
    for (const iv of parEq.values()) dureeArrets += dureeUnion(iv);
    // R2 (préparation de R4) : pannes = arrêts non planifiés ; le MTTR ne retiendra que celles aux heures connues.
    const pannes = avecArret.filter(o => typeArret(o) === 'non_planifie');
    const pannesBornees = pannes.filter(o => o.arretDebut && o.arretFin && o.arretFin > o.arretDebut);

    const ouvertes = D.demandes.filter(d => demandeOuverte(d, idx.get(d.id) || []));

    return {
      interventions: ots.length,
      parNature,
      delaiCloture: { n: delais.length, mediane: mediane(delais), moyenne: delais.length ? delais.reduce((a, b) => a + b, 0) / delais.length : null },
      preventif: { dus: dus.length + nonLances, aTemps, nonLances },
      piecesParEquipement: [...pieces.entries()].sort((a, b) => b[1] - a[1]),
      repetitives: [...faits.entries()].filter(([, n]) => n >= 2).sort((a, b) => b[1] - a[1]),
      arrets: { faits: new Set(avecArret.map(cleFait)).size, faitsBornes: new Set(bornees.map(cleFait)).size, dureeConnue: bornees.length ? dureeArrets : null,
        nonPlanifies: new Set(pannes.map(cleFait)).size, nonPlanifiesBornes: new Set(pannesBornees.map(cleFait)).size,
        planifies: new Set(avecArret.filter(o => typeArret(o) === 'planifie').map(cleFait)).size },
      aQualifier: tous.filter(aQualifier).length,
      demandesOuvertes: { n: ouvertes.length, plusAncienneJours: ouvertes.length ? Math.max(...ouvertes.map(d => daysBetween(d.creeLe, today))) : 0 },
    };
  }

  // ---------- magasin relié au terrain (volet B, V3 §6, §15, §35) ----------
  // Cinq faits distincts : besoin (aucun effet stock), réservation (diminue le disponible),
  // remise / retrait urgent (− physique), utilisation (aucun effet : déjà sortie), retour (+ physique).
  // Les mouvements portent une quantité signée ; un rebut a qte = 0 (traçabilité sans retour en stock).
  const surSite = (o, siteId) => !siteId || !o.siteId || o.siteId === siteId;
  const abs = n => Math.abs(Number(n) || 0);

  /** Stock physique d'un article (sur un site si précisé) : somme des mouvements, jamais recalculée autrement. */
  function stockPhysique(mouvements, articleId, siteId) {
    return mouvements.filter(m => m.articleId === articleId && surSite(m, siteId)).reduce((s, m) => s + (Number(m.qte) || 0), 0);
  }
  const remisesDuBesoin = (mouvements, besoinId) => mouvements.filter(m => m.besoinId === besoinId && m.type === 'remise');
  const qteRemise = (mouvements, besoinId) => remisesDuBesoin(mouvements, besoinId).reduce((s, m) => s + abs(m.qte), 0);
  const qteRetournee = (mouvements, besoinId) => mouvements.filter(m => m.besoinId === besoinId && m.type === 'retour').reduce((s, m) => s + abs(m.qte), 0);

  /** Quantité réservée et pas encore remise (les besoins annulés ou indisponibles ne réservent rien). */
  function qteReservee(besoins, mouvements, articleId, siteId) {
    return besoins.filter(b => b.articleId === articleId && surSite(b, siteId) && !['annule', 'indisponible'].includes(b.statut))
      .reduce((s, b) => s + Math.max(0, abs(b.qteReservee) - qteRemise(mouvements, b.id)), 0);
  }
  function stockDisponible(besoins, mouvements, articleId, siteId) {
    return stockPhysique(mouvements, articleId, siteId) - qteReservee(besoins, mouvements, articleId, siteId);
  }

  /** État d'un besoin, déduit des faits (remises réelles), pas d'un statut saisi à la main. */
  function etatBesoin(b, mouvements) {
    if (b.statut === 'annule') return 'annule';
    const remis = qteRemise(mouvements, b.id), q = abs(b.qte);
    if (q && remis >= q) return 'remis';          // une remise réelle l'emporte sur « indisponible »
    if (remis > 0) return 'partiellement_remis';
    if (b.statut === 'indisponible') return 'indisponible';
    if (abs(b.qteReservee) > 0) return 'reserve';
    return 'demande';
  }

  /** Besoins que le magasin doit traiter : urgents d'abord, puis les plus anciens ; « indisponible » en dernier. */
  function besoinsAServir(besoins, mouvements) {
    return besoins.map(b => ({ b, etat: etatBesoin(b, mouvements) }))
      .filter(x => ['demande', 'reserve', 'partiellement_remis', 'indisponible'].includes(x.etat))
      .sort((x, y) => (x.etat === 'indisponible') - (y.etat === 'indisponible') || !!y.b.urgent - !!x.b.urgent
        || (x.b.demandeLe || x.b.creeLe || '').localeCompare(y.b.demandeLe || y.b.creeLe || ''));
  }

  /** Contrôle d'une remise : remis = utilisé + retourné + détenu. Un détenu négatif est un écart à expliquer. */
  function rapprochementBesoin(b, mouvements, pieces) {
    const remis = qteRemise(mouvements, b.id), retourne = qteRetournee(mouvements, b.id);
    const utilise = (pieces || []).filter(p => p.besoinId === b.id && !p.annulee).reduce((s, p) => s + abs(p.qte), 0);
    const detenu = remis - retourne - utilise;
    return { remis, utilise, retourne, detenu, ecart: detenu < 0 };
  }

  /** Retraits urgents faits par un technicien et pas encore vérifiés par le magasin. */
  const retraitsAVerifier = mouvements => mouvements.filter(m => m.type === 'remise' && m.urgent && !m.verifieLe);

  /** Attentes « pièce » d'une intervention à lever : besoin lié entièrement remis.
      Date de fin = date de la dernière remise (le fait), pas l'heure à laquelle l'appareil s'en aperçoit. */
  function attentesALever(ot, besoins, mouvements) {
    const parId = new Map(besoins.map(b => [b.id, b]));
    return (ot.attentes || []).filter(a => !a.fin && a.besoinId && parId.has(a.besoinId) && etatBesoin(parId.get(a.besoinId), mouvements) === 'remis')
      .map(a => ({ ...a, fin: remisesDuBesoin(mouvements, a.besoinId).map(m => m.le || '').sort().pop() || null, leveePar: 'remise' }));
  }

  /** Pièces remises pour une intervention ni utilisées ni rendues (à déclarer avant clôture). */
  function piecesDetenues(besoinsDeLOT, mouvements, pieces) {
    return besoinsDeLOT.map(b => ({ besoin: b, ...rapprochementBesoin(b, mouvements, pieces) })).filter(r => r.detenu > 0);
  }


  // ---------- stocks, réapprovisionnement et achats (volet C, V3 §14, §16, §17, §18) ----------
  // Conventions des mouvements :
  //   entree (qte > 0, achatId / ligneId si réception de commande) = quantité utilisable mise en stock ;
  //   isolement (qte = 0, quantite = N, achatId / ligneId) = pièces reçues mais douteuses, hors stock utilisable ;
  //   liberation (qte = +N, isolementId) = pièces isolées déclarées utilisables ;
  //   disposition (qte = 0, quantite = N, isolementId, decision : retour_fournisseur / rebut / reparation).
  // Les prix ne sont jamais sur les mouvements : ils vivent dans les fiches « valorisations » (lecture restreinte).
  const num = v => Number(v) || 0;
  const surArticleSite = (o, articleId, siteId) => o.articleId === articleId && surSite(o, siteId);
  const parDate = (a, b) => (a.le || '').localeCompare(b.le || '') || (a.creeLe || '').localeCompare(b.creeLe || '') || String(a.id).localeCompare(String(b.id));

  /** Seuil actif : dernière version validée pour l'article et le site. Sinon repère provisoire tiré de stockMin. */
  function seuilActif(seuils, article, siteId) {
    const v = seuils.filter(x => x.articleId === article.id && (!siteId || x.siteId === siteId) && x.statut === 'valide')
      .sort((a, b) => (b.valideLe || '').localeCompare(a.valideLe || ''))[0];
    if (v) return { ...v, provisoire: false };
    const m = num(article.stockMin);
    return m > 0 ? { articleId: article.id, siteId, securite: 0, pointCommande: m, cible: m, delaiJours: null, critique: false, provisoire: true } : null;
  }

  /** Quantités demandées par les interventions et pas encore couvertes par une réservation ni une remise. */
  function besoinsNonCouverts(besoins, mouvements, articleId, siteId) {
    return besoins.filter(b => surArticleSite(b, articleId, siteId) && ['demande', 'reserve', 'partiellement_remis', 'indisponible'].includes(etatBesoin(b, mouvements)))
      .reduce((s, b) => {
        const remis = qteRemise(mouvements, b.id), reserveRestant = Math.max(0, abs(b.qteReservee) - remis);
        return s + Math.max(0, abs(b.qte) - remis - reserveRestant);
      }, 0);
  }

  /** Réception d'une ligne de commande : reçu = utilisable + isolé ; reliquat = commandé − reçu (jamais négatif). */
  function receptionLigne(achat, ligne, mouvements) {
    const lies = mouvements.filter(m => m.achatId === achat.id && m.ligneId === ligne.id);
    const utilisable = lies.filter(m => m.type === 'entree').reduce((s, m) => s + num(m.qte), 0);
    const isole = lies.filter(m => m.type === 'isolement').reduce((s, m) => s + num(m.quantite), 0);
    const recu = utilisable + isole, commande = num(ligne.qteCommandee ?? ligne.qte);
    return { commande, recu, utilisable, isole, reliquat: ligne.solde ? 0 : Math.max(0, commande - recu) };
  }

  const ACHAT_COMMANDE = ['commandee', 'partiellement_recue', 'recue'];
  /** État d'une demande d'achat : saisi jusqu'à la commande, puis déduit des réceptions réelles. */
  function etatAchat(achat, mouvements) {
    if (!ACHAT_COMMANDE.includes(achat.statut)) return achat.statut;
    const r = (achat.lignes || []).map(l => receptionLigne(achat, l, mouvements));
    if (r.length && r.every(x => x.reliquat === 0)) return 'recue';
    if (r.some(x => x.recu > 0)) return 'partiellement_recue';
    return 'commandee';
  }

  /** Quantité en commande (reliquats des commandes passées en externe). Une commande n'est pas du stock. */
  function qteEnCommande(achats, mouvements, articleId, siteId) {
    let n = 0;
    for (const a of achats) {
      if (!ACHAT_COMMANDE.includes(a.statut) || !surSite(a, siteId)) continue;
      for (const l of a.lignes || []) if (l.articleId === articleId) n += receptionLigne(a, l, mouvements).reliquat;
    }
    return n;
  }

  /** Pièces isolées en attente de décision (reçues, ni libérées ni sorties). */
  function qteIsolee(mouvements, articleId, siteId) {
    const m = mouvements.filter(x => surArticleSite(x, articleId, siteId));
    const isole = m.filter(x => x.type === 'isolement').reduce((s, x) => s + num(x.quantite), 0);
    const decide = m.filter(x => x.type === 'liberation').reduce((s, x) => s + num(x.qte), 0)
      + m.filter(x => x.type === 'disposition').reduce((s, x) => s + num(x.quantite), 0);
    return Math.max(0, isole - decide);
  }

  /** Situation d'un article sur un site et proposition de réapprovisionnement (ne commande rien). */
  function situationArticle(D, article, siteId) {
    const { besoins = [], mouvements = [], achats = [], seuils = [] } = D;
    const physique = stockPhysique(mouvements, article.id, siteId);
    const reserve = qteReservee(besoins, mouvements, article.id, siteId);
    const disponible = physique - reserve;
    const nonCouverts = besoinsNonCouverts(besoins, mouvements, article.id, siteId);
    const enCommande = qteEnCommande(achats, mouvements, article.id, siteId);
    const couverture = disponible - nonCouverts + enCommande;
    const seuil = seuilActif(seuils, article, siteId);
    const alerte = !!seuil && couverture < num(seuil.pointCommande);
    const proposee = alerte ? Math.ceil(Math.max(num(seuil.cible), num(seuil.pointCommande)) - couverture) : 0;
    return { article, seuil, physique, reserve, disponible, nonCouverts, enCommande, couverture, isole: qteIsolee(mouvements, article.id, siteId),
      rupture: disponible - nonCouverts <= 0 && (nonCouverts > 0 || !!seuil), alerte, proposee };
  }

  /** Récapitulatif « à réapprovisionner » : rupture d'abord, puis article critique, puis écart au point de commande. */
  function aReapprovisionner(D, siteId) {
    return (D.articles || []).filter(a => a.actif !== false).map(a => situationArticle(D, a, siteId)).filter(x => x.alerte)
      .sort((x, y) => (y.rupture - x.rupture) || (!!y.seuil.critique - !!x.seuil.critique)
        || ((num(y.seuil.pointCommande) - y.couverture) - (num(x.seuil.pointCommande) - x.couverture)));
  }

  /** Prix unitaire en MAD HT d'une entrée, ou null si inconnu (un prix inconnu ne vaut jamais zéro). */
  function prixMAD(v) {
    if (!v) return null;
    if (v.prixUnitaireMAD != null && v.prixUnitaireMAD !== '') return num(v.prixUnitaireMAD);
    if ((v.devise || 'MAD') === 'MAD' && v.prixUnitaire != null && v.prixUnitaire !== '') return num(v.prixUnitaire);
    return null; // autre devise sans conversion explicite : non valorisé
  }

  /** CUMP mobile par article et site, rejoué dans l'ordre des dates (V3 §18).
      Entrée valorisée : CUMP = (valeur avant + valeur entrée) / (quantité avant + quantité entrée).
      Sortie : prend le CUMP du moment (coût figé, une livraison postérieure ne le réécrit pas).
      Retour d'une pièce remise : réintègre sa valeur de sortie. Entrée sans prix : quantité « non valorisée ».
      Retourne aussi le coût unitaire figé de chaque mouvement (couts : Map id → coût ou null). */
  function valorisation(mouvements, valorisations, articleId, siteId) {
    const prix = new Map(valorisations.map(v => [v.mouvementId, v]));
    const mv = mouvements.filter(m => surArticleSite(m, articleId, siteId) && num(m.qte) !== 0).sort(parDate);
    let qv = 0, valeur = 0, qnv = 0, provisoire = false;
    const couts = new Map(), sortieParBesoin = new Map();
    const cump = () => qv > 0 ? valeur / qv : null;
    for (const m of mv) {
      const q = num(m.qte);
      if (q > 0) {
        const p = m.type === 'retour' && m.besoinId && sortieParBesoin.has(m.besoinId) ? sortieParBesoin.get(m.besoinId)
          : (m.type === 'entree' || m.type === 'liberation') ? prixMAD(prix.get(m.id) || prix.get(m.isolementId)) : cump();
        if (p == null) { qnv += q; couts.set(m.id, null); continue; }
        if (prix.get(m.id)?.statut === 'provisoire') provisoire = true;
        qv += q; valeur += q * p; couts.set(m.id, p);
      } else {
        const out = -q, c = cump();
        const deValorise = Math.min(out, qv);
        couts.set(m.id, c);
        if (c != null) { valeur -= deValorise * c; qv -= deValorise; if (m.besoinId) sortieParBesoin.set(m.besoinId, c); }
        qnv = Math.max(0, qnv - (out - deValorise));
        if (qv <= 1e-9) { qv = 0; valeur = 0; }
      }
    }
    return { quantite: qv + qnv, quantiteValorisee: qv, quantiteNonValorisee: qnv, valeur, cump: cump(), incomplet: qnv > 0, provisoire, couts };
  }

  /** Consommation moyenne par semaine sur une période (remises et sorties, retours déduits) : aide à proposer un seuil.
      V3 §14 : 2 filtres / semaine × 3 semaines de délai + 2 de sécurité = seuil indicatif de 8. */
  function consommationHebdo(mouvements, articleId, siteId, today, jours = 90) {
    const debut = addDays(today, -jours);
    const m = mouvements.filter(x => surArticleSite(x, articleId, siteId) && (x.le || '').slice(0, 10) > debut && (x.le || '').slice(0, 10) <= today);
    const sorti = m.filter(x => ['remise', 'sortie'].includes(x.type)).reduce((s, x) => s + abs(x.qte), 0)
      - m.filter(x => x.type === 'retour').reduce((s, x) => s + abs(x.qte), 0);
    return Math.max(0, sorti) / (jours / 7);
  }
  const seuilIndicatif = (consoHebdo, delaiJours, securite) => Math.ceil(consoHebdo * (num(delaiJours) / 7) + num(securite));

  /** Montant d'une commande externe (MAD HT) : lignes avec prix connu ; les lignes sans prix sont comptées à part. */
  function montantCommande(achat) {
    let montant = 0, sansPrix = 0;
    for (const l of achat.lignes || []) {
      const p = prixMAD(l), qc = num(l.qteCommandee ?? l.qte);
      if (p == null) sansPrix++; else montant += qc * p;
    }
    return { montant, sansPrix, complet: sansPrix === 0 };
  }

  /** Pièces isolées en attente de décision, isolement par isolement (reste = isolé − libéré − sorti autrement). */
  function isolementsEnAttente(mouvements) {
    const dec = new Map();
    for (const m of mouvements) if (m.isolementId && (m.type === 'liberation' || m.type === 'disposition'))
      dec.set(m.isolementId, (dec.get(m.isolementId) || 0) + (m.type === 'liberation' ? num(m.qte) : num(m.quantite)));
    return mouvements.filter(m => m.type === 'isolement').map(m => ({ m, reste: num(m.quantite) - (dec.get(m.id) || 0) })).filter(x => x.reste > 0)
      .sort((x, y) => (x.m.le || '').localeCompare(y.m.le || ''));
  }

  /** Coût consommé par un besoin : quantité utilisée × coût figé de ses remises (moyenne pondérée), null si inconnu. */
  function coutConsomme(besoin, mouvements, pieces, couts) {
    const rem = remisesDuBesoin(mouvements, besoin.id);
    const q = rem.reduce((s, m) => s + abs(m.qte), 0);
    if (!q || rem.some(m => couts.get(m.id) == null)) return null;
    const cu = rem.reduce((s, m) => s + abs(m.qte) * couts.get(m.id), 0) / q;
    return rapprochementBesoin(besoin, mouvements, pieces).utilise * cu;
  }

  // ---------- volet D : énergie et eau (V3 §19, §20, §36, §37) ----------
  // Compteur : { id, unite, mode: 'cumulatif' | 'periode' | 'instantane', coefficient, frequenceJours, toleranceVariation }.
  // Relevé : { id, compteurId, le, valeur, unite?, estime?, debut? (mode période), remplaceId? (correction),
  //   decision?: 'confirme' | 'invalide' (responsable) }. Rupture = relevé { nature: 'rupture', indexFinal?, indexInitial?,
  //   coefficient? } : remplacement, remise à zéro ou changement de coefficient. Un relevé n'est jamais modifié.
  const UNITES = ['kWh', 'm³', 'L', 'kg', 'Nm³', 'h', 'cycles', '°C', 'bar'];
  const UNITES_RESSOURCE = { electricite: ['kWh'], eau: ['m³'], gasoil: ['L'], fuel: ['L', 'kg'], gaz: ['Nm³', 'kWh', 'kg'],
    air_comprime: ['Nm³', 'm³', 'h'], froid: ['kWh', 'h'], autre: UNITES };
  // Seule une variation inhabituelle peut être confirmée : les autres anomalies se corrigent (nouveau relevé ou rupture).
  const ANOMALIES_CONFIRMABLES = ['variation'];
  const instant = s => (s && s.length === 10 ? s + 'T00:00' : s);
  const finJour = s => (s && s.length === 10 ? addDays(s, 1) + 'T00:00' : s);
  const arrondi = x => (x == null ? null : Math.round(x * 1000) / 1000);
  const jours = minutes => Math.round(minutes / 144) / 10;

  /** Relevés d'un compteur dans l'ordre : retenu, suspect, invalidé, remplacé ou rupture ; et les segments de consommation. */
  function analyserReleves(compteur, releves, { maintenant = null } = {}) {
    const mode = compteur.mode || 'cumulatif';
    const facteur = num(compteur.toleranceVariation) || 3;
    const tous = releves.filter(r => r.compteurId === compteur.id);
    const remplaces = new Set(tous.filter(r => r.remplaceId).map(r => r.remplaceId));
    const ordre = [...tous].sort((a, b) => (a.le || '').localeCompare(b.le || '') || (a.creeLe || '').localeCompare(b.creeLe || ''));
    const lignes = [], segments = [], taux = [];
    let coef = num(compteur.coefficient) || 1;
    let base = null; // dernier point retenu : { le, valeur (cumulatif), coef, estime }
    for (const r of ordre) {
      if (remplaces.has(r.id)) { lignes.push({ releve: r, statut: 'remplace', anomalies: [] }); continue; }
      if (r.nature === 'rupture') {
        if (mode === 'cumulatif' && base && r.indexFinal != null && Number(r.indexFinal) >= base.valeur)
          segments.push({ debut: base.le, fin: r.le, quantite: arrondi((Number(r.indexFinal) - base.valeur) * base.coef), estime: base.estime });
        if (r.coefficient != null && num(r.coefficient) > 0) coef = num(r.coefficient);
        // Sans index initial connu, la nouvelle série commence au prochain relevé : le trou reste visible dans la couverture.
        base = mode === 'cumulatif' ? (r.indexInitial != null ? { le: r.le, valeur: Number(r.indexInitial), coef, estime: false } : null) : { le: r.le, coef };
        lignes.push({ releve: r, statut: 'rupture', anomalies: [] });
        continue;
      }
      const an = [], v = Number(r.valeur);
      let q = null, debut = null;
      if (r.valeur == null || r.valeur === '' || !Number.isFinite(v)) an.push('valeur_invalide');
      if (r.unite && compteur.unite && r.unite !== compteur.unite) an.push('unite');
      if (maintenant && r.le > maintenant) an.push('date_future');
      if (base && r.le === base.le) an.push('doublon');
      if (!an.length && mode === 'cumulatif' && base) {
        if (v < base.valeur) an.push('baisse_index'); else { q = (v - base.valeur) * base.coef; debut = base.le; }
      }
      if (!an.length && mode === 'periode') {
        debut = r.debut ? instant(r.debut) : base?.le || null;
        if (v < 0) an.push('valeur_negative');
        else if (debut && debut >= r.le) an.push('date_incoherente');
        else if (base && debut && debut < base.le) an.push('chevauchement');
        else if (debut) q = v * coef;
      }
      if (!an.length && q != null) {
        const j = minutesBetween(debut, r.le) / 1440, m = mediane(taux);
        if (j > 0 && taux.length >= 3 && m > 0 && (q / j > m * facteur || q / j < m / facteur)) an.push('variation');
      }
      const confirmable = an.length > 0 && an.every(a => ANOMALIES_CONFIRMABLES.includes(a));
      if (r.decision === 'invalide') { lignes.push({ releve: r, statut: 'invalide', anomalies: an }); continue; }
      if (an.length && !(confirmable && r.decision === 'confirme')) { lignes.push({ releve: r, statut: 'suspect', anomalies: an, confirmable }); continue; }
      if (q != null) {
        const j = minutesBetween(debut, r.le) / 1440;
        segments.push({ debut, fin: r.le, quantite: arrondi(q), estime: !!r.estime || !!(mode === 'cumulatif' && base?.estime) });
        if (j > 0) taux.push(q / j);
      }
      base = mode === 'cumulatif' ? { le: r.le, valeur: v, coef, estime: !!r.estime } : { le: r.le, coef };
      lignes.push({ releve: r, statut: 'retenu', anomalies: an });
    }
    return { lignes, segments };
  }

  /** Consommation sur une période demandée : seulement la partie couverte par des relevés, couverture affichée.
   *  Un segment à cheval sur une borne n'est compté que si `prorata` est demandé, et le résultat est alors « estimé ». */
  function consommationPeriode(compteur, releves, du, au, { prorata = false, maintenant = null } = {}) {
    const d0 = instant(du), d1 = finJour(au), total = minutesBetween(d0, d1);
    const a = analyserReleves(compteur, releves, { maintenant });
    const dans = l => l.releve.le >= d0 && l.releve.le < d1;
    const suspects = a.lignes.filter(l => l.statut === 'suspect' && dans(l)).length;
    if (compteur.mode === 'instantane') {
      const v = a.lignes.filter(l => l.statut === 'retenu' && dans(l)).map(l => Number(l.releve.valeur));
      return { mode: 'instantane', unite: compteur.unite, quantite: null, nb: v.length, min: v.length ? Math.min(...v) : null,
        max: v.length ? Math.max(...v) : null, derniere: v.length ? v[v.length - 1] : null, suspects };
    }
    let q = 0, couvert = 0, partiels = 0, estime = false;
    for (const s of a.segments) {
      if (s.fin <= d0 || s.debut >= d1) continue;
      if (s.debut >= d0 && s.fin <= d1) { q += s.quantite; couvert += minutesBetween(s.debut, s.fin); estime = estime || s.estime; continue; }
      partiels++;
      if (!prorata) continue;
      const deb = s.debut > d0 ? s.debut : d0, fin = s.fin < d1 ? s.fin : d1, part = minutesBetween(deb, fin);
      q += s.quantite * part / minutesBetween(s.debut, s.fin); couvert += part; estime = true;
    }
    return { mode: compteur.mode || 'cumulatif', unite: compteur.unite, quantite: couvert > 0 ? arrondi(q) : null,
      couvertureJours: jours(couvert), periodeJours: jours(total), complet: couvert >= total, segmentsPartiels: partiels, estime, suspects };
  }

  /** Point retenu le plus proche d'une date de facture (écart en jours ≤ tolérance), parmi les bornes des segments. */
  function pointProche(segments, date, toleranceJours) {
    let best = null;
    for (const p of new Set(segments.flatMap(s => [s.debut, s.fin]))) {
      const e = Math.abs(daysBetween(p, date));
      if (e <= toleranceJours && (!best || e < best.e)) best = { le: p, e };
    }
    return best?.le || null;
  }

  /** Facturé / mesuré sur l'intervalle exact de la facture (du 15 au 15 n'est pas un mois civil).
   *  Bornes non couvertes par des relevés : « incomplet », jamais un écart certain. */
  function rapprochementFacture(facture, compteurs, releves, { toleranceJours = 1, tolerancePct = 2, maintenant = null } = {}) {
    const liste = compteurs.filter(c => (facture.compteurIds || []).includes(c.id));
    const details = liste.map(c => {
      if (c.unite !== facture.unite) return { compteurId: c.id, mesure: null, manque: 'unite' };
      const { segments } = analyserReleves(c, releves, { maintenant });
      const deb = pointProche(segments, facture.du, toleranceJours), fin = pointProche(segments, facture.au, toleranceJours);
      if (!deb || !fin || fin <= deb) return { compteurId: c.id, mesure: null, debut: deb, fin, manque: !deb ? 'debut' : 'fin' };
      const dedans = segments.filter(s => s.debut >= deb && s.fin <= fin);
      const couvert = dureeUnion(dedans.map(s => [s.debut, s.fin]));
      const mesure = arrondi(dedans.reduce((t, s) => t + s.quantite, 0));
      return { compteurId: c.id, mesure, debut: deb, fin, estime: dedans.some(s => s.estime), manque: couvert < minutesBetween(deb, fin) ? 'continuite' : null };
    });
    const base = { facture: facture.quantite ?? null, unite: facture.unite, details };
    if (!liste.length) return { ...base, statut: 'incomplet', mesure: null, ecart: null, ecartPct: null };
    if (details.some(d => d.manque === 'unite')) return { ...base, statut: 'unites_differentes', mesure: null, ecart: null, ecartPct: null };
    const mesure = arrondi(details.reduce((t, d) => t + (d.mesure || 0), 0));
    if (details.some(d => d.manque) || facture.quantite == null) return { ...base, statut: 'incomplet', mesure, ecart: null, ecartPct: null };
    const ecart = arrondi(Number(facture.quantite) - mesure), ecartPct = mesure ? Math.round(ecart / mesure * 1000) / 10 : null;
    return { ...base, statut: ecartPct != null && Math.abs(ecartPct) <= tolerancePct ? 'concordant' : 'ecart', mesure, ecart, ecartPct,
      estime: details.some(d => d.estime) };
  }

  /** Principal et sous-compteurs ne s'additionnent jamais : résidu = principal − Σ sous-compteurs, « à expliquer ». */
  function residuSousComptage(principal, sous, releves, du, au, { seuilPct = 5, toleranceJours = 1, maintenant = null } = {}) {
    const p = consommationPeriode(principal, releves, du, au, { maintenant });
    const ss = sous.map(c => ({ compteur: c, conso: c.unite === principal.unite ? consommationPeriode(c, releves, du, au, { maintenant }) : null }));
    const horsUnite = ss.filter(x => !x.conso).map(x => x.compteur.id);
    const comparables = p.quantite != null && !horsUnite.length
      && ss.every(x => x.conso.quantite != null && Math.abs(x.conso.couvertureJours - p.couvertureJours) <= toleranceJours);
    if (!comparables) return { statut: 'non_comparable', principal: p, sous: ss, horsUnite, residu: null, residuPct: null };
    const residu = arrondi(p.quantite - ss.reduce((t, x) => t + x.conso.quantite, 0));
    const residuPct = p.quantite ? Math.round(residu / p.quantite * 1000) / 10 : null;
    const statut = residuPct == null ? 'non_comparable' : residuPct < -seuilPct ? 'incoherent' : residuPct > seuilPct ? 'a_expliquer' : 'faible';
    return { statut, principal: p, sous: ss, horsUnite, residu, residuPct };
  }

  /** Totaux par ressource et par unité ; jamais de total toutes énergies confondues. Non mesuré ≠ zéro. */
  function totauxParUnite(lignes) {
    const t = new Map();
    for (const l of lignes) {
      const k = `${l.ressource}|${l.unite}`;
      const x = t.get(k) || { ressource: l.ressource, unite: l.unite, quantite: null, nonMesures: 0 };
      if (l.quantite == null) x.nonMesures++; else x.quantite = arrondi((x.quantite || 0) + Number(l.quantite));
      t.set(k, x);
    }
    return [...t.values()];
  }

  /** Compteurs à relever : dernier relevé (même suspect) + fréquence en jours ≤ aujourd'hui ; jamais relevé = dû. */
  function relevesDus(compteurs, releves, today) {
    return compteurs.filter(c => c.actif !== false && num(c.frequenceJours) > 0).map(c => {
      const der = releves.filter(r => r.compteurId === c.id && r.decision !== 'invalide').reduce((m, r) => (!m || r.le > m ? r.le : m), null);
      const prochaine = der ? addDays(der, num(c.frequenceJours)) : today.slice(0, 10);
      return { compteur: c, dernier: der, prochaine, retardJours: daysBetween(prochaine, today) };
    }).filter(x => x.prochaine <= today.slice(0, 10)).sort((a, b) => b.retardJours - a.retardJours);
  }

  /** Bilan d'une cuve : stock initial + livraisons + transferts entrants − stock final − transferts sortants (même unité). */
  function bilanCombustible({ unite, stockInitial, stockFinal, livraisons = [], transfertsEntrants = [], transfertsSortants = [], usageMesure = null }) {
    const mvts = [...livraisons, ...transfertsEntrants, ...transfertsSortants];
    if (mvts.some(m => m.unite && m.unite !== unite)) return { unite, sorti: null, erreur: 'unites' };
    const manque = [stockInitial == null && 'stock_initial', stockFinal == null && 'stock_final'].filter(Boolean);
    if (manque.length) return { unite, sorti: null, manque };
    const s = l => l.reduce((t, m) => t + num(m.quantite), 0);
    const sorti = arrondi(num(stockInitial) + s(livraisons) + s(transfertsEntrants) - num(stockFinal) - s(transfertsSortants));
    return { unite, sorti, incoherent: sorti < 0, ecartUsage: usageMesure == null ? null : arrondi(sorti - num(usageMesure)) };
  }

  /** Montants de factures par devise ; montant inconnu compté à part, jamais comme zéro. */
  function totalFactures(factures) {
    const t = {};
    let sansMontant = 0;
    for (const f of factures) {
      if (f.montantHT == null || f.montantHT === '') { sansMontant++; continue; }
      const d = f.devise || 'MAD';
      t[d] = arrondi((t[d] || 0) + Number(f.montantHT));
    }
    return { parDevise: t, sansMontant };
  }

  /** Contrôle immédiat d'un relevé avant enregistrement : anomalies que ce relevé aurait parmi les relevés existants. */
  function controleReleve(compteur, releves, candidat, { maintenant = null } = {}) {
    const c = { id: '__candidat__', compteurId: compteur.id, ...candidat };
    const l = analyserReleves(compteur, [...releves, c], { maintenant }).lignes.find(x => x.releve.id === '__candidat__');
    const retenus = analyserReleves(compteur, releves, { maintenant }).lignes.filter(x => x.statut === 'retenu' || x.statut === 'rupture');
    const precedent = [...retenus].reverse().find(x => x.releve.nature !== 'rupture' && (x.releve.le || '') < (c.le || '')) || null;
    return { anomalies: l?.anomalies || [], confirmable: !!l?.confirmable, precedent: precedent?.releve || null };
  }

  /** Préventif selon l'usage (heures, cycles…) : usage depuis la dernière réalisation, reste, alerte, date estimée.
   *  Programme : { compteurId, intervalleCompteur, margeCompteur, dernierIndex, derniereRealisation }.
   *  Usage = dernier index retenu − index de la dernière réalisation (même série) ; après un remplacement de compteur,
   *  somme des consommations relevées depuis la réalisation. Inconnu si aucun relevé depuis. */
  function echeanceCompteur(programme, compteur, releves, today, { maintenant = null } = {}) {
    const pas = num(programme.intervalleCompteur);
    if (!compteur || !pas) return { statut: 'inconnu', raison: 'compteur ou pas manquant' };
    const a = analyserReleves(compteur, releves, { maintenant });
    const retenus = a.lignes.filter(l => l.statut === 'retenu').map(l => l.releve);
    const dernier = retenus[retenus.length - 1] || null;
    const ref = programme.derniereRealisation ? instant(programme.derniereRealisation) : null;
    const coef = num(compteur.coefficient) || 1;
    const ruptureApres = a.lignes.some(l => l.statut === 'rupture' && (!ref || l.releve.le > ref));
    let usage = null;
    if (dernier && programme.dernierIndex != null && programme.dernierIndex !== '' && !ruptureApres && (!ref || dernier.le >= ref))
      usage = (Number(dernier.valeur) - num(programme.dernierIndex)) * coef;
    else if (ref) {
      const segs = a.segments.filter(s => s.debut >= ref);
      if (segs.length) usage = segs.reduce((t, s) => t + s.quantite, 0);
    }
    if (usage == null) return { statut: 'inconnu', raison: 'aucun relevé depuis la dernière réalisation', dernier, intervalle: pas };
    usage = arrondi(usage);
    const reste = arrondi(pas - usage), marge = num(programme.margeCompteur);
    // Rythme : consommations des relevés retenus sur les 60 derniers jours.
    const debutFenetre = addDays(today, -60) + 'T00:00';
    const recents = a.segments.filter(s => s.fin >= debutFenetre);
    const jours = recents.reduce((t, s) => t + minutesBetween(s.debut, s.fin) / 1440, 0);
    // Pas d'estimation sur moins de 7 jours de relevés (deux relevés à quelques minutes d'écart donneraient n'importe quoi).
    const rythme = jours >= 7 ? recents.reduce((t, s) => t + s.quantite, 0) / jours : null;
    const dateEstimee = reste <= 0 ? today : rythme > 0 ? addDays(dernier ? dernier.le.slice(0, 10) : today, Math.ceil(reste / rythme)) : null;
    return { statut: reste <= 0 ? 'atteint' : reste <= marge ? 'alerte' : 'ok', usage, reste, intervalle: pas, marge, echeanceIndex: programme.dernierIndex != null ? arrondi(num(programme.dernierIndex) + pas / coef) : null,
      dernier, rythme: rythme == null ? null : arrondi(rythme), dateEstimee };
  }

  /** Bornes d'un mois « AAAA-MM » (dates incluses) et mois décalé de n. */
  function bornesMois(ym) {
    const [y, m] = ym.split('-').map(Number);
    const fin = new Date(Date.UTC(y, m, 0)).getUTCDate();
    return { du: `${ym}-01`, au: `${ym}-${String(fin).padStart(2, '0')}` };
  }
  function moisDecale(ym, n) {
    const [y, m] = ym.split('-').map(Number), t = y * 12 + (m - 1) + n;
    return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, '0')}`;
  }

  /** Tableau Énergie d'une période : consommation de chaque compteur (avec couverture), totaux par ressource et unité
   *  sur les compteurs principaux seulement (un sous-compteur n'est jamais ajouté à son principal), résidus des
   *  sous-comptages. Les compteurs d'équipement (heures, cycles) n'y figurent pas. */
  function tableauEnergie(compteurs, releves, du, au, { maintenant = null } = {}) {
    const liste = compteurs.filter(c => c.usage !== 'equipement' && c.actif !== false);
    const ids = new Set(liste.map(c => c.id));
    const parent = c => (c.parentId && ids.has(c.parentId) && c.parentId !== c.id ? c.parentId : null);
    const enfants = id => liste.filter(c => parent(c) === id);
    const parCompteur = new Map(liste.map(c => [c.id, consommationPeriode(c, releves, du, au, { maintenant })]));
    // Ordre d'affichage : chaque principal suivi de ses sous-compteurs (en profondeur).
    const lignes = [], vus = new Set();
    const ajouter = (c, niveau) => {
      if (vus.has(c.id)) return;
      vus.add(c.id);
      lignes.push({ compteur: c, conso: parCompteur.get(c.id), niveau, parentId: parent(c) });
      enfants(c.id).forEach(x => ajouter(x, niveau + 1));
    };
    liste.filter(c => !parent(c)).forEach(c => ajouter(c, 0));
    liste.forEach(c => ajouter(c, 0)); // boucle de parenté éventuelle : affichée quand même
    const totaux = totauxParUnite(lignes.filter(l => l.niveau === 0 && l.conso.mode !== 'instantane')
      .map(l => ({ ressource: l.compteur.ressource || 'autre', unite: l.compteur.unite, quantite: l.conso.quantite })));
    const sousComptages = liste.filter(c => enfants(c.id).length).map(c => ({ ...residuSousComptage(c, enfants(c.id), releves, du, au, { maintenant }), compteur: c }));
    return { lignes, totaux, sousComptages, suspects: lignes.reduce((t, l) => t + (l.conso.suspects || 0), 0) };
  }

  /** Données énergie et eau de la démo — une seule définition : démo de l'appli (energie.js) et démos du serveur
   *  (supabase/demo_energie.sql, généré par scripts/generer_demo_energie.py). J(n, 'HH:MM') = date relative à aujourd'hui,
   *  K(suffixe) = identifiant, comp = id du compresseur. Un relevé tous les 7 jours sur 9 semaines.
   *  Scénario : arrivée générale + 3 sous-compteurs (résidu ≈ 7 % « à expliquer »), compteur de la ligne remplacé il y a
   *  30 jours, eau avec une lecture erronée (4 718 au lieu de 3 718 : à examiner), heures du compresseur (vidange
   *  2 000 h en alerte), factures ONEE concordante puis en écart (+6 %), facture d'eau. */
  function demoEnergie(J, K, comp) {
    const out = [], qui = ['Technicien A (mécanique)', 'Technicien B (automatisme)'];
    const C = (k, o) => { out.push(['compteurs', { id: K(k), coefficient: 1, frequenceJours: 7, mode: 'cumulatif', actif: true, ...o }]); return K(k); };
    const gen = C('cg', { code: 'ELEC-GEN', libelle: 'Électricité — arrivée générale', usage: 'ressource', ressource: 'electricite', unite: 'kWh' });
    const cco = C('cc', { code: 'ELEC-COMP', libelle: 'Électricité — compresseur', usage: 'ressource', ressource: 'electricite', unite: 'kWh', parentId: gen, equipementId: comp });
    const cat = C('ca', { code: 'ELEC-AT', libelle: 'Électricité — atelier presses', usage: 'ressource', ressource: 'electricite', unite: 'kWh', parentId: gen });
    const clg = C('cl', { code: 'ELEC-LG', libelle: 'Électricité — ligne conditionnement', usage: 'ressource', ressource: 'electricite', unite: 'kWh', parentId: gen });
    const eau = C('ce', { code: 'EAU-GEN', libelle: 'Eau de ville', usage: 'ressource', ressource: 'eau', unite: 'm³' });
    const hrs = C('ch', { code: 'HRS-COMP01', libelle: 'Heures de marche compresseur', usage: 'equipement', unite: 'h', equipementId: comp, frequenceJours: 1 }); // relevé dû chaque jour : « Relevés à faire » du technicien
    let n = 0;
    const R = (cpt, j, hm, o) => { const le = J(j, hm); n++; out.push(['releves', { id: K('r' + n), compteurId: cpt, le, creeLe: le, creePar: qui[n % 2], ...o }]); };
    const serie = (cpt, unite, depart, incs, hm, special = {}) => {
      let v = depart;
      for (let i = 0; i <= incs.length; i++) {
        if (special[i]) special[i](v); else R(cpt, -64 + 7 * i, hm, { valeur: v, unite });
        if (i < incs.length) v += incs[i];
      }
    };
    serie(gen, 'kWh', 120000, [6100, 5900, 6300, 6050, 6200, 5800, 6400, 6150, 6000], '08:00');
    serie(cco, 'kWh', 45000, [2350, 2280, 2420, 2300, 2390, 2250, 2460, 2370, 2310], '08:04');
    serie(cat, 'kWh', 80000, [2100, 2050, 2180, 2120, 2150, 2000, 2230, 2140, 2090], '08:07');
    // Ligne : compteur remplacé il y a 31 jours (ancien index final connu, nouveau compteur à 0).
    const lg = [1220, 1160, 1260, 1200, 1230, 1150, 1270, 1210, 1180];
    let v = 30500;
    for (let i = 0; i <= 4; i++) { R(clg, -64 + 7 * i, '08:10', { valeur: v, unite: 'kWh' }); if (i < 4) v += lg[i]; }
    n++;
    out.push(['releves', { id: K('r' + n), compteurId: clg, nature: 'rupture', typeRupture: 'remplacement', le: J(-31, '10:00'), creeLe: J(-31, '10:00'), creePar: 'Responsable maintenance',
      indexFinal: v + 900, indexInitial: 0, motif: 'Compteur défectueux remplacé par l’électricien' }]);
    v = 330;
    for (let i = 5; i <= 9; i++) { R(clg, -64 + 7 * i, '08:10', { valeur: v, unite: 'kWh' }); if (i < 9) v += lg[i]; }
    // Eau : le relevé d'il y a 15 jours a été mal lu (4 718 au lieu de 3 718) : à examiner, exclu des calculs.
    serie(eau, 'm³', 3400, [44, 47, 43, 46, 45, 48, 45, 44, 46], '08:15', { 7: () => R(eau, -15, '08:15', { valeur: 4718, unite: 'm³' }) });
    serie(hrs, 'h', 11800, [112, 108, 115, 110, 105, 118, 111, 109, 114], '08:20');
    out.push(['programmes', { id: K('pg3'), equipementId: comp, compteurId: hrs, libelle: 'Vidange compresseur selon les heures', modele: 'entretien', intervalleCompteur: 2000, margeCompteur: 200,
      dernierIndex: 10850, derniereRealisation: J(-120, '10:00'), regle: 'apres_realisation', instruction: 'Vidange, filtre à huile et séparateur, toutes les 2 000 h de marche.', actif: true }]);
    const F = (k, o) => out.push(['factures_energie', { id: K(k), devise: 'MAD', creePar: 'Responsable maintenance', ...o }]);
    F('f1', { ressource: 'electricite', fournisseur: 'ONEE', reference: 'FAC-ONEE-0001', du: J(-64), au: J(-36), quantite: 24540, unite: 'kWh', montantHT: 28957.2, compteurIds: [gen], creeLe: J(-34, '11:00') });
    F('f2', { ressource: 'electricite', fournisseur: 'ONEE', reference: 'FAC-ONEE-0002', du: J(-36), au: J(-8), quantite: 26100, unite: 'kWh', montantHT: 30798, compteurIds: [gen], creeLe: J(-6, '11:00') });
    F('f3', { ressource: 'eau', fournisseur: 'Régie de distribution', reference: 'FAC-EAU-0001', du: J(-64), au: J(-8), quantite: 362, unite: 'm³', montantHT: 3439, compteurIds: [eau], creeLe: J(-6, '11:30') });
    return out;
  }

  // ---------- lot R3 : membres, équipes, sociétés, habilitations ----------
  /** Nom comparable : sans accents, sans casse, espaces réduits (détection des doublons). */
  const nomComparable = s => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
  /** Membres actifs portant le même nom (hors le membre lui-même). */
  const doublonsNom = (nom, membres, sauf) => !nomComparable(nom) ? [] :
    membres.filter(m => m.id !== sauf && m.actif !== false && nomComparable(m.nom) === nomComparable(nom));
  /** Habilitation échue : échéance (AAAA-MM-JJ) passée au jour donné. */
  const habilitationEchue = (h, jour) => !!(h && h.echeance && String(h.echeance).slice(0, 10) < String(jour).slice(0, 10));
  const habilitationsEchues = (m, jour) => ((m && m.habilitations) || []).filter(h => habilitationEchue(h, jour));
  /** Équipes actives dont le membre fait partie (une seule source : l'équipe). */
  const equipesDe = (personneId, equipes) => !personneId ? [] :
    equipes.filter(e => e.actif !== false && ((e.membreIds || []).includes(personneId) || e.chefId === personneId));
  /** Intervention confiée à une personne : intervenant actif, ou confiée à sa société (prestataire). */
  const otConfiee = (o, { personneId, societeId } = {}) =>
    ((o.intervenants || []).some(i => !i.fin && i.personneId === personneId) && !!personneId) || (!!societeId && o.societeId === societeId);
  /** Intervention confiée à l'une des équipes données. */
  const otDeMesEquipes = (o, equipeIds) => !!o.equipeId && (equipeIds || []).includes(o.equipeId);

  // ---------- lot S1 : listes fusionnées élément par élément (miroir de supabase/stabilite_s1.sql) ----------
  /** Clé d'un élément : son id (objet), sa valeur (texte, nombre, booléen) ; null sinon. */
  const cleElement = e => e === null || e === undefined || Array.isArray(e) ? null
    : typeof e === 'object' ? (e.id === null || e.id === undefined ? null : String(e.id)) : String(e);
  const listeFusionnable = a => Array.isArray(a) && a.every(x => cleElement(x) !== null);
  /** Changements d'une liste : clés ajoutées ou modifiées, clés retirées ; null si la liste ne se fusionne pas. */
  function decrireListe(avant, apres) {
    if (!listeFusionnable(avant) || !listeFusionnable(apres)) return null;
    const av = new Map(avant.map(x => [cleElement(x), JSON.stringify(x)]));
    const ap = new Set(apres.map(cleElement));
    return { modifies: apres.filter(x => av.get(cleElement(x)) !== JSON.stringify(x)).map(cleElement), retraits: [...av.keys()].filter(k => !ap.has(k)) };
  }
  /** Applique un patch (et sa description « $listes ») à une fiche, comme le serveur : renvoie le patch fusionné. */
  function fusionPatch(d, patch) {
    const { $listes: listes, ...p } = patch || {};
    if (!d) return p;
    for (const [k, b] of Object.entries(p)) {
      const a = d[k];
      if (!listeFusionnable(a) || !listeFusionnable(b)) continue;
      const m = listes && typeof listes[k] === 'object' && listes[k] ? listes[k] : {};
      const rem = new Set((m.retraits || []).map(String));
      const mod = new Set(Array.isArray(m.modifies) ? m.modifies.map(String) : b.map(cleElement));
      const parCle = new Map();
      for (const x of b) if (!parCle.has(cleElement(x))) parCle.set(cleElement(x), x);
      const res = [], vus = new Set();
      for (const e of a) {
        const c = cleElement(e);
        if (vus.has(c)) continue;
        vus.add(c);
        if (rem.has(c)) continue;
        res.push(mod.has(c) && parCle.has(c) ? parCle.get(c) : e);
      }
      for (const e of b) {
        const c = cleElement(e);
        if (vus.has(c) || rem.has(c) || !mod.has(c)) continue;
        vus.add(c);
        res.push(e);
      }
      p[k] = res;
    }
    return p;
  }

  const Calculs = { cleElement, listeFusionnable, decrireListe, fusionPatch, nomComparable, doublonsNom, habilitationEchue, habilitationsEchues, equipesDe, otConfiee, otDeMesEquipes, demoEnergie, bornesMois, moisDecale, tableauEnergie, controleReleve, echeanceCompteur, UNITES, UNITES_RESSOURCE, ANOMALIES_CONFIRMABLES, analyserReleves, consommationPeriode, rapprochementFacture, residuSousComptage, totauxParUnite, relevesDus, bilanCombustible, totalFactures,
    montantCommande, isolementsEnAttente, consommationHebdo, seuilIndicatif, seuilActif, besoinsNonCouverts, receptionLigne, etatAchat, qteEnCommande, qteIsolee, situationArticle, aReapprovisionner, prixMAD, valorisation, coutConsomme, besoinsAServir, attentesALever, piecesDetenues, stockPhysique, qteReservee, stockDisponible, etatBesoin, rapprochementBesoin, retraitsAVerifier, qteRemise, addDays, daysBetween, minutesBetween, dureeUnion, mediane, NATURE_DU_BESOIN, ETAT_RANK, otOuvert, demandeOuverte, indexOtsParDemande, etatEquipement, verifierCloture, qualification, typeArret, typeArretPropose, aQualifier, ETAT_SIGNALE, echeanceSuivante, indicateurs };
  if (typeof module === 'object' && module.exports) module.exports = Calculs; else root.Calculs = Calculs;
})(this);
