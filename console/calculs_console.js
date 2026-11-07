/* Centre de contrôle — calculs du tableau de bord, sans accès au réseau (testés : tests/console.test.js).
   Client = ligne rendue par pf_clients() : { id, code, nom, demo, statut, abonnement: { pack, statut, fin, debut, prix,
   periodicite, remisePct, ecriture }, actifs, activite7j, derniereActivite, miseEnService }.
   Règles : un prix inconnu n'est jamais compté comme 0 ; une démonstration n'est ni un client ni un revenu. */
(function (root) {
  const jours = (a, b) => Math.round((Date.parse(b.slice(0, 10)) - Date.parse(a.slice(0, 10))) / 864e5);
  const arrondi = x => (x == null ? null : Math.round(x * 100) / 100);

  /** Revenu mensuel récurrent d'un abonnement (HT, MAD) : prix de la période, remise déduite, ramené au mois. */
  function mensuel(abo) {
    if (!abo || abo.prix == null || abo.prix === '') return null;
    const net = Number(abo.prix) * (1 - (Number(abo.remisePct) || 0) / 100);
    return arrondi(abo.periodicite === 'annuel' ? net / 12 : net);
  }

  /** État commercial : demo, essai, actif, echu (date de fin dépassée), suspendu, resilie. */
  function etat(c, today) {
    if (c.demo) return 'demo';
    const a = c.abonnement || {};
    const s = a.statutAbonnement || a.statut || c.statut;
    if (s === 'suspendu' || s === 'resilie') return s;
    if (a.fin && a.fin.slice(0, 10) < today) return 'echu';
    return s === 'essai' ? 'essai' : 'actif';
  }

  const ETAPES_MES = ['kit_envoye', 'kit_recu', 'import', 'responsable_invite', 'qr_imprimes', 'equipe_invitee', 'mise_en_service'];

  /** Alertes à traiter, de la plus urgente à la moins urgente. */
  function alertes(clients, today) {
    const out = [];
    for (const c of clients) {
      const e = etat(c, today), a = c.abonnement || {};
      if (e === 'demo' || e === 'resilie') continue;
      const reste = a.fin ? jours(today, a.fin) : null;
      if (e === 'echu') out.push({ niveau: 1, type: 'echu', client: c, texte: `Échéance dépassée depuis ${-reste} j : lecture seule pour le client` });
      else if (e === 'essai' && reste != null && reste <= 7) out.push({ niveau: 1, type: 'fin_essai', client: c, texte: reste === 0 ? 'Essai : dernier jour' : `Essai : fin dans ${reste} j` });
      else if (e === 'actif' && reste != null && reste <= 30) out.push({ niveau: 2, type: 'echeance', client: c, texte: `Échéance dans ${reste} j (${a.fin.slice(0, 10)})` });
      if (e === 'essai' && !a.fin) out.push({ niveau: 2, type: 'essai_sans_fin', client: c, texte: 'Essai sans date de fin' });
      if (e === 'actif' && mensuel(a) == null) out.push({ niveau: 3, type: 'sans_prix', client: c, texte: 'Abonnement actif sans prix convenu' });
      if ((e === 'actif' || e === 'essai') && c.derniereActivite && jours(String(c.derniereActivite), today) >= 7)
        out.push({ niveau: 2, type: 'inactif', client: c, texte: `Aucune saisie depuis ${jours(String(c.derniereActivite), today)} j` });
      if ((e === 'actif' || e === 'essai') && !c.derniereActivite) {
        const faites = ETAPES_MES.filter(k => (c.miseEnService || {})[k]).length;
        out.push({ niveau: 3, type: 'demarrage', client: c, texte: `Pas encore utilisé · mise en service ${faites}/${ETAPES_MES.length}` });
      }
    }
    return out.sort((x, y) => x.niveau - y.niveau || (x.client.nom || '').localeCompare(y.client.nom || ''));
  }

  /** Synthèse : nombres par état, revenu mensuel (prix connus seulement) et nombre de clients payants sans prix. */
  function synthese(clients, today) {
    const parEtat = { actif: 0, essai: 0, echu: 0, suspendu: 0, resilie: 0, demo: 0 };
    let mrr = 0, sansPrix = 0, echeances30 = 0, inactifs = 0;
    for (const c of clients) {
      const e = etat(c, today);
      parEtat[e]++;
      if (e === 'actif') { const m = mensuel(c.abonnement); if (m == null) sansPrix++; else mrr += m; }
      const fin = c.abonnement?.fin;
      if ((e === 'actif' || e === 'essai') && fin && jours(today, fin) <= 30) echeances30++;
      if ((e === 'actif' || e === 'essai') && c.derniereActivite && jours(String(c.derniereActivite), today) >= 7) inactifs++;
    }
    return { parEtat, clients: parEtat.actif + parEtat.essai + parEtat.echu + parEtat.suspendu, mrr: arrondi(mrr), arr: arrondi(mrr * 12), sansPrix, echeances30, inactifs };
  }

  /** Nouvelle date de fin en prolongeant d'un mois ou d'un an, depuis la fin actuelle (ou aujourd'hui si dépassée). */
  function prolonger(fin, today, duree) {
    const base = fin && fin.slice(0, 10) >= today ? fin.slice(0, 10) : today;
    const [y, m, d] = base.split('-').map(Number);
    const mois = duree === 'annuel' ? 12 : 1;
    const cible = new Date(Date.UTC(y, m - 1 + mois, 1));
    const dernier = new Date(Date.UTC(cible.getUTCFullYear(), cible.getUTCMonth() + 1, 0)).getUTCDate();
    cible.setUTCDate(Math.min(d, dernier));
    return cible.toISOString().slice(0, 10);
  }

  /** ICE marocain : 15 chiffres (vide accepté). */
  const iceValide = s => !s || /^[0-9]{15}$/.test(String(s).trim());

  // ---------- CC2 : prospects, support, communication ----------
  const ETAPES_PROSPECT = ['nouveau', 'contacte', 'demo_prevue', 'demo_faite', 'essai', 'gagne', 'perdu'];
  const PROSPECT_OUVERT = p => !['gagne', 'perdu'].includes(p.etape || 'nouveau');
  const TICKET_OUVERT = t => !['resolue', 'fermee'].includes(t.statut || 'ouverte');

  /** Numéro pour wa.me : chiffres seuls, indicatif international ; 06… / 07… / 05… marocains → 212… ; null si inutilisable. */
  function numeroWhatsApp(tel) {
    if (!tel) return null;
    let d = String(tel).replace(/[^0-9+]/g, '');
    if (d.startsWith('+')) d = d.slice(1);
    else if (d.startsWith('00')) d = d.slice(2);
    else if (/^0[5-7][0-9]{8}$/.test(d)) d = '212' + d.slice(1);
    d = d.replace(/[^0-9]/g, '');
    return d.length >= 10 && d.length <= 15 ? d : null;
  }
  const lienWhatsApp = (tel, texte) => { const n = numeroWhatsApp(tel); return n ? `https://wa.me/${n}${texte ? '?text=' + encodeURIComponent(texte) : ''}` : null; };

  /** Remplit un modèle : {contact} {entreprise} {fin} {montant} {lien}. Une variable sans valeur reste visible et est signalée. */
  function remplir(texte, vars) {
    const manquantes = [];
    const out = String(texte || '').replace(/\{(\w+)\}/g, (m, k) => {
      const v = vars[k];
      if (v == null || v === '') { manquantes.push(k); return m; }
      return String(v);
    });
    return { texte: out, manquantes: [...new Set(manquantes)] };
  }

  /** Prospects à relancer : ouverts dont la prochaine action est due (ou sans prochaine action), les plus en retard d'abord. */
  function aRelancer(prospects, today) {
    return prospects.filter(PROSPECT_OUVERT).map(p => ({ p, du: p.prochaineAction?.date || null }))
      .filter(x => !x.du || x.du.slice(0, 10) <= today)
      .map(x => ({ ...x, retard: x.du ? jours(x.du, today) : null }))
      .sort((a, b) => (a.du == null) - (b.du == null) || (b.retard ?? 0) - (a.retard ?? 0));
  }

  /** Nombre de prospects par étape. */
  const pipeline = prospects => Object.fromEntries(ETAPES_PROSPECT.map(e => [e, prospects.filter(p => (p.etape || 'nouveau') === e).length]));

  const PRIO = { urgente: 0, haute: 1, normale: 2, basse: 3 };
  /** Demandes de support ouvertes : en retard d'abord, puis par priorité, puis les plus anciennes. */
  function supportOuvert(tickets, today) {
    return tickets.filter(TICKET_OUVERT).map(t => ({ t, enRetard: !!(t.echeance && t.echeance.slice(0, 10) < today), age: t.creeLe ? jours(String(t.creeLe), today) : 0 }))
      .sort((a, b) => b.enRetard - a.enRetard || PRIO[a.t.priorite || 'normale'] - PRIO[b.t.priorite || 'normale'] || b.age - a.age);
  }

  const Console = { mensuel, etat, alertes, synthese, prolonger, iceValide, ETAPES_MES, ETAPES_PROSPECT, PROSPECT_OUVERT, TICKET_OUVERT,
    numeroWhatsApp, lienWhatsApp, remplir, aRelancer, pipeline, supportOuvert };
  if (typeof module === 'object' && module.exports) module.exports = Console; else root.CalculsConsole = Console;
})(this);
