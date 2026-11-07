/* Synchronisation cloud (prototype lot 1) — Supabase via son API web, sans bibliothèque.
   Offline-first : l'appareil reste la source immédiate. Les modifications attendent dans la
   file « sortie » et partent dès qu'il y a du réseau ; les changements des autres appareils
   sont récupérés par numéro de séquence serveur (jamais par l'horloge du téléphone). */
const Sync = (() => {
  const { data } = Store;
  const LOT_ENVOI = 100, LOT_RECEPTION = 100, RECOUVREMENT = 200;
  let enCours = false, minuteur = null;
  let surEtat = () => {}, surReception = () => {}, surRefus = () => {};

  const DELAI_MAX = 20000; // réseau faible : on abandonne et on réessaiera plus tard
  // Envoi par lots limités en nombre ET en taille (photos) : sur un réseau lent, un lot trop lourd dépasserait le délai
  // à chaque essai et bloquerait toute la file. Délai accordé : 20 s + 1 s par 25 Ko (≈ 200 kbit/s minimum).
  const LOT_OCTETS = 350000, OCTETS_PAR_SECONDE = 25000;
  const RESEAU = /injoignable|trop lent|réseau/i;
  /** Projet Supabase du site : adresse et clé publique, publiques par conception (accès protégé par RLS). */
  const PROJET = { url: 'https://oihaqzkqhvyjybijsonc.supabase.co', cle: 'sb_publishable_Qpm_99-lOQOOJ5R__oyIcA_4nd7t3un' };
  const cfg = () => data.meta.get('cloud');
  async function requete(url, opts) {
    const taille = typeof opts?.body === 'string' ? opts.body.length : opts?.body instanceof Blob ? opts.body.size : 0;
    const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), DELAI_MAX + Math.ceil(taille / OCTETS_PAR_SECONDE) * 1000);
    try { return await fetch(url, { ...opts, signal: ctl.signal }); }
    catch (e) { throw new Error(e.name === 'AbortError' ? 'Réseau trop lent (délai dépassé)' : 'Serveur injoignable (réseau)'); }
    finally { clearTimeout(t); }
  }
  const majCfg = patch => Store.persistMeta({ ...(cfg() || { id: 'cloud' }), ...patch });

  // ---------- connexion (Supabase Auth) ----------
  async function auth(url, cle, grant, corps) {
    const r = await requete(`${url}/auth/v1/token?grant_type=${grant}`, {
      method: 'POST', headers: { apikey: cle, 'Content-Type': 'application/json' }, body: JSON.stringify(corps),
    });
    const j = await r.json().catch(() => null);
    // Portail Wi-Fi, proxy ou passerelle en panne : réponse qui ne vient pas de Supabase → traité comme une panne réseau.
    if (!j || r.status >= 500 || (r.ok && !j.access_token)) throw new Error('Serveur injoignable (réseau : réponse inattendue)');
    if (!r.ok) {
      const m = j.error_description || j.msg || j.message || '';
      const fr = /invalid login/i.test(m) ? 'E-mail ou mot de passe incorrect' : /not confirmed/i.test(m) ? 'E-mail pas encore confirmé (voir Supabase → Authentication)'
        : /api key/i.test(m) ? 'Clé publique incorrecte' : m || `Connexion refusée (${r.status})`;
      const err = new Error(fr);
      err.definitif = r.status === 400 || r.status === 401 || r.status === 403;   // Supabase refuse la session (expirée, révoquée)
      throw err;
    }
    return j;
  }
  const session = j => ({ access: j.access_token, refresh: j.refresh_token, expire: Date.now() + (j.expires_in || 3600) * 1000, userId: j.user?.id || null, email: j.user?.email || null });

  /** Connexion ; le mot de passe n'est jamais conservé. Retourne true si c'est la première fois sur cet appareil. */
  async function connecter({ url, cle, email, motDePasse }) {
    url = url.trim().replace(/\/+$/, '');
    const premiere = !cfg()?.url;
    const j = await auth(url, cle.trim(), 'password', { email: email.trim(), password: motDePasse });
    await majCfg({ url, cle: cle.trim(), ...session(j), curseur: cfg()?.url === url ? (cfg().curseur || 0) : 0, erreur: null });
    notifier();
    return premiere;
  }
  // ---------- liens reçus par e-mail (invitation, mot de passe oublié) ----------
  /** Lit un retour de lien Supabase dans l'adresse (#access_token=…&type=invite). null sinon. */
  function lireLienEmail(hash) {
    const h = (hash || '').replace(/^#\/?/, '');
    if (!/(^|&)(access_token|error)=/.test(h)) return null;
    const p = new URLSearchParams(h);
    if (p.get('error')) {
      const code = p.get('error_code') || '';
      return { erreur: /expired/.test(code) ? 'Lien expiré : demandez un nouvel e-mail au responsable.' : (p.get('error_description') || 'Lien invalide').replace(/\+/g, ' ') };
    }
    return { type: p.get('type'), access_token: p.get('access_token'), refresh_token: p.get('refresh_token'), expires_in: Number(p.get('expires_in')) || 3600 };
  }
  /** Ouvre la session à partir du lien (sans mot de passe) et récupère l'identité du compte. */
  async function sessionDepuisLien(l) {
    const c = cfg()?.url ? cfg() : PROJET;
    const r = await requete(`${c.url}/auth/v1/user`, { headers: { apikey: c.cle, Authorization: 'Bearer ' + l.access_token } });
    if (!r.ok) throw new Error('Lien invalide ou déjà utilisé');
    const u = await r.json();
    const premiere = !cfg()?.url;
    await majCfg({ url: c.url, cle: c.cle, ...session({ ...l, user: u }), curseur: cfg()?.curseur || 0, erreur: null });
    notifier();
    return { premiere, email: u.email };
  }
  /** Envoie par e-mail un lien pour choisir son mot de passe (première connexion ou oubli).
      Le lien ramène sur l'appli (adresseRetour), qui demande alors le nouveau mot de passe. */
  async function demanderLien(email, adresseRetour) {
    const c = cfg()?.url ? cfg() : PROJET;
    const r = await requete(`${c.url}/auth/v1/recover?redirect_to=${encodeURIComponent(adresseRetour)}`, {
      method: 'POST', headers: { apikey: c.cle, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: email.trim() }),
    });
    if (!r.ok) {
      const j = await r.json().catch(() => ({}));
      const m = j.msg || j.message || j.error_description || '';
      throw new Error(/rate limit|seconds|too many/i.test(m) ? 'Trop de demandes : réessayez dans quelques minutes' : m || `Refusé (${r.status})`);
    }
  }
  async function changerMotDePasse(mdp) {
    const c = cfg();
    const r = await requete(`${c.url}/auth/v1/user`, { method: 'PUT', headers: { apikey: c.cle, Authorization: 'Bearer ' + await jeton(), 'Content-Type': 'application/json' }, body: JSON.stringify({ password: mdp }) });
    if (!r.ok) {
      const j = await r.json().catch(() => ({}));
      const m = j.msg || j.message || j.error_description || '';
      throw new Error(/weak|at least|characters/i.test(m) ? 'Mot de passe trop faible : 10 caractères minimum, lettres et chiffres' : /same/i.test(m) ? 'Choisissez un mot de passe différent de l’ancien' : m || `Refusé (${r.status})`);
    }
  }

  async function deconnecter() { await majCfg({ access: null, refresh: null, expire: 0 }); notifier(); }
  /** Ferme toutes les sessions du compte (téléphone perdu, appareil prêté), puis celle-ci. */
  async function deconnecterPartout() {
    const c = cfg();
    const r = await requete(`${c.url}/auth/v1/logout?scope=global`, { method: 'POST', headers: { apikey: c.cle, Authorization: 'Bearer ' + await jeton() } });
    if (!r.ok && r.status !== 401 && r.status !== 403) throw new Error(`Déconnexion refusée (${r.status})`);
    await deconnecter();
  }

  async function jeton() {
    const c = cfg();
    if (!c?.refresh) throw new Error('Connexion nécessaire');
    if (c.access && c.expire - Date.now() > 60000) return c.access;
    try { await majCfg(session(await auth(c.url, c.cle, 'refresh_token', { refresh_token: c.refresh }))); }
    catch (e) {
      // Seul un refus explicite de Supabase met fin à la session ; toute autre erreur (réseau, portail Wi-Fi, serveur
      // momentanément indisponible) la conserve : les saisies attendent et repartiront seules.
      if (!e.definitif) throw RESEAU.test(e.message) ? e : new Error('Serveur injoignable (réseau) : ' + e.message);
      await majCfg({ access: null, refresh: null }); throw new Error('Session expirée : reconnectez-vous');
    }
    return cfg().access;
  }

  async function api(chemin, opts = {}) {
    const c = cfg();
    const appel = tok => requete(c.url + chemin, { ...opts, headers: { apikey: c.cle, Authorization: 'Bearer ' + tok, 'Content-Type': 'application/json' } });
    let r = await appel(await jeton());
    if (r.status === 401) { await majCfg({ expire: 0 }); r = await appel(await jeton()); }
    if (!r.ok) {
      const brut = await r.text();
      let m = ''; try { const j = JSON.parse(brut); m = j.message || j.erreur || j.msg || ''; } catch { /* texte brut */ }
      throw new Error(m || `Serveur ${r.status} : ${brut.slice(0, 160)}`);
    }
    const t = await r.text();
    return t ? JSON.parse(t) : null;
  }

  // ---------- fichiers joints (Supabase Storage, espace privé « fichiers ») ----------
  const BUCKET = 'fichiers';
  /** Dépose le contenu d'un fichier joint (une seule fois : un dépôt déjà fait est accepté comme réussi). */
  async function deposerFichier(chemin, blob, mime) {
    const c = cfg();
    const r = await requete(`${c.url}/storage/v1/object/${BUCKET}/${chemin}`, { method: 'POST', body: blob,
      headers: { apikey: c.cle, Authorization: 'Bearer ' + await jeton(), 'Content-Type': mime || blob.type || 'application/octet-stream', 'x-upsert': 'false' } });
    if (r.ok) return;
    const t = await r.text();
    if (/duplicate|already exists|409/i.test(t)) return;   // déjà déposé (réponse perdue la fois précédente)
    let m = ''; try { m = JSON.parse(t).message || ''; } catch { /* texte brut */ }
    throw new Error(`Fichier refusé : ${m || r.status}`);
  }
  /** Lit le contenu d'un fichier joint (Blob). */
  async function lireFichier(chemin) {
    const c = cfg();
    const r = await requete(`${c.url}/storage/v1/object/authenticated/${BUCKET}/${chemin}`, { headers: { apikey: c.cle, Authorization: 'Bearer ' + await jeton() } });
    if (!r.ok) throw new Error(r.status === 400 || r.status === 404 ? 'Fichier introuvable ou non autorisé' : `Fichier indisponible (${r.status})`);
    return r.blob();
  }
  /** Avant d'envoyer la fiche d'un fichier joint, son contenu doit être déposé (sinon la fiche pointerait vers rien). */
  async function deposerContenus(lot) {
    for (const s of lot) {
      if (s.type !== 'photos' || !s.patch?.chemin) continue;
      const b = await Store.blobLire(s.rid);
      if (!b || b.envoye) continue;
      await deposerFichier(s.patch.chemin, b.blob, s.patch.mime);
      await Store.blobEcrire({ ...b, envoye: true });
    }
  }

  // ---------- envoi puis réception ----------
  async function envoyer() {
    let n = 0;
    for (;;) {
      const file = Store.fileEnvoi(), lot = [];
      let octets = 0;
      for (const s of file) {
        const t = JSON.stringify(s.patch).length;
        if (lot.length && (lot.length >= LOT_ENVOI || octets + t > LOT_OCTETS)) break;
        lot.push(s); octets += t;
      }
      if (!lot.length) return n;
      await deposerContenus(lot);
      const rep = await api('/rest/v1/rpc/push_fiches', { method: 'POST', body: JSON.stringify({ lot: lot.map(s => ({ id: s.rid, type: s.type, patch: s.patch })), version: window.App?.version || null }) });
      const refus = (Array.isArray(rep?.refuses) ? rep.refuses : [])
        .map(r => ({ ...r, patch: lot.filter(s => s.rid === r.id).reduce((p, s) => ({ ...p, ...s.patch }), {}) }));
      await Store.retirerEnvoyes(lot.map(s => s.id));
      if (refus.length) await traiterRefus(refus);
      n += lot.length;
      notifier();
    }
  }

  /** Modifications refusées par le serveur (droits) : on reprend la version du serveur et on prévient. */
  async function traiterRefus(refus) {
    const ids = [...new Set(refus.filter(r => r.type !== 'journal').map(r => r.id))];
    if (ids.length) {
      const liste = ids.map(i => '"' + String(i).replace(/"/g, '') + '"').join(',');
      const rows = await api(`/rest/v1/fiches?select=id,type,data,seq&id=in.(${encodeURIComponent(liste)})`);
      if (rows?.length) await Store.appliquerDistant(rows, { remplacer: true });
    }
    for (const r of refus.filter(x => x.type !== 'journal')) window.Erreurs?.noter({ nature: 'refus', message: r.motif || 'Refusé par le serveur', detail: `${r.type} ${r.id}` });
    const le = Store.now();
    await majCfg({ refus: [...refus.map(({ patch, ...r }) => ({ ...r, le })), ...(cfg().refus || [])].slice(0, 20) });
    surRefus(refus.filter(r => r.type !== 'journal'));
  }

  // ---------- profil et équipe (rôles contrôlés par le serveur) ----------
  // Version des règles de lecture du serveur : à relever à chaque nouveau type de fiche ou lecture élargie (une relecture
  // complète, une fois). r1 : supabase/roles_r1.sql ; r3 : équipes, interventions confiées à la société (membres_r3.sql).
  const PERIMETRE = 'r3';
  async function chargerProfil() {
    const p = await api('/rest/v1/rpc/mon_profil', { method: 'POST', body: '{}' });
    // Multi-entreprise : un appareil ne mélange jamais les données de deux entreprises.
    const ent = p?.entreprise?.id || null, dev = Store.device();
    if (ent && dev.entrepriseId && dev.entrepriseId !== ent) {
      if (data.sortie.size) {
        await deconnecter();
        throw new Error('Cet appareil contient des saisies non envoyées d’une autre entreprise : reconnectez l’ancien compte pour les envoyer, ou effacez l’appareil (Réglages).');
      }
      await Store.viderMetier();
      await majCfg({ curseur: 0 });
    } else if (ent && !dev.entrepriseId && (cfg().curseur || 0) > 0 && !data.sortie.size) {
      // Premier passage en multi-entreprise d'un appareil déjà synchronisé : on repart du serveur,
      // qui ne renvoie que l'entreprise et les sites autorisés (plus de copies hors périmètre).
      await Store.viderMetier();
      await majCfg({ curseur: 0 });
    }
    if (ent && Store.device().entrepriseId !== ent) await Store.persistMeta({ ...Store.device(), entrepriseId: ent, siteActif: null });
    // Démo commerciale réinitialisée sur le serveur : on repart de zéro (données de démo uniquement).
    const ri = p?.entreprise?.reinitLe || null;
    if (p?.entreprise?.demo && ri && Store.device().reinitLe !== ri) {
      // Appareil déjà synchronisé (même s'il n'avait jamais vu de réinitialisation : entreprise devenue démo) → on repart de zéro.
      if (Store.device().reinitLe || (cfg().curseur || 0) > 0) { await Store.viderMetier(); await majCfg({ curseur: 0 }); }
      await Store.persistMeta({ ...Store.device(), reinitLe: ri });
    }
    // Lot R1 : le serveur restreint désormais certaines lectures (prestataire, journal). Une fois, on repart du serveur pour
    // ne pas garder sur l'appareil des fiches hors du périmètre — seulement s'il n'y a rien en attente d'envoi.
    if (ent && Store.device().perimetre !== PERIMETRE && !data.sortie.size) {
      if ((cfg().curseur || 0) > 0) { await Store.viderMetier(); await majCfg({ curseur: 0 }); }
      await Store.persistMeta({ ...Store.device(), perimetre: PERIMETRE });
    }
    // S2 (risque F) : code appareil unique dans l'entreprise, attribué par le serveur (références OT-K3-0007 sans doublon).
    if (ent && Store.device().codeEntreprise !== ent) {
      try {
        const d = Store.device(), appareilId = d.appareilId || Store.uid() + Store.uid();
        const code = await api('/rest/v1/rpc/appareil_code', { method: 'POST', body: JSON.stringify({ p_code: d.code, p_appareil: appareilId }) });
        if (typeof code === 'string' && code) await Store.persistMeta({ ...Store.device(), code, appareilId, codeEntreprise: ent });
      } catch { /* hors ligne ou serveur plus ancien : nouvel essai à la prochaine lecture du profil */ }
    }
    await majCfg({ profil: p, profilLe: Date.now() });
    if (p?.personneId && Store.device().personneId !== p.personneId) await Store.persistMeta({ ...Store.device(), personneId: p.personneId });
    return p;
  }
  const profil = () => (cfg()?.refresh ? cfg()?.profil : null) || null;
  const equipe = () => api('/rest/v1/profils?select=user_id,email,nom,role,actif,personne_id,admin_client&order=email.asc');
  const definirAdminClient = (cible, valeur) => api('/rest/v1/rpc/definir_admin_client', { method: 'POST', body: JSON.stringify({ cible, valeur: !!valeur }) });
  const utilisation = () => api('/rest/v1/rpc/utilisation', { method: 'POST', body: '{}' });
  /** R3 : relier un compte (juste invité) à une fiche membre existante. */
  const relierMembre = (cible, personne) => api('/rest/v1/rpc/relier_membre', { method: 'POST', body: JSON.stringify({ cible, personne }) });
  const affecterSites = (cible, liste) => api('/rest/v1/rpc/affecter_sites', { method: 'POST', body: JSON.stringify({ cible, liste }) });
  /** Invitation via la fonction serveur « inviter » (seule détentrice de la clé secrète). */
  async function inviter({ email, role, nom, sites, redirectTo, entrepriseId }) {
    const rep = await api('/functions/v1/inviter', { method: 'POST', body: JSON.stringify({ email, role, nom, sites, redirectTo, entrepriseId }) });
    if (rep?.erreur) throw new Error(rep.erreur);
    return rep;
  }
  // ---------- console plateforme (administrateur plateforme) ----------
  const rpc = (nom, corps = {}) => api('/rest/v1/rpc/' + nom, { method: 'POST', body: JSON.stringify(corps) });
  const pf = {
    entreprises: () => rpc('pf_entreprises'),
    creer: v => rpc('pf_creer_entreprise', { p_code: v.code, p_nom: v.nom, p_pack: v.pack, p_statut: v.statut, p_site_code: v.siteCode, p_site_nom: v.siteNom, p_demo: !!v.demo }),
    abonnement: (ent, v) => rpc('pf_modifier_abonnement', { p_entreprise: ent, p_pack: v.pack, p_statut: v.statut, p_fin: v.fin || null,
      p_max_sites: v.maxSites ?? null, p_max_utilisateurs_site: v.maxUtilisateursSite ?? null, p_max_utilisateurs_total: v.maxUtilisateursTotal ?? null }),
    ajouterSite: (ent, code, nom) => rpc('pf_ajouter_site', { p_entreprise: ent, p_code: code, p_nom: nom }),
    reinitialiserDemo: ent => rpc('pf_reinitialiser_demo', { p_entreprise: ent }),
    anormales: () => rpc('pf_fiches_anormales'),
    // mise en service d'un client (supabase/mise_en_service.sql)
    referentiel: ent => rpc('pf_referentiel', { p_entreprise: ent }),
    importer: (ent, lot, fichier, fiches, essai) => rpc('pf_importer', { p_entreprise: ent, p_lot: lot, p_fichier: fichier, p_fiches: fiches, p_essai: !!essai }),
    annulerLot: (ent, lot) => rpc('pf_annuler_lot', { p_entreprise: ent, p_lot: lot }),
    mesLire: ent => rpc('pf_mes_lire', { p_entreprise: ent }),
    mesEtape: (ent, cle, fait) => rpc('pf_mes_etape', { p_entreprise: ent, p_cle: cle, p_fait: !!fait }),
    // centre de contrôle (supabase/centre_controle.sql)
    clients: () => rpc('pf_clients'),
    clientMaj: (ent, data) => rpc('pf_client_maj', { p_entreprise: ent, p_data: data }),
    conditions: (ent, v) => rpc('pf_abonnement_conditions', { p_entreprise: ent, p_prix: v.prix ?? null, p_periodicite: v.periodicite || 'mensuel', p_remise: v.remisePct ?? 0, p_debut: v.debut || null, p_conditions: v.conditions || null }),
    tarifs: () => rpc('pf_tarifs_lire'),
    objets: type => rpc('pf_objets_lire', { p_type: type }),
    objetEnregistrer: (id, type, ent, data) => rpc('pf_objet_enregistrer', { p_id: id, p_type: type, p_entreprise: ent || null, p_data: data }),
    objetSupprimer: id => rpc('pf_objet_supprimer', { p_id: id }),
    annonces: () => rpc('pf_annonces_lire'),
    annonceEnregistrer: (id, v) => rpc('pf_annonce_enregistrer', { p_id: id, p_titre: v.titre, p_texte: v.texte, p_niveau: v.niveau, p_entreprise: v.entrepriseId || null,
      p_debut: v.debut || null, p_fin: v.fin || null, p_actif: v.actif !== false }),
    tarifMaj: (pack, v) => rpc('pf_tarif_maj', { p_pack: pack, p_prix_mensuel: v.prixMensuel ?? null, p_prix_annuel: v.prixAnnuel ?? null, p_note: v.note || null }),
    // sécurité et supervision (supabase/securite.sql)
    mfaActiver: () => rpc('pf_mfa_activer'),
    journal: (limite = 200, avant = null, table = null) => rpc('pf_journal_admin_lire', { p_limite: limite, p_avant: avant, p_table: table }),
    erreurs: (jours = 7) => rpc('pf_erreurs_lire', { p_jours: jours }),
    stockage: () => rpc('pf_stockage'),
  };
  // ---------- double authentification (application d'authentification, TOTP) — administrateur plateforme ----------
  const mfa = {
    facteurs: async () => ((await api('/auth/v1/user'))?.factors || []).filter(f => f.factor_type === 'totp'),
    /** Nouvelle inscription : les inscriptions jamais confirmées sont d'abord retirées. Rend { id, totp: { uri, secret } }. */
    async inscrire() {
      for (const f of await mfa.facteurs()) if (f.status !== 'verified') await api(`/auth/v1/factors/${f.id}`, { method: 'DELETE' });
      return api('/auth/v1/factors', { method: 'POST', body: JSON.stringify({ factor_type: 'totp', issuer: 'Perfora', friendly_name: 'Perfora ' + new Date().toISOString().slice(0, 16) }) });
    },
    /** Vérifie un code à 6 chiffres : la session passe au niveau « aal2 » (mot de passe + code). */
    async verifier(factorId, code) {
      const ch = await api(`/auth/v1/factors/${factorId}/challenge`, { method: 'POST', body: '{}' });
      let j;
      try { j = await api(`/auth/v1/factors/${factorId}/verify`, { method: 'POST', body: JSON.stringify({ challenge_id: ch.id, code: String(code).replace(/\s/g, '') }) }); }
      catch (e) { throw new Error(/invalid|code/i.test(e.message) ? 'Code incorrect ou expiré : réessayez avec le code affiché maintenant' : e.message); }
      if (!j?.access_token) throw new Error('Vérification refusée');
      await majCfg(session(j));
      notifier();
    },
  };
  const signalerErreurs = liste => rpc('erreurs_signaler', { p_erreurs: liste });
  async function definirProfil(cible, role, nom, actif) {
    await api('/rest/v1/rpc/definir_profil', { method: 'POST', body: JSON.stringify({ cible, nouveau_role: role, nouveau_nom: nom, est_actif: actif }) });
  }

  async function recevoir() {
    const curseur = cfg().curseur || 0;
    // Léger recouvrement : une transaction plus ancienne peut être validée après une plus récente.
    let apres = Math.max(0, curseur - RECOUVREMENT), max = curseur, nouveaux = 0;
    for (;;) {
      const rows = await api(`/rest/v1/fiches?select=id,type,data,seq&seq=gt.${apres}&order=seq.asc&limit=${LOT_RECEPTION}`);
      if (!rows || !rows.length) break;
      await Store.appliquerDistant(rows);
      nouveaux += rows.filter(r => r.seq > curseur).length;
      apres = rows[rows.length - 1].seq;
      max = Math.max(max, apres);
      if (rows.length < LOT_RECEPTION) break;
    }
    await majCfg({ curseur: max });
    return nouveaux;
  }

  async function synchroniser() {
    const c = cfg();
    if (enCours || !c?.url || !c.refresh) { notifier(); return; }
    if (!navigator.onLine) { notifier(); return; }
    enCours = true; notifier();
    try {
      if (!c.profil || Date.now() - (c.profilLe || 0) > 10 * 60000) await chargerProfil(); // rôle à jour
      await envoyer();               // d'abord nos patchs (le serveur fusionne)…
      const recus = await recevoir(); // …puis tout ce qui a changé ailleurs
      await majCfg({ dernier: Store.now(), erreur: null });
      if (recus) surReception(recus);
      window.Erreurs?.envoyer();
    } catch (e) {
      await majCfg({ erreur: e.message || String(e) });
      // S1 : version de l'appli refusée par le serveur → l'appli se met à jour (les saisies restent en attente).
      if (/version de l.appli trop ancienne/i.test(e.message || '')) window.dispatchEvent(new CustomEvent('perfora-version-requise', { detail: e.message }));
      else if (!RESEAU.test(e.message || '')) window.Erreurs?.noter({ nature: 'synchro', message: e.message || String(e), detail: e.stack || '' });
    } finally {
      enCours = false; notifier();
    }
  }

  function planifier(delai = 1500) { clearTimeout(minuteur); minuteur = setTimeout(synchroniser, delai); }

  function demarrer({ etat, reception, refus } = {}) {
    if (etat) surEtat = etat;
    if (reception) surReception = reception;
    if (refus) surRefus = refus;
    Store.surEcriture(() => { notifier(); planifier(); });
    addEventListener('online', () => planifier(300));
    addEventListener('offline', notifier);
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') planifier(300); });
    setInterval(() => { if (document.visibilityState === 'visible') synchroniser(); }, 60000);
    planifier(500);
    notifier();
  }

  function etatCourant() {
    const c = cfg();
    return { configure: !!c?.url, connecte: !!c?.refresh, attente: data.sortie.size, enCours, erreur: c?.erreur || null,
      dernier: c?.dernier || null, email: c?.email || null, url: c?.url || null, enLigne: navigator.onLine,
      profil: profil(), refus: c?.refus || [] };
  }
  function notifier() { try { surEtat(etatCourant()); } catch { /* affichage */ } }

  // Annonces de la plateforme et demande au support (tout compte connecté).
  const mesAnnonces = () => rpc('mes_annonces');
  const supportCreer = (nature, sujet, message) => rpc('support_creer', { p_nature: nature, p_sujet: sujet, p_message: message });
  return { PROJET, pf, mfa, signalerErreurs, definirAdminClient, deconnecterPartout, mesAnnonces, supportCreer, lireFichier, profil, chargerProfil, equipe, definirProfil, utilisation, affecterSites, relierMembre, inviter, connecter, deconnecter, synchroniser, planifier, demarrer, etatCourant, lireLienEmail, sessionDepuisLien, changerMotDePasse, demanderLien };
})();
