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

  const Calculs = { montantCommande, isolementsEnAttente, consommationHebdo, seuilIndicatif, seuilActif, besoinsNonCouverts, receptionLigne, etatAchat, qteEnCommande, qteIsolee, situationArticle, aReapprovisionner, prixMAD, valorisation, coutConsomme, besoinsAServir, attentesALever, piecesDetenues, stockPhysique, qteReservee, stockDisponible, etatBesoin, rapprochementBesoin, retraitsAVerifier, qteRemise, addDays, daysBetween, minutesBetween, dureeUnion, mediane, NATURE_DU_BESOIN, ETAT_RANK, otOuvert, demandeOuverte, indexOtsParDemande, etatEquipement, verifierCloture, echeanceSuivante, indicateurs };
  if (typeof module === 'object' && module.exports) module.exports = Calculs; else root.Calculs = Calculs;
})(this);
