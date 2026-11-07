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
  let clients = [], tarifs = [], prospects = [], tickets = [], echanges = [], modeles = [], annonces = [];
  async function charger() {
    [clients, tarifs, prospects, tickets, echanges, modeles, annonces] = await Promise.all([Sync.pf.clients(), Sync.pf.tarifs(),
      Sync.pf.objets('prospect'), Sync.pf.objets('ticket'), Sync.pf.objets('echange'), Sync.pf.objets('modele'), Sync.pf.annonces()]);
  }
  const prospect = id => prospects.find(x => x.id === id);
  const ticket = id => tickets.find(x => x.id === id);
  const ETAPE = { nouveau: ['Nouveau', ''], contacte: ['Contacté', 'blue'], demo_prevue: ['Démo prévue', 'blue'], demo_faite: ['Démo faite', 'blue'], essai: ['Essai', 'amber'], gagne: ['Gagné', 'green'], perdu: ['Perdu', 'red'] };
  const SOURCES = { site: 'Site web', whatsapp: 'WhatsApp', parrainage: 'Parrainage', salon: 'Salon, événement', appel: 'Appel entrant', reseau: 'Réseau personnel', linkedin: 'LinkedIn', autre: 'Autre' };
  const STATUT_T = { ouverte: ['Ouverte', 'amber'], en_cours: ['En cours', 'blue'], en_attente_client: ['Attente client', ''], resolue: ['Résolue', 'green'], fermee: ['Fermée', ''] };
  const PRIO_T = { urgente: ['Urgente', 'red'], haute: ['Haute', 'amber'], normale: ['Normale', ''], basse: ['Basse', ''] };
  const NATURE = { question: 'Question', anomalie: 'Anomalie', evolution: 'Évolution', facturation: 'Facturation' };
  const CANAL = { whatsapp: 'WhatsApp', email: 'E-mail', telephone: 'Téléphone', rencontre: 'Rencontre', autre: 'Autre' };
  const echangesDe = (cle, val) => echanges.filter(e => (cle === 'entreprise' ? e.entrepriseId === val && !e.prospectId : e[cle] === val));
  const listeEchanges = l => l.length ? `<ul class="lines">${l.map(e => `<li style="flex-wrap:wrap"><span class="grow"><b>${esc(CANAL[e.canal] || e.canal)}</b> · ${e.sens === 'entrant' ? 'reçu' : 'envoyé'} · <span class="small muted">${fmtD(e.date || e.creeLe)}</span><br><span style="white-space:pre-wrap">${esc(e.resume)}</span></span></li>`).join('')}</ul>` : '<p class="muted small" style="margin:0">Aucun échange noté.</p>';
  let messagePret = null; // { cible, lien, canal, texte } : lien WhatsApp ou e-mail à ouvrir d'un clic
  const client = id => clients.find(c => c.id === id);
  const tarifDe = pack => tarifs.find(t => t.pack === pack) || {};

  // ---------- vues ----------
  const V = {};

  V.tableau = () => {
    const t = today(), s = K.synthese(clients, t), al = K.alertes(clients, t), rel = K.aRelancer(prospects, t), sup = K.supportOuvert(tickets, t);
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
        <a class="tile ${rel.length ? 'amber' : ''}" href="#/prospects"><b>${rel.length}</b><span>Prospects à relancer</span></a>
        <a class="tile ${sup.some(x => x.enRetard) ? 'red' : sup.length ? 'amber' : ''}" href="#/support"><b>${sup.length}</b><span>Demandes de support ouvertes</span></a>
      </div>
      <h2>À traiter</h2>
      <div class="card" style="padding:0">${al.length ? al.map(a => `<div class="cc-alerte">${badge(...NIV[a.niveau])}<a href="#/client/${a.client.id}"><b>${esc(a.client.nom)}</b></a><span class="grow">${esc(a.texte)}</span></div>`).join('')
        : '<p class="muted" style="margin:0;padding:14px">Rien à traiter.</p>'}</div>
      ${sup.length ? `<h2>Support ouvert</h2><div class="card" style="padding:0">${sup.slice(0, 8).map(({ t: k, enRetard }) => `<div class="cc-alerte">${badge(...PRIO_T[k.priorite || 'normale'])}<a href="#/ticket/${k.id}"><b>${esc(k.ref)}</b></a><span class="grow">${esc(client(k.entrepriseId)?.nom || '')} · ${esc(k.sujet)}</span>${enRetard ? badge('en retard', 'red') : ''}</div>`).join('')}</div>` : ''}
      ${rel.length ? `<h2>Prospects à relancer</h2><div class="card" style="padding:0">${rel.slice(0, 8).map(({ p: x, retard }) => `<div class="cc-alerte">${badge(...ETAPE[x.etape || 'nouveau'])}<a href="#/prospect/${x.id}"><b>${esc(x.societe || x.nom)}</b></a><span class="grow">${esc(x.prochaineAction?.texte || 'Prochaine action à fixer')}</span><span class="small muted">${retard == null ? '' : retard > 0 ? `en retard de ${retard} j` : 'aujourd’hui'}</span></div>`).join('')}</div>` : ''}
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
          <h2>Échanges</h2>
          ${blocMessagePret('client', c.id)}
          <div class="card">${listeEchanges(echangesDe('entreprise', c.id))}
            <div class="actions" style="margin-bottom:0"><button class="btn sm primary" data-action="message" data-cible="client" data-id="${c.id}">Envoyer un message</button><button class="btn sm" data-action="echange" data-cible="client" data-id="${c.id}">Noter un échange</button></div></div>
          <h2>Support</h2>
          <div class="card">${(() => { const l = tickets.filter(k => k.entrepriseId === c.id); return l.length ? `<ul class="lines">${l.map(k => `<li><a class="grow" href="#/ticket/${k.id}"><b>${esc(k.ref)}</b> ${esc(k.sujet)}</a>${badge(...STATUT_T[k.statut || 'ouverte'])}</li>`).join('')}</ul>` : '<p class="muted small" style="margin:0">Aucune demande.</p>'; })()}
            <div class="actions" style="margin-bottom:0"><button class="btn sm" data-action="ticket-nouveau" data-id="${c.id}">+ Demande de support</button></div></div>
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

  function blocMessagePret(cible, id) {
    if (!messagePret || messagePret.cible !== cible || messagePret.id !== id) return '';
    return `<div class="card" style="border-color:var(--blue)"><p style="margin-top:0"><b>Message prêt</b> pour ${esc(messagePret.destinataire)} :</p><p class="small" style="white-space:pre-wrap">${esc(messagePret.texte)}</p>
      <div class="actions" style="margin-bottom:0"><a class="btn primary" id="cc-envoyer" target="_blank" rel="noopener" href="${esc(messagePret.lien)}">${messagePret.canal === 'whatsapp' ? 'Ouvrir WhatsApp' : 'Ouvrir l’e-mail'}</a><button class="btn ghost" data-action="message-annuler">Annuler</button></div>
      <p class="small muted" style="margin-bottom:0">Le message s’ouvre dans ${messagePret.canal === 'whatsapp' ? 'WhatsApp' : 'votre messagerie'} : c’est vous qui l’envoyez. L’échange est noté dans l’historique au clic.</p></div>`;
  }

  V.prospects = r => {
    const f = r.q.get('f') || 'ouverts', t = today(), pipe = K.pipeline(prospects);
    const liste = prospects.filter(x => f === 'tous' || (f === 'ouverts' ? K.PROSPECT_OUVERT(x) : (x.etape || 'nouveau') === f))
      .sort((a, b) => (a.prochaineAction?.date || '9999').localeCompare(b.prochaineAction?.date || '9999'));
    return `<h1>Prospects</h1>
      <div class="cc-outils">${[['ouverts', 'En cours'], ...K.ETAPES_PROSPECT.map(e => [e, ETAPE[e][0]]), ['tous', 'Tous']].map(([k, l]) => `<a class="btn sm ${f === k ? 'primary' : 'ghost'}" href="#/prospects?f=${k}">${esc(l)}${pipe[k] != null ? ` · ${pipe[k]}` : ''}</a>`).join('')}
        <span class="grow"></span><button class="btn primary sm" data-action="prospect-nouveau">+ Prospect</button></div>
      <table class="cc-table"><thead><tr><th>Prospect</th><th>Secteur, ville</th><th>Source</th><th>Étape</th><th>Prochaine action</th><th>Dernier échange</th></tr></thead>
      <tbody>${liste.map(x => {
        const d = x.prochaineAction?.date, retard = d && d < t;
        const der = echangesDe('prospectId', x.id)[0];
        return `<tr class="lien" data-href="#/prospect/${x.id}"><td><b>${esc(x.societe || '—')}</b><br><span class="small muted">${esc(x.nom || '')}${x.fonction ? ' · ' + esc(x.fonction) : ''}</span></td>
          <td class="small">${esc(SECTEURS[x.secteur] || '')}${x.ville ? '<br>' + esc(x.ville) : ''}</td><td class="small">${esc(SOURCES[x.source] || '')}</td><td>${badge(...ETAPE[x.etape || 'nouveau'])}</td>
          <td class="small">${d ? `<b class="${retard ? 'warn' : ''}" style="background:none;padding:0">${fmtD(d)}</b> ` : ''}${esc(x.prochaineAction?.texte || (K.PROSPECT_OUVERT(x) ? '— à fixer' : ''))}</td><td class="small">${der ? `${esc(CANAL[der.canal])} · ${fmtD(der.date || der.creeLe)}` : '—'}</td></tr>`;
      }).join('') || '<tr><td colspan="6" class="muted">Aucun prospect.</td></tr>'}</tbody></table>
      <p class="small muted">Données personnelles de prospection : ne garder que le nécessaire ; « Supprimer » efface le prospect et ses échanges (droit d’effacement, loi 09-08).</p>`;
  };

  V.prospect = r => {
    const x = prospect(r.id);
    if (!x) return `<p class="muted">Prospect introuvable. <a href="#/prospects">Retour</a></p>`;
    const conv = x.clientId && client(x.clientId);
    return `<p class="small" style="margin:0 0 6px"><a href="#/prospects">← Prospects</a></p>
      <div class="row"><h1 class="grow">${esc(x.societe || x.nom)}</h1>${badge(...ETAPE[x.etape || 'nouveau'])}</div>
      <div class="cc-deux"><div>
        <div class="card"><dl class="kv">
          <dt>Contact</dt><dd>${esc(x.nom || '—')}${x.fonction ? ' · ' + esc(x.fonction) : ''}</dd>
          <dt>Téléphone</dt><dd>${esc(x.telephone || '—')}${K.lienWhatsApp(x.telephone) ? ` · <a target="_blank" rel="noopener" href="${esc(K.lienWhatsApp(x.telephone))}">WhatsApp</a>` : ''}</dd>
          <dt>E-mail</dt><dd>${x.email ? `<a href="mailto:${esc(x.email)}">${esc(x.email)}</a>` : '—'}</dd>
          <dt>Secteur</dt><dd>${esc(SECTEURS[x.secteur] || '—')}${x.ville ? ' · ' + esc(x.ville) : ''}</dd>
          <dt>Taille</dt><dd>${esc(x.taille || '—')}</dd>
          <dt>Source</dt><dd>${esc(SOURCES[x.source] || '—')}${x.parrain ? ' · parrain : ' + esc(x.parrain) : ''}</dd>
          <dt>Prochaine action</dt><dd>${x.prochaineAction?.date ? fmtD(x.prochaineAction.date) + ' · ' : ''}${esc(x.prochaineAction?.texte || '—')}</dd>
          ${x.etape === 'perdu' ? `<dt>Motif de perte</dt><dd>${esc(x.motifPerte)}</dd>` : ''}
          ${x.notes ? `<dt>Notes</dt><dd style="white-space:pre-wrap">${esc(x.notes)}</dd>` : ''}
          ${conv ? `<dt>Client</dt><dd><a href="#/client/${conv.id}">${esc(conv.nom)}</a></dd>` : ''}
        </dl><div class="actions" style="margin-bottom:0"><button class="btn sm primary" data-action="prospect-modifier" data-id="${x.id}">Modifier, changer d’étape</button>
          ${!x.clientId && x.etape !== 'perdu' ? `<button class="btn sm" data-action="prospect-convertir" data-id="${x.id}">Convertir en client</button>` : ''}
          <button class="btn sm ghost danger" data-action="prospect-supprimer" data-id="${x.id}">Supprimer</button></div></div>
      </div><div>
        <h2 style="margin-top:0">Échanges</h2>
        ${blocMessagePret('prospect', x.id)}
        <div class="card">${listeEchanges(echangesDe('prospectId', x.id))}
          <div class="actions" style="margin-bottom:0"><button class="btn sm primary" data-action="message" data-cible="prospect" data-id="${x.id}">Envoyer un message</button><button class="btn sm" data-action="echange" data-cible="prospect" data-id="${x.id}">Noter un échange</button></div></div>
      </div></div>`;
  };

  V.support = r => {
    const f = r.q.get('f') || 'ouvertes', t = today();
    const l = f === 'ouvertes' ? K.supportOuvert(tickets, t).map(x => x.t) : tickets;
    return `<h1>Support</h1>
      <div class="cc-outils"><a class="btn sm ${f === 'ouvertes' ? 'primary' : 'ghost'}" href="#/support">Ouvertes · ${tickets.filter(K.TICKET_OUVERT).length}</a><a class="btn sm ${f === 'toutes' ? 'primary' : 'ghost'}" href="#/support?f=toutes">Toutes · ${tickets.length}</a>
        <span class="grow"></span><button class="btn primary sm" data-action="ticket-nouveau">+ Demande</button></div>
      <table class="cc-table"><thead><tr><th>Réf.</th><th>Client</th><th>Nature</th><th>Sujet</th><th>Priorité</th><th>Statut</th><th>Échéance</th><th>Reçue</th></tr></thead>
      <tbody>${l.map(k => `<tr class="lien" data-href="#/ticket/${k.id}"><td><b>${esc(k.ref)}</b></td><td>${esc(client(k.entrepriseId)?.nom || '—')}</td><td class="small">${esc(NATURE[k.nature] || '')}${k.source === 'appli' ? '<br><span class="muted">depuis l’appli</span>' : ''}</td>
        <td>${esc(k.sujet)}</td><td>${badge(...PRIO_T[k.priorite || 'normale'])}</td><td>${badge(...STATUT_T[k.statut || 'ouverte'])}</td>
        <td class="small">${k.echeance ? `<span class="${k.echeance < t && K.TICKET_OUVERT(k) ? 'warn' : ''}" style="background:none;padding:0">${fmtD(k.echeance)}</span>` : '—'}</td><td class="small">${esc(depuis(k.creeLe))}</td></tr>`).join('') || '<tr><td colspan="8" class="muted">Aucune demande.</td></tr>'}</tbody></table>`;
  };

  V.ticket = r => {
    const k = ticket(r.id);
    if (!k) return `<p class="muted">Demande introuvable. <a href="#/support">Retour</a></p>`;
    const c = client(k.entrepriseId);
    return `<p class="small" style="margin:0 0 6px"><a href="#/support">← Support</a></p>
      <div class="row"><h1 class="grow">${esc(k.ref)} · ${esc(k.sujet)}</h1>${badge(...PRIO_T[k.priorite || 'normale'])} ${badge(...STATUT_T[k.statut || 'ouverte'])}</div>
      <div class="cc-deux"><div>
        <div class="card"><dl class="kv">
          <dt>Client</dt><dd>${c ? `<a href="#/client/${c.id}">${esc(c.nom)}</a>` : '—'}</dd>
          <dt>Nature</dt><dd>${esc(NATURE[k.nature] || '—')}${k.source === 'appli' ? ' · envoyée depuis l’appli' : ''}</dd>
          ${k.demandeur ? `<dt>Demandeur</dt><dd>${esc(k.demandeur.nom || '')} · ${esc(k.demandeur.email || '')} (${esc(k.demandeur.role || '')})</dd>` : ''}
          <dt>Reçue</dt><dd>${fmtD(k.creeLe)}</dd><dt>Échéance</dt><dd>${k.echeance ? fmtD(k.echeance) : '—'}</dd>
          <dt>Description</dt><dd style="white-space:pre-wrap">${esc(k.description || '—')}</dd>
          ${k.reponse ? `<dt>Réponse / solution</dt><dd style="white-space:pre-wrap">${esc(k.reponse)}</dd>` : ''}
        </dl><div class="actions" style="margin-bottom:0"><button class="btn sm primary" data-action="ticket-modifier" data-id="${k.id}">Traiter, modifier</button></div></div>
      </div><div>
        <h2 style="margin-top:0">Échanges sur cette demande</h2>
        <div class="card">${listeEchanges(echanges.filter(e => e.ticketId === k.id))}
          <div class="actions" style="margin-bottom:0"><button class="btn sm" data-action="echange" data-cible="ticket" data-id="${k.id}">Noter un échange</button></div></div>
      </div></div>`;
  };

  V.communication = () => {
    const t = today();
    const enCours = a => a.actif && (!a.debut || a.debut.slice(0, 10) <= t) && (!a.fin || a.fin.slice(0, 10) >= t);
    return `<h1>Communication</h1>
      <h2 style="margin-top:0">Modèles de messages</h2>
      <p class="small muted" style="margin-top:0">Variables : {contact} {entreprise} {fin} {montant} {lien}. Le message est préparé ici ; vous l’envoyez vous-même depuis WhatsApp ou votre messagerie.</p>
      <table class="cc-table"><thead><tr><th>Nom</th><th>Pour</th><th>Texte</th><th></th></tr></thead><tbody>
        ${modeles.map(m => `<tr><td><b>${esc(m.nom)}</b></td><td class="small">${m.cible === 'prospect' ? 'Prospect' : 'Client'}</td><td class="small" style="white-space:pre-wrap">${esc(m.texte)}</td>
          <td style="white-space:nowrap"><button class="btn sm" data-action="modele-modifier" data-id="${m.id}">Modifier</button> <button class="btn sm ghost danger" data-action="modele-supprimer" data-id="${m.id}">Supprimer</button></td></tr>`).join('') || '<tr><td colspan="4" class="muted">Aucun modèle.</td></tr>'}
      </tbody></table>
      <div class="actions"><button class="btn sm primary" data-action="modele-modifier">+ Modèle</button></div>
      <h2>Annonces dans l’appli</h2>
      <p class="small muted" style="margin-top:0">Bandeau affiché en haut de l’appli des utilisateurs concernés (maintenance prévue, nouveauté…). Chaque utilisateur peut le masquer.</p>
      <table class="cc-table"><thead><tr><th>Titre</th><th>Pour</th><th>Période</th><th>État</th><th></th></tr></thead><tbody>
        ${annonces.map(a => `<tr><td><b>${esc(a.titre)}</b><br><span class="small">${esc(a.texte)}</span></td><td class="small">${a.entrepriseId ? esc(client(a.entrepriseId)?.nom || 'un client') : 'Tous les clients'}</td>
          <td class="small">${fmtD(a.debut)} → ${a.fin ? fmtD(a.fin) : 'sans fin'}</td><td>${enCours(a) ? badge('affichée', 'green') : a.actif ? badge('programmée', 'blue') : badge('désactivée')}</td>
          <td><button class="btn sm" data-action="annonce-modifier" data-id="${a.id}">Modifier</button></td></tr>`).join('') || '<tr><td colspan="5" class="muted">Aucune annonce.</td></tr>'}
      </tbody></table>
      <div class="actions"><button class="btn sm primary" data-action="annonce-modifier">+ Annonce</button></div>
      <h2>Journal des échanges</h2>
      <table class="cc-table"><thead><tr><th>Date</th><th>Avec</th><th>Canal</th><th>Résumé</th></tr></thead><tbody>
        ${echanges.slice(0, 100).map(e => { const avec = e.prospectId ? prospect(e.prospectId) : null, c = client(e.entrepriseId);
          return `<tr><td class="small">${fmtD(e.date || e.creeLe)}</td><td class="small">${avec ? `<a href="#/prospect/${avec.id}">${esc(avec.societe || avec.nom)}</a> (prospect)` : c ? `<a href="#/client/${c.id}">${esc(c.nom)}</a>` : '—'}</td>
            <td class="small">${esc(CANAL[e.canal] || e.canal)} · ${e.sens === 'entrant' ? 'reçu' : 'envoyé'}</td><td class="small" style="white-space:pre-wrap">${esc(e.resume)}</td></tr>`; }).join('') || '<tr><td colspan="4" class="muted">Aucun échange.</td></tr>'}
      </tbody></table>`;
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

  const ACT = {};
  const enregistrer = async (id, type, ent, data, msg) => { try { const o = await Sync.pf.objetEnregistrer(id, type, ent, data); if (msg) toast(msg); return o; } catch (e) { erreur(e); return null; } };
  const champsProspect = [
    { nom: 'societe', label: 'Société' }, { nom: 'nom', label: 'Contact' }, { nom: 'fonction', label: 'Fonction', aide: 'Directeur maintenance…' },
    { nom: 'telephone', label: 'Téléphone (WhatsApp)', type: 'tel' }, { nom: 'email', label: 'E-mail', type: 'email' }, { nom: 'ville', label: 'Ville' },
    { nom: 'secteur', label: 'Secteur', type: 'select', options: SECTEURS, vide: '—' }, { nom: 'taille', label: 'Taille', aide: 'ex. 2 sites, 15 techniciens' },
    { nom: 'source', label: 'Source', type: 'select', options: SOURCES, vide: '—' }, { nom: 'parrain', label: 'Parrain (si parrainage)' },
    { nom: 'etape', label: 'Étape', type: 'select', options: Object.fromEntries(K.ETAPES_PROSPECT.map(e => [e, ETAPE[e][0]])), requis: true },
    { nom: 'motifPerte', label: 'Motif de perte (si perdu)' },
    { nom: 'actionDate', label: 'Prochaine action : date', type: 'date' }, { nom: 'actionTexte', label: 'Prochaine action', aide: 'ex. Rappeler après la démo' },
    { nom: 'notes', label: 'Notes', type: 'textarea', plein: true }];
  async function editerProspect(x) {
    const v = await formulaire({ titre: x ? `Prospect — ${x.societe || x.nom}` : 'Nouveau prospect', ok: 'Enregistrer', champs: champsProspect,
      valeurs: x ? { ...x, actionDate: x.prochaineAction?.date, actionTexte: x.prochaineAction?.texte } : { etape: 'nouveau', actionDate: today() } });
    if (!v) return null;
    const { actionDate, actionTexte, ...d } = v;
    d.prochaineAction = actionDate || actionTexte ? { date: actionDate, texte: actionTexte } : null;
    const keep = x ? { clientId: x.clientId } : {};
    return enregistrer(x?.id || null, 'prospect', null, { ...keep, ...d }, 'Prospect enregistré');
  }
  ACT['prospect-nouveau'] = async () => { const o = await editerProspect(null); if (o) { await afficher(true); location.hash = '#/prospect/' + o.id; } };
  ACT['prospect-modifier'] = async el => { if (await editerProspect(prospect(el.dataset.id))) await afficher(true); };
  ACT['prospect-supprimer'] = async el => {
    const x = prospect(el.dataset.id);
    if (!(await confirmer('Supprimer le prospect', `${x.societe || x.nom} et ses échanges seront effacés définitivement.`, 'Supprimer'))) return;
    try { await Sync.pf.objetSupprimer(x.id); toast('Prospect supprimé'); } catch (e) { erreur(e); }
    await afficher(true); location.hash = '#/prospects';
  };
  ACT['prospect-convertir'] = async el => {
    const x = prospect(el.dataset.id);
    const code = String(x.societe || x.nom || 'CLIENT').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().replace(/[^A-Z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 12);
    const v = await formulaire({ titre: `Convertir en client — ${x.societe || x.nom}`, ok: 'Créer le client', valeurs: { nom: x.societe || x.nom, code, pack: 'essentiel', statut: 'essai', siteCode: 'S1', siteNom: x.ville ? `Site de ${x.ville}` : '' },
      info: 'Crée l’entreprise (et son premier site), recopie le contact dans la fiche client et passe le prospect en « Gagné ». Ensuite : mise en service.',
      champs: [{ nom: 'nom', label: 'Nom de l’entreprise', requis: true }, { nom: 'code', label: 'Code (majuscules)', requis: true },
        { nom: 'pack', label: 'Pack', type: 'select', options: PACKS, requis: true }, { nom: 'statut', label: 'Statut', type: 'select', options: { essai: 'Essai', actif: 'Actif' }, requis: true },
        { nom: 'siteNom', label: 'Premier site', requis: true }, { nom: 'siteCode', label: 'Code du site', requis: true }] });
    if (!v) return;
    try {
      const r = await Sync.pf.creer(v);
      await Sync.pf.clientMaj(r.entrepriseId, { raisonSociale: x.societe || null, ville: x.ville || null, secteur: x.secteur || null, notes: x.notes || null,
        contacts: x.nom ? [{ nom: x.nom, fonction: x.fonction || null, telephone: x.telephone || null, email: x.email || null }] : [] });
      await Sync.pf.objetEnregistrer(x.id, 'prospect', null, { ...x, etape: 'gagne', clientId: r.entrepriseId, prochaineAction: null });
      toast('Client créé'); await afficher(true); location.hash = '#/client/' + r.entrepriseId;
    } catch (e) { erreur(e); await afficher(true); }
  };

  ACT.echange = async el => {
    const cible = el.dataset.cible, id = el.dataset.id;
    const v = await formulaire({ titre: 'Noter un échange', valeurs: { canal: 'telephone', sens: 'sortant', date: today() }, champs: [
      { nom: 'canal', label: 'Canal', type: 'select', options: CANAL, requis: true }, { nom: 'sens', label: 'Sens', type: 'select', options: { sortant: 'Envoyé / appelé', entrant: 'Reçu' }, requis: true },
      { nom: 'date', label: 'Date', type: 'date', requis: true }, { nom: 'resume', label: 'Résumé', type: 'textarea', requis: true, plein: true }] });
    if (!v) return;
    const k = cible === 'ticket' ? ticket(id) : null;
    await enregistrer(null, 'echange', cible === 'client' ? id : k ? k.entrepriseId : null,
      { ...v, ...(cible === 'prospect' ? { prospectId: id } : {}), ...(k ? { ticketId: id } : {}) }, 'Échange noté');
    await afficher(true);
  };

  ACT.message = async el => {
    const cible = el.dataset.cible, id = el.dataset.id;
    const c = cible === 'client' ? client(id) : null, x = cible === 'prospect' ? prospect(id) : null;
    const contacts = c ? (c.fiche?.contacts || []) : [{ nom: x.nom, telephone: x.telephone, email: x.email }];
    if (!contacts.some(p => p.telephone || p.email)) { toast('Aucun téléphone ni e-mail : complétez la fiche'); return; }
    const choix = Object.fromEntries(contacts.flatMap((p, i) => [...(K.numeroWhatsApp(p.telephone) ? [[`w${i}`, `${p.nom || 'Contact'} · WhatsApp ${p.telephone}`]] : []), ...(p.email ? [[`e${i}`, `${p.nom || 'Contact'} · e-mail ${p.email}`]] : [])]));
    const mods = modeles.filter(m => (m.cible || 'client') === (c ? 'client' : 'prospect'));
    const v1 = await formulaire({ titre: 'Envoyer un message', ok: 'Préparer', champs: [
      { nom: 'dest', label: 'Destinataire', type: 'select', options: choix, requis: true },
      { nom: 'modele', label: 'Modèle', type: 'select', options: Object.fromEntries(mods.map(m => [m.id, m.nom])), vide: '— Message libre —' }] });
    if (!v1) return;
    const p = contacts[Number(v1.dest.slice(1))], canal = v1.dest[0] === 'w' ? 'whatsapp' : 'email';
    const a = c?.abonnement || {};
    const vars = { contact: p.nom, entreprise: c ? (c.fiche?.raisonSociale || c.nom) : (x.societe || ''), fin: a.fin ? fmtD(a.fin) : null,
      montant: a.prix != null ? `${mad(a.prix)} HT / ${a.periodicite === 'annuel' ? 'an' : 'mois'}` : null, lien: 'https://app.perfora.ma' };
    const base = K.remplir(modeles.find(m => m.id === v1.modele)?.texte || '', vars);
    const v2 = await formulaire({ titre: 'Relire le message', ok: 'Message prêt', valeurs: { texte: base.texte },
      info: base.manquantes.length ? `À compléter : ${base.manquantes.map(m => '{' + esc(m) + '}').join(', ')}` : '',
      champs: [{ nom: 'texte', label: 'Message', type: 'textarea', requis: true, plein: true }] });
    if (!v2) return;
    const lien = canal === 'whatsapp' ? K.lienWhatsApp(p.telephone, v2.texte) : `mailto:${p.email}?subject=${encodeURIComponent('Perfora')}&body=${encodeURIComponent(v2.texte)}`;
    messagePret = { cible, id, canal, lien, texte: v2.texte, destinataire: `${p.nom || ''} (${canal === 'whatsapp' ? p.telephone : p.email})`, entrepriseId: c?.id || null };
    afficher();
  };
  ACT['message-annuler'] = () => { messagePret = null; afficher(); };

  ACT['ticket-nouveau'] = async el => {
    const v = await formulaire({ titre: 'Nouvelle demande de support', ok: 'Créer', valeurs: { entrepriseId: el.dataset.id || '', nature: 'question', priorite: 'normale' }, champs: [
      { nom: 'entrepriseId', label: 'Client', type: 'select', options: Object.fromEntries(clients.map(c => [c.id, c.nom])), requis: true },
      { nom: 'nature', label: 'Nature', type: 'select', options: NATURE, requis: true }, { nom: 'priorite', label: 'Priorité', type: 'select', options: Object.fromEntries(Object.entries(PRIO_T).map(([k, v]) => [k, v[0]])), requis: true },
      { nom: 'sujet', label: 'Sujet', requis: true, plein: true }, { nom: 'description', label: 'Description', type: 'textarea', plein: true }, { nom: 'echeance', label: 'Échéance', type: 'date' }] });
    if (!v) return;
    const { entrepriseId, ...d } = v;
    const o = await enregistrer(null, 'ticket', entrepriseId, { ...d, statut: 'ouverte', source: 'console' }, 'Demande créée');
    await afficher(true); if (o) location.hash = '#/ticket/' + o.id;
  };
  ACT['ticket-modifier'] = async el => {
    const k = ticket(el.dataset.id);
    const v = await formulaire({ titre: `${k.ref} — ${k.sujet}`, valeurs: k, champs: [
      { nom: 'statut', label: 'Statut', type: 'select', options: Object.fromEntries(Object.entries(STATUT_T).map(([a, b]) => [a, b[0]])), requis: true },
      { nom: 'priorite', label: 'Priorité', type: 'select', options: Object.fromEntries(Object.entries(PRIO_T).map(([a, b]) => [a, b[0]])), requis: true },
      { nom: 'nature', label: 'Nature', type: 'select', options: NATURE, requis: true }, { nom: 'echeance', label: 'Échéance', type: 'date' },
      { nom: 'sujet', label: 'Sujet', requis: true, plein: true }, { nom: 'description', label: 'Description', type: 'textarea', plein: true },
      { nom: 'reponse', label: 'Réponse / solution', type: 'textarea', plein: true }] });
    if (!v) return;
    const { id, type, entrepriseId, creeLe, majLe, ...garde } = k;
    await enregistrer(k.id, 'ticket', k.entrepriseId, { ...garde, ...v, ...(v.statut === 'resolue' && k.statut !== 'resolue' ? { resolueLe: new Date().toISOString() } : {}) }, 'Demande mise à jour');
    await afficher(true);
  };

  ACT['modele-modifier'] = async el => {
    const m = el.dataset.id ? modeles.find(y => y.id === el.dataset.id) : null;
    const v = await formulaire({ titre: m ? `Modèle — ${m.nom}` : 'Nouveau modèle', valeurs: m || { cible: 'client' }, info: 'Variables : {contact} {entreprise} {fin} {montant} {lien}',
      champs: [{ nom: 'nom', label: 'Nom', requis: true }, { nom: 'cible', label: 'Pour', type: 'select', options: { client: 'Client', prospect: 'Prospect' }, requis: true },
        { nom: 'texte', label: 'Texte', type: 'textarea', requis: true, plein: true }] });
    if (!v) return;
    await enregistrer(m?.id || null, 'modele', null, v, 'Modèle enregistré'); await afficher(true);
  };
  ACT['modele-supprimer'] = async el => {
    const m = modeles.find(y => y.id === el.dataset.id);
    if (!(await confirmer('Supprimer le modèle', `« ${m.nom} » sera supprimé.`, 'Supprimer'))) return;
    try { await Sync.pf.objetSupprimer(m.id); toast('Modèle supprimé'); } catch (e) { erreur(e); }
    await afficher(true);
  };
  ACT['annonce-modifier'] = async el => {
    const a = el.dataset.id ? annonces.find(y => y.id === el.dataset.id) : null;
    const v = await formulaire({ titre: a ? 'Annonce' : 'Nouvelle annonce', ok: 'Enregistrer',
      valeurs: a ? { ...a, entrepriseId: a.entrepriseId || '', debut: a.debut?.slice(0, 10), fin: a.fin?.slice(0, 10) } : { niveau: 'info', actif: true, debut: today(), entrepriseId: '' },
      champs: [{ nom: 'titre', label: 'Titre', requis: true, plein: true }, { nom: 'texte', label: 'Texte (500 caractères max.)', type: 'textarea', requis: true, plein: true },
        { nom: 'niveau', label: 'Niveau', type: 'select', options: { info: 'Information', attention: 'Attention' }, requis: true },
        { nom: 'entrepriseId', label: 'Pour', type: 'select', options: Object.fromEntries(clients.map(c => [c.id, c.nom])), vide: 'Tous les clients' },
        { nom: 'debut', label: 'Début', type: 'date' }, { nom: 'fin', label: 'Fin (incluse)', type: 'date' },
        { nom: 'actif', label: 'Active', type: 'checkbox', plein: true }] });
    if (!v) return;
    try {
      await Sync.pf.annonceEnregistrer(a?.id || null, { ...v, debut: v.debut ? v.debut + 'T00:00:00' : null, fin: v.fin ? v.fin + 'T23:59:59' : null });
      toast('Annonce enregistrée');
    } catch (e) { erreur(e); }
    await afficher(true);
  };

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
    const onglet = { client: 'clients', prospect: 'prospects', ticket: 'support' }[r.nom] || r.nom;
    document.querySelectorAll('.cc-onglets a').forEach(a => a.classList.toggle('on', a.dataset.onglet === onglet));
    vue.querySelectorAll('[data-abo]').forEach(b => b.onclick = () => modifierAbonnement(b.dataset.abo));
    vue.querySelectorAll('[data-prolonger]').forEach(b => b.onclick = () => prolonger(b.dataset.prolonger, b.dataset.duree));
    vue.querySelectorAll('[data-tarif]').forEach(b => b.onclick = () => modifierTarif(b.dataset.tarif));
    vue.querySelectorAll('tr.lien').forEach(tr => tr.onclick = () => { location.hash = tr.dataset.href || '#/client/' + tr.dataset.id; });
    vue.querySelectorAll('[data-action]').forEach(b => b.onclick = () => ACT[b.dataset.action]?.(b));
    const env = $('#cc-envoyer');
    if (env) env.onclick = () => {
      const m = messagePret; messagePret = null;
      Sync.pf.objetEnregistrer(null, 'echange', m.entrepriseId, { canal: m.canal, sens: 'sortant', date: today(), resume: m.texte, ...(m.cible === 'prospect' ? { prospectId: m.id } : {}) })
        .then(() => afficher(true)).catch(erreur);
    };
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
