-- ===== 04_quotas.sql — copie générée de supabase/quotas.sql (empreinte d71d058d79dbab3c) : ne pas modifier ici =====
-- GMAO terrain — Volet A, étape A3 : quotas, invitations, affectation des sites (rejouable).
-- À exécuter APRÈS multitenant.sql. Voir docs/VOLET_A_CONCEPTION.md §3.5 et §3.6.
--
-- Les quotas sont des DÉCLENCHEURS : ils s'appliquent à toute écriture (appli, fonction
-- d'invitation, tableau de bord Supabase, SQL). Limites = pack + dérogations (droits_entreprise).
-- Un compte actif compte une fois dans l'entreprise et une fois sur chaque site affecté.

-- ---------- comptage ----------
create or replace function public.nb_actifs_entreprise(ent uuid, sauf uuid)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from profils where entreprise_id = ent and actif and user_id is distinct from sauf
$$;
create or replace function public.nb_actifs_site(site uuid, sauf uuid)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from profil_sites ps join profils p on p.user_id = ps.user_id
  where ps.site_id = site and p.actif and ps.user_id is distinct from sauf
$$;

-- ---------- déclencheurs de quotas ----------
create or replace function public.quota_profils()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim jsonb; mx integer; s record;
begin
  if not new.actif or new.entreprise_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.actif and old.entreprise_id is not distinct from new.entreprise_id then return new; end if;
  lim := public.droits_entreprise(new.entreprise_id);
  mx := (lim->>'maxUtilisateursTotal')::int;
  if mx is not null and public.nb_actifs_entreprise(new.entreprise_id, new.user_id) + 1 > mx then
    raise exception 'Quota atteint : % utilisateur(s) actif(s) maximum pour l''entreprise (pack %)', mx, lim->>'packNom' using errcode = 'P0001';
  end if;
  mx := (lim->>'maxUtilisateursSite')::int;
  if mx is not null then
    for s in select ps.site_id, si.nom from profil_sites ps join sites si on si.id = ps.site_id where ps.user_id = new.user_id loop
      if public.nb_actifs_site(s.site_id, new.user_id) + 1 > mx then
        raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, s.nom using errcode = 'P0001';
      end if;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists gmao_quota_profils on public.profils;
create trigger gmao_quota_profils before insert or update of actif, entreprise_id on public.profils
  for each row execute function public.quota_profils();

create or replace function public.quota_profil_sites()
returns trigger language plpgsql security definer set search_path = public as $$
declare p profils; si sites; mx integer;
begin
  select * into p from profils where user_id = new.user_id;
  select * into si from sites where id = new.site_id;
  if p.entreprise_id is null or si.entreprise_id is distinct from p.entreprise_id then
    raise exception 'Site hors de l''entreprise du compte' using errcode = 'P0001';
  end if;
  if not p.actif then return new; end if;
  mx := (public.droits_entreprise(p.entreprise_id)->>'maxUtilisateursSite')::int;
  if mx is not null and public.nb_actifs_site(new.site_id, new.user_id) + 1 > mx then
    raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, si.nom using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists gmao_quota_profil_sites on public.profil_sites;
create trigger gmao_quota_profil_sites before insert on public.profil_sites
  for each row execute function public.quota_profil_sites();

create or replace function public.quota_sites()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim jsonb; mx integer;
begin
  if not new.actif then return new; end if;
  if tg_op = 'UPDATE' and old.actif then return new; end if;
  lim := public.droits_entreprise(new.entreprise_id);
  mx := (lim->>'maxSites')::int;
  if mx is not null and (select count(*) from sites where entreprise_id = new.entreprise_id and actif and id <> new.id) + 1 > mx then
    raise exception 'Quota atteint : % site(s) maximum (pack %)', mx, lim->>'packNom' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists gmao_quota_sites on public.sites;
create trigger gmao_quota_sites before insert or update of actif on public.sites
  for each row execute function public.quota_sites();

-- ---------- utilisation (écran Équipe) ----------
create or replace function public.utilisation()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); lim jsonb;
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  lim := public.droits_entreprise(ent);
  return jsonb_build_object(
    'actifs', public.nb_actifs_entreprise(ent, null), 'maxTotal', lim->'maxUtilisateursTotal',
    'maxSite', lim->'maxUtilisateursSite', 'maxSites', lim->'maxSites',
    'sites', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nom', s.nom, 'actifs', public.nb_actifs_site(s.id, null)) order by s.nom)
                       from sites s where s.entreprise_id = ent and s.actif), '[]'::jsonb),
    'affectations', coalesce((select jsonb_agg(jsonb_build_object('userId', ps.user_id, 'siteId', ps.site_id))
                              from profil_sites ps join profils p on p.user_id = ps.user_id where p.entreprise_id = ent), '[]'::jsonb));
end $$;
revoke all on function public.utilisation() from public, anon;
grant execute on function public.utilisation() to authenticated;

-- ---------- affectation des sites d'un membre (responsable) ----------
create or replace function public.affecter_sites(cible uuid, liste uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); s uuid;
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = ent) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if coalesce(array_length(liste, 1), 0) = 0 then raise exception 'Choisissez au moins un site'; end if;
  if exists (select 1 from unnest(liste) x where x not in (select id from sites where entreprise_id = ent and actif)) then
    raise exception 'Site inconnu ou inactif';
  end if;
  delete from profil_sites where user_id = cible and site_id <> all (liste);
  foreach s in array liste loop
    insert into profil_sites (user_id, site_id) values (cible, s) on conflict do nothing;   -- quota vérifié par déclencheur
  end loop;
  update profils set site_defaut = liste[1] where user_id = cible and (site_defaut is null or site_defaut <> all (liste));
end $$;
revoke all on function public.affecter_sites(uuid, uuid[]) from public, anon;
grant execute on function public.affecter_sites(uuid, uuid[]) to authenticated;

-- ---------- invitation : contrôle (au nom du responsable) puis rattachement (fonction serveur) ----------
create or replace function public.preparer_invitation(p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); lim jsonb; mx integer; existant uuid; p profils; s record; v_email text := lower(trim(p_email));
begin
  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;
  lim := public.droits_entreprise(ent);
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
      if public.nb_actifs_site(s.id, null) + 1 > mx then
        raise exception 'Quota atteint : % utilisateur(s) maximum sur « % »', mx, s.nom;
      end if;
    end loop;
  end if;
  return jsonb_build_object('entreprise_id', ent, 'invite_par', auth.uid(), 'user_id_existant', existant);
end $$;
revoke all on function public.preparer_invitation(text, text, uuid[]) from public, anon;
grant execute on function public.preparer_invitation(text, text, uuid[]) to authenticated;

-- Appelée uniquement par la fonction serveur « inviter » (clé secrète), jamais par l'appli.
create or replace function public.finaliser_invitation(p_user uuid, p_entreprise uuid, p_role text, p_nom text, p_sites uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_email text; s uuid;
begin
  select u.email into v_email from auth.users u where u.id = p_user;
  insert into profils (user_id, email, nom) values (p_user, v_email, coalesce(nullif(trim(p_nom), ''), split_part(v_email, '@', 1)))
    on conflict (user_id) do nothing;
  update profils set entreprise_id = p_entreprise, role = p_role, actif = true,
    nom = coalesce(nullif(trim(p_nom), ''), nom), site_defaut = p_sites[1] where user_id = p_user;   -- quota total : déclencheur
  foreach s in array p_sites loop
    insert into profil_sites (user_id, site_id) values (p_user, s) on conflict do nothing;      -- quota site : déclencheur
  end loop;
end $$;
revoke all on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) from public, anon, authenticated;
grant execute on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) to service_role;

-- Pour que la liste d'équipe montre les sites de chacun.
grant select on public.profil_sites to authenticated;
