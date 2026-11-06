-- GMAO terrain — Volet A, étape A4 : console plateforme (rejouable). À exécuter APRÈS quotas.sql.
-- Toutes les fonctions pf_* sont réservées à l'administrateur plateforme (table admins_plateforme)
-- et contournent volontairement le périmètre « mon entreprise » pour gérer les clients.
-- Démo commerciale : seule une entreprise marquée demo = true peut être réinitialisée
-- (ses fiches sont effacées puis rechargées ; les appareils se resynchronisent d'eux-mêmes).

alter table public.entreprises add column if not exists demo boolean not null default false;
alter table public.entreprises add column if not exists reinit_le timestamptz;

create or replace function public.exiger_admin()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_admin_plateforme() then raise exception 'Réservé à l''administrateur plateforme' using errcode = '42501'; end if;
end $$;

-- ---------- contrôle d'invitation commun (responsable ou plateforme) ----------
create or replace function public.controle_invitation(ent uuid, p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim jsonb; mx integer; existant uuid; p profils; s record; v_email text := lower(trim(p_email));
begin
  lim := public.droits_entreprise(ent);
  if lim is null then raise exception 'Entreprise sans abonnement'; end if;
  if not coalesce((lim->>'ecriture')::boolean, false) then raise exception 'Abonnement suspendu ou expiré'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Adresse e-mail invalide'; end if;
  if p_role not in ('responsable','technicien','prestataire','magasinier','exploitation','pilote') then raise exception 'Rôle inconnu'; end if;
  if coalesce(array_length(p_sites, 1), 0) = 0 then raise exception 'Choisissez au moins un site'; end if;
  if exists (select 1 from unnest(p_sites) x where x not in (select id from sites where entreprise_id = ent and actif)) then
    raise exception 'Site inconnu ou inactif';
  end if;
  select u.id into existant from auth.users u where lower(u.email) = v_email limit 1;
  if existant is not null then
    select * into p from profils where user_id = existant;
    if p.entreprise_id = ent then raise exception 'Ce compte fait déjà partie de l''équipe'; end if;
    if p.entreprise_id is not null then raise exception 'Ce compte est rattaché à une autre entreprise'; end if;
  end if;
  mx := (lim->>'maxUtilisateursTotal')::int;
  if mx is not null and public.nb_actifs_entreprise(ent, null) + 1 > mx then
    raise exception 'Quota atteint : % utilisateur(s) actif(s) maximum (pack %). Désactivez un compte ou changez de pack.', mx, lim->>'packNom';
  end if;
  mx := (lim->>'maxUtilisateursSite')::int;
  if mx is not null then
    for s in select id, nom from sites where id = any (p_sites) loop
      if public.nb_actifs_site(s.id, null) + 1 > mx then raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, s.nom; end if;
    end loop;
  end if;
  return jsonb_build_object('entreprise_id', ent, 'invite_par', auth.uid(), 'user_id_existant', existant);
end $$;
revoke all on function public.controle_invitation(uuid, text, text, uuid[]) from public, anon, authenticated;

create or replace function public.preparer_invitation(p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  return public.controle_invitation(public.mon_entreprise(), p_email, p_role, p_sites);
end $$;
revoke all on function public.preparer_invitation(text, text, uuid[]) from public, anon;
grant execute on function public.preparer_invitation(text, text, uuid[]) to authenticated;

create or replace function public.pf_preparer_invitation(p_entreprise uuid, p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return public.controle_invitation(p_entreprise, p_email, p_role, p_sites);
end $$;
revoke all on function public.pf_preparer_invitation(uuid, text, text, uuid[]) from public, anon;
grant execute on function public.pf_preparer_invitation(uuid, text, text, uuid[]) to authenticated;

-- ---------- liste des clients et usage ----------
create or replace function public.pf_entreprises()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(x order by x->>'nom') from (
    select jsonb_build_object(
      'id', e.id, 'code', e.code, 'nom', e.nom, 'statut', e.statut, 'demo', e.demo, 'creeLe', e.cree_le, 'reinitLe', e.reinit_le,
      'abonnement', public.droits_entreprise(e.id),
      'derogations', jsonb_build_object('maxSites', a.max_sites, 'maxUtilisateursSite', a.max_utilisateurs_site, 'maxUtilisateursTotal', a.max_utilisateurs_total),
      'actifs', public.nb_actifs_entreprise(e.id, null),
      'sites', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'nom', s.nom, 'actif', s.actif, 'actifs', public.nb_actifs_site(s.id, null)) order by s.nom), '[]'::jsonb) from sites s where s.entreprise_id = e.id),
      'responsables', (select coalesce(jsonb_agg(p.email order by p.email), '[]'::jsonb) from profils p where p.entreprise_id = e.id and p.role = 'responsable' and p.actif),
      'fiches', (select count(*) from fiches f where f.entreprise_id = e.id),
      'photos', (select count(*) from fiches f where f.entreprise_id = e.id and f.type = 'photos'),
      'derniereActivite', (select max(recu_le) from fiches f where f.entreprise_id = e.id)) x
    from entreprises e left join abonnements a on a.entreprise_id = e.id) q), '[]'::jsonb);
end $$;
revoke all on function public.pf_entreprises() from public, anon;
grant execute on function public.pf_entreprises() to authenticated;

-- ---------- création d'un client (entreprise + abonnement + premier site) ----------
create or replace function public.pf_creer_entreprise(p_code text, p_nom text, p_pack text, p_statut text, p_site_code text, p_site_nom text, p_demo boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ent uuid; site uuid; v_code text := upper(trim(p_code));
begin
  perform public.exiger_admin();
  if v_code !~ '^[A-Z0-9-]{2,20}$' then raise exception 'Code entreprise : 2 à 20 lettres majuscules, chiffres ou tirets'; end if;
  if coalesce(trim(p_nom), '') = '' or coalesce(trim(p_site_nom), '') = '' then raise exception 'Nom de l''entreprise et du site obligatoires'; end if;
  if not exists (select 1 from packs where code = p_pack) then raise exception 'Pack inconnu'; end if;
  if exists (select 1 from entreprises e2 where e2.code = v_code) then raise exception 'Ce code entreprise existe déjà'; end if;
  insert into entreprises (code, nom, statut, demo) values (v_code, trim(p_nom), coalesce(p_statut, 'essai'), coalesce(p_demo, false)) returning id into ent;
  insert into abonnements (entreprise_id, pack, statut) values (ent, p_pack, coalesce(p_statut, 'essai'));
  insert into sites (entreprise_id, code, nom) values (ent, upper(coalesce(nullif(trim(p_site_code), ''), 'S1')), trim(p_site_nom)) returning id into site;
  return jsonb_build_object('entrepriseId', ent, 'siteId', site);
end $$;
revoke all on function public.pf_creer_entreprise(text, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.pf_creer_entreprise(text, text, text, text, text, text, boolean) to authenticated;

-- ---------- abonnement : pack, statut, échéance, dérogations ----------
create or replace function public.pf_modifier_abonnement(p_entreprise uuid, p_pack text, p_statut text, p_fin date,
  p_max_sites integer, p_max_utilisateurs_site integer, p_max_utilisateurs_total integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  if p_statut not in ('essai','actif','suspendu','resilie') then raise exception 'Statut inconnu'; end if;
  if not exists (select 1 from packs where code = p_pack) then raise exception 'Pack inconnu'; end if;
  update abonnements set pack = p_pack, statut = p_statut, fin = p_fin, max_sites = p_max_sites,
    max_utilisateurs_site = p_max_utilisateurs_site, max_utilisateurs_total = p_max_utilisateurs_total
  where entreprise_id = p_entreprise;
  if not found then raise exception 'Entreprise sans abonnement'; end if;
  update entreprises set statut = p_statut where id = p_entreprise;
end $$;
revoke all on function public.pf_modifier_abonnement(uuid, text, text, date, integer, integer, integer) from public, anon;
grant execute on function public.pf_modifier_abonnement(uuid, text, text, date, integer, integer, integer) to authenticated;

create or replace function public.pf_ajouter_site(p_entreprise uuid, p_code text, p_nom text)
returns uuid language plpgsql security definer set search_path = public as $$
declare site uuid;
begin
  perform public.exiger_admin();
  if coalesce(trim(p_nom), '') = '' then raise exception 'Nom du site obligatoire'; end if;
  insert into sites (entreprise_id, code, nom) values (p_entreprise, upper(trim(p_code)), trim(p_nom)) returning id into site;   -- quota : déclencheur
  return site;
end $$;
revoke all on function public.pf_ajouter_site(uuid, text, text) from public, anon;
grant execute on function public.pf_ajouter_site(uuid, text, text) to authenticated;

-- ---------- démo commerciale réinitialisable ----------
create or replace function public.pf_j(j integer, hm text default null)
returns text language sql stable as $$
  select to_char((now() at time zone 'Africa/Casablanca')::date + j, 'YYYY-MM-DD') || coalesce('T' || hm, '')
$$;

create or replace function public.pf_reinitialiser_demo(p_entreprise uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  e entreprises; site uuid; k text; maint text := public.pf_j(0, to_char(now() at time zone 'Africa/Casablanca', 'HH24:MI'));
  l_site text; l_at text; l_li text; l_ut text; presse text; emb text; conv text; comp text;
  resp text; ta text; tb text; mag text; a1 text; a2 text; a3 text; d1 text; d3 text; o1 text; m1 text;
begin
  perform public.exiger_admin();
  select * into e from entreprises where id = p_entreprise;
  if not found or not e.demo then raise exception 'Seule une entreprise de démonstration peut être réinitialisée'; end if;
  select id into site from sites where entreprise_id = e.id and actif order by cree_le limit 1;
  if site is null then raise exception 'La démo n''a aucun site actif'; end if;

  delete from fiches where entreprise_id = e.id;   -- démo uniquement : rien d'autre n'est jamais supprimé
  k := substr(md5(e.id::text || clock_timestamp()::text), 1, 8);
  l_site := k || '-loc0'; l_at := k || '-loc1'; l_li := k || '-loc2'; l_ut := k || '-loc3';
  presse := k || '-eq1'; emb := k || '-eq2'; conv := k || '-eq3'; comp := k || '-eq4';
  resp := k || '-p1'; ta := k || '-p2'; tb := k || '-p3'; mag := k || '-p4';
  a1 := k || '-a1'; a2 := k || '-a2'; a3 := k || '-a3'; d1 := k || '-d1'; d3 := k || '-d3'; o1 := k || '-o1'; m1 := k || '-m1';

  insert into fiches (id, type, entreprise_id, site_id, data)
  select v.id, v.type, e.id, case when v.type in ('personnes','articles') then null else site end,
         v.data || jsonb_build_object('id', v.id, 'creeLe', coalesce(v.data->>'creeLe', maint), 'creePar', coalesce(v.data->>'creePar', 'Démo'), 'modifieLe', maint, 'modifiePar', 'Démo')
                || case when v.type in ('personnes','articles') then '{}'::jsonb else jsonb_build_object('siteId', site) end
  from (values
    (l_site, 'localisations', jsonb_build_object('code', 'SITE', 'nom', 'Usine', 'parentId', null)),
    (l_at, 'localisations', jsonb_build_object('code', 'AT-PR', 'nom', 'Atelier presses', 'parentId', l_site)),
    (l_li, 'localisations', jsonb_build_object('code', 'LG-CD', 'nom', 'Ligne conditionnement', 'parentId', l_site)),
    (l_ut, 'localisations', jsonb_build_object('code', 'UT', 'nom', 'Utilités', 'parentId', l_site)),
    (presse, 'equipements', jsonb_build_object('code', 'PRESSE-01', 'designation', 'Presse hydraulique 200 t', 'localisationId', l_at, 'famille', 'presse', 'criticite', '4', 'actif', true)),
    (emb, 'equipements', jsonb_build_object('code', 'EMB-02', 'designation', 'Emballeuse ligne 2', 'localisationId', l_li, 'famille', 'emballage', 'criticite', '3', 'actif', true)),
    (conv, 'equipements', jsonb_build_object('code', 'CONV-03', 'designation', 'Convoyeur sortie ligne 2', 'localisationId', l_li, 'famille', 'convoyage', 'criticite', '2', 'actif', true)),
    (comp, 'equipements', jsonb_build_object('code', 'COMP-01', 'designation', 'Compresseur d’air 55 kW', 'localisationId', l_ut, 'famille', 'utilité', 'criticite', '4', 'actif', true)),
    (resp, 'personnes', jsonb_build_object('nom', 'Responsable maintenance', 'role', 'responsable', 'actif', true)),
    (ta, 'personnes', jsonb_build_object('nom', 'Technicien A (mécanique)', 'role', 'technicien', 'actif', true)),
    (tb, 'personnes', jsonb_build_object('nom', 'Technicien B (automatisme)', 'role', 'technicien', 'actif', true)),
    (mag, 'personnes', jsonb_build_object('nom', 'Magasinier', 'role', 'magasinier', 'actif', true)),
    (a1, 'articles', jsonb_build_object('ref', 'J-VER-80', 'designation', 'Joint de vérin Ø80', 'unite', 'u', 'stockMin', 2, 'actif', true)),
    (a2, 'articles', jsonb_build_object('ref', 'HUI-HV46', 'designation', 'Huile hydraulique HV46', 'unite', 'L', 'stockMin', 20, 'actif', true)),
    (a3, 'articles', jsonb_build_object('ref', 'FIL-AIR', 'designation', 'Filtre à air compresseur', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (k || '-m0a', 'mouvements', jsonb_build_object('articleId', a1, 'type', 'entree', 'qte', 3, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0b', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'entree', 'qte', 60, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0c', 'mouvements', jsonb_build_object('articleId', a3, 'type', 'entree', 'qte', 1, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (m1, 'mouvements', jsonb_build_object('articleId', a1, 'type', 'sortie', 'qte', -1, 'otId', o1, 'le', public.pf_j(-3, '09:00'), 'motif', null)),
    (d1, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0001', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Opérateur presse', 'service', 'Production'), 'equipementId', presse, 'besoin', 'corriger', 'constat', 'Le vérin ne tient plus la position', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(-3, '08:00'), 'precisionHeure', 'exacte', 'statut', 'traitement_organise', 'priseEnChargePar', ta, 'priseEnChargeLe', public.pf_j(-3, '08:05'), 'creeLe', public.pf_j(-3, '08:03'))),
    (k || '-d2', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0002', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Chef de ligne', 'service', 'Conditionnement'), 'equipementId', emb, 'besoin', 'verifier', 'constat', 'Bruit anormal au niveau du convoyeur d’entrée', 'etat', 'degrade', 'impact', 'aucun_constate', 'heureFait', public.pf_j(-1, '14:20'), 'precisionHeure', 'estimee', 'statut', 'a_examiner', 'creeLe', public.pf_j(-1, '14:35'))),
    (d3, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0003', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie, frottement côté moteur', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(0, '07:40'), 'precisionHeure', 'estimee', 'statut', 'traitement_organise', 'priseEnChargePar', tb, 'priseEnChargeLe', public.pf_j(0, '07:50'), 'creeLe', public.pf_j(0, '07:45'))),
    (k || '-d4', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0004', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie', 'etat', 'degrade', 'impact', 'reduit', 'precisionHeure', 'inconnue', 'statut', 'close_sans_travail', 'motifClassement', 'Recentrage par l’opérateur', 'creeLe', public.pf_j(-12, '10:00'))),
    (o1, 'ots', jsonb_build_object('ref', 'OT-DEMO-0001', 'demandeIds', jsonb_build_array(d1), 'equipementId', presse, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'cloturee',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i1', 'personneId', ta, 'role', 'intervenant', 'depuis', public.pf_j(-3, '08:10'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic', 'remplacement'), 'travaux', 'Remplacement du joint de vérin, purge du circuit.', 'resultat', 'resolu', 'cause', 'Joint de vérin usé', 'certitudeCause', 'probable', 'familleDefaut', 'hydraulique',
        'avecArret', 'oui', 'arretDebut', public.pf_j(-3, '08:00'), 'arretFin', public.pf_j(-3, '10:30'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc1', 'articleId', a1, 'qte', 1, 'mouvementId', m1, 'annulee', false)), 'reserves', '[]'::jsonb, 'attentes', '[]'::jsonb,
        'clotureLe', public.pf_j(-3, '11:20'), 'cloturePar', 'Responsable maintenance', 'creeLe', public.pf_j(-3, '08:05'))),
    (k || '-o3', 'ots', jsonb_build_object('ref', 'OT-DEMO-0003', 'demandeIds', jsonb_build_array(d3), 'equipementId', conv, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'suspendue',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i3', 'personneId', tb, 'role', 'intervenant', 'depuis', public.pf_j(0, '07:50'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic'), 'travaux', 'Rouleau tendeur grippé.', 'familleDefaut', 'mecanique', 'avecArret', 'oui', 'arretDebut', public.pf_j(0, '07:40'),
        'pieces', '[]'::jsonb, 'reserves', '[]'::jsonb,
        'attentes', jsonb_build_array(jsonb_build_object('id', k || '-at3', 'motif', 'piece', 'detail', 'Rouleau tendeur commandé', 'depuis', public.pf_j(0, '08:30'), 'fin', null, 'responsableId', mag)),
        'creeLe', public.pf_j(0, '07:50'))),
    (k || '-pg1', 'programmes', jsonb_build_object('equipementId', comp, 'libelle', 'Vidange et filtre compresseur', 'modele', 'entretien', 'periodiciteJours', 90, 'prochaineEcheance', public.pf_j(-2), 'regle', 'fixe', 'instruction', 'Consigner selon procédure site, vidanger, remplacer le filtre à air, essai à vide puis en charge.', 'actif', true)),
    (k || '-pg2', 'programmes', jsonb_build_object('equipementId', presse, 'libelle', 'Contrôle niveau et fuites hydrauliques', 'modele', 'inspection', 'periodiciteJours', 30, 'prochaineEcheance', public.pf_j(5), 'regle', 'apres_realisation', 'instruction', 'Niveau bâche, état flexibles, traces de fuite.', 'actif', true))
  ) as v(id, type, data);

  update entreprises set reinit_le = now() where id = e.id;
  return jsonb_build_object('fiches', (select count(*) from fiches where entreprise_id = e.id), 'reinitLe', now());
end $$;
revoke all on function public.pf_reinitialiser_demo(uuid) from public, anon;
grant execute on function public.pf_reinitialiser_demo(uuid) to authenticated;

-- ---------- profil : date de réinitialisation (les appareils se resynchronisent) ----------
create or replace function public.mon_profil()
returns jsonb language plpgsql security definer set search_path = public as $$
declare p profils; pid text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  select * into p from profils where user_id = auth.uid();
  if not found then raise exception 'Compte sans profil' using errcode = '42501'; end if;
  if p.entreprise_id is null then raise exception 'Compte non rattaché à une entreprise : contactez votre responsable' using errcode = '42501'; end if;
  if p.personne_id is null or not exists (select 1 from fiches where id = p.personne_id) then
    pid := 'p' || replace(p.user_id::text, '-', '');
    insert into fiches (id, type, data, auteur, entreprise_id) values (pid, 'personnes', jsonb_build_object(
      'id', pid, 'nom', coalesce(p.nom, p.email), 'role', p.role, 'actif', p.actif, 'email', p.email,
      'creeLe', maintenant, 'creePar', 'serveur', 'modifieLe', maintenant, 'modifiePar', 'serveur'), auth.uid(), p.entreprise_id)
    on conflict (id) do nothing;
    update profils set personne_id = pid where user_id = p.user_id;
    p.personne_id := pid;
  end if;
  return jsonb_build_object(
    'userId', p.user_id, 'email', p.email, 'nom', p.nom, 'role', p.role, 'personneId', p.personne_id, 'actif', p.actif,
    'entreprise', (select jsonb_build_object('id', e.id, 'code', e.code, 'nom', e.nom, 'statut', e.statut, 'demo', e.demo, 'reinitLe', e.reinit_le) from entreprises e where e.id = p.entreprise_id),
    'sites', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'nom', s.nom) order by s.nom)
                       from sites s where s.id in (select public.mes_sites())), '[]'::jsonb),
    'siteDefaut', p.site_defaut,
    'abonnement', public.droits_entreprise(p.entreprise_id),
    'adminPlateforme', public.est_admin_plateforme());
end $$;
revoke all on function public.mon_profil() from public, anon;
grant execute on function public.mon_profil() to authenticated;
