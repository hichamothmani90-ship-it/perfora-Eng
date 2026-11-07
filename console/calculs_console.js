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

  const Console = { mensuel, etat, alertes, synthese, prolonger, iceValide, ETAPES_MES };
  if (typeof module === 'object' && module.exports) module.exports = Console; else root.CalculsConsole = Console;
})(this);
