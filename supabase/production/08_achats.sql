-- ===== 08_achats.sql — copie générée de supabase/achats.sql (empreinte bec7170b8c2dd45c) : ne pas modifier ici =====
-- GMAO terrain — Volet C, étape C2 : seuils, achats et valorisation (rejouable). APRÈS magasin.sql.
-- Voir docs/VOLET_C_CONCEPTION.md.
--   seuils        : module magasin ; le magasinier propose, le responsable valide.
--   achats        : module achats ; magasinier / responsable rédigent ; seul le responsable valide, refuse ou
--                   demande de compléter ; le rôle « achats » renseigne la commande externe d'une demande validée.
--   valorisations : module achats ; prix d'une entrée de stock ; correction réservée au responsable.
--   Les prix ne sont lisibles que par responsable, magasinier, achats et pilote : fiches achats / valorisations
--   ET lignes de journal qui les concernent (sinon l'historique « avant / après » révélerait les montants).
--   Rôle facultatif « achats » (V3 §24).

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in ('localisations','equipements','personnes',
  'demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations'));

alter table public.profils drop constraint if exists profils_role_check;
alter table public.profils add constraint profils_role_check
  check (role in ('responsable','technicien','prestataire','magasinier','achats','exploitation','pilote'));

create or replace function public.module_de(t text)
returns text language sql immutable set search_path = public as $$
  select case when t in ('articles', 'mouvements', 'besoins', 'seuils') then 'magasin'
              when t in ('achats', 'valorisations') then 'achats'
              when t = 'programmes' then 'preventif' else 'base' end
$$;
create or replace function public.peut_ecrire(r text, t text)
returns boolean language sql immutable set search_path = public as $$
  select case
    when r is null or r = 'pilote' then false
    when r = 'responsable' then true
    when t in ('demandes', 'journal', 'photos') then true
    when t = 'ots' then r in ('technicien', 'prestataire')
    when t in ('articles', 'seuils') then r = 'magasinier'
    when t in ('mouvements', 'besoins') then r in ('magasinier', 'technicien', 'prestataire')
    when t in ('achats', 'valorisations') then r in ('magasinier', 'achats')
    else false
  end
$$;
revoke execute on function public.module_de(text) from public, anon, authenticated;
revoke execute on function public.peut_ecrire(text, text) from public, anon, authenticated;

-- Qui peut voir les montants (V3 §24 : prix masqués aux techniciens, y compris par l'API).
create or replace function public.voit_couts()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.mon_role() in ('responsable', 'magasinier', 'achats', 'pilote'), false)
$$;
revoke all on function public.voit_couts() from public, anon;
grant execute on function public.voit_couts() to authenticated;

drop policy if exists "lecture equipe" on public.fiches;
create policy "lecture equipe" on public.fiches for select to authenticated using (
  public.mon_role() is not null
  and entreprise_id = public.mon_entreprise()
  and (site_id is null or site_id in (select public.mes_sites()))
  and (public.voit_couts()
       or not (type in ('achats', 'valorisations') or (type = 'journal' and data->>'entite' in ('achats', 'valorisations')))));

create or replace function public.controle_invitation(ent uuid, p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim jsonb; mx integer; existant uuid; p profils; s record; v_email text := lower(trim(p_email));
begin
  lim := public.droits_entreprise(ent);
  if lim is null then raise exception 'Entreprise sans abonnement'; end if;
  if not coalesce((lim->>'ecriture')::boolean, false) then raise exception 'Abonnement suspendu ou expiré'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Adresse e-mail invalide'; end if;
  if p_role not in ('responsable','technicien','prestataire','magasinier','achats','exploitation','pilote') then raise exception 'Rôle inconnu'; end if;
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

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  droits := public.droits_entreprise(ent);
  mes := array(select public.mes_sites());
  select site_defaut into defaut from profils where user_id = auth.uid();
  if defaut is null or not (defaut = any (mes)) then
    defaut := case when coalesce(array_length(mes, 1), 0) = 1 then mes[1] end;
  end if;

  for f in select value from jsonb_array_elements(lot) loop
    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    cible := case when t = 'journal' then p->>'entite' else t end;
    motif := null; s := null;
    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- Renvoi identique d'un mouvement déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t = 'mouvements' and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? public.module_de(cible)) then
      motif := 'module « ' || public.module_de(cible) || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    -- besoins : la réservation et ses suites appartiennent au magasin
    elsif t = 'besoins' and terrain and (p ? 'qteReservee' or p ? 'delai' or coalesce(p->>'statut', 'demande') not in ('demande', 'annule')) then
      motif := 'réservation et disponibilité : réservées au magasin';
    elsif t = 'besoins' and terrain and ex.id is null and coalesce(p->>'otId', '') = '' then
      motif := 'un besoin de pièce se rattache à une intervention';
    -- mouvements : le terrain ne fait que retrait urgent et retour, rattachés à une intervention ou un besoin
    elsif t = 'mouvements' and ex.id is null and terrain and not (
            ((p->>'type') = 'remise' and coalesce((p->>'urgent')::boolean, false))
            or (p->>'type') in ('retour', 'sortie'))
    then
      motif := 'mouvement de stock réservé au magasin (terrain : retrait urgent ou retour)';
    elsif t = 'mouvements' and ex.id is null and terrain and coalesce(p->>'otId', '') = '' and coalesce(p->>'besoinId', '') = '' then
      motif := 'mouvement de stock hors intervention : réservé au magasin';
    elsif t = 'mouvements' and ex.id is not null and (terrain or exists (select 1 from jsonb_object_keys(p) k where k not in ('verifieLe', 'verifiePar', 'aVerifier', 'modifieLe', 'modifiePar'))) then
      motif := 'un mouvement de stock ne se modifie pas (seule sa vérification par le magasin)';
    -- volet C : seuils proposés par le magasin, validés par le responsable
    elsif t = 'seuils' and r <> 'responsable' and (coalesce(p->>'statut', 'propose') <> 'propose' or p ? 'valideLe' or p ? 'validePar') then
      motif := 'validation des seuils : réservée au responsable';
    elsif t = 'seuils' and r <> 'responsable' and ex.id is not null and ex.data->>'statut' = 'valide' then
      motif := 'un seuil validé ne se modifie pas : proposez une nouvelle version';
    elsif t = 'seuils' and ex.id is null and coalesce(p->>'articleId', '') = '' then
      motif := 'un seuil se rattache à un article';
    -- volet C : demandes d'achat (V3 §17) ; aucune commande n'est envoyée par l'appli
    elsif t = 'achats' and r = 'achats' and ex.id is null then
      motif := 'une demande d''achat est rédigée par le magasin ou le responsable';
    elsif t = 'achats' and r = 'achats' and coalesce(ex.data->>'statut', '') not in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue') then
      motif := 'demande d''achat pas encore validée par le responsable';
    elsif t = 'achats' and r = 'achats' and p ? 'statut' and p->>'statut' not in ('transmise', 'commandee') then
      motif := 'les achats renseignent la commande, pas la validation';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') in ('brouillon', 'soumise', 'a_completer')
          and p ? 'statut' and p->>'statut' not in ('brouillon', 'soumise', 'annulee') then
      motif := 'validation d''une demande d''achat : réservée au responsable';
    elsif t = 'achats' and r = 'magasinier' and coalesce(ex.data->>'statut', 'brouillon') not in ('brouillon', 'soumise', 'a_completer')
          and not (p->>'statut' = 'close' and coalesce(ex.data->>'statut', '') in ('commandee', 'partiellement_recue', 'recue')
                   and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'closLe', 'closPar', 'motifCloture', 'modifieLe', 'modifiePar'))) then
      motif := 'demande d''achat validée : modification réservée au responsable et aux achats';
    -- volet C : prix des entrées ; une correction de prix est une régularisation du responsable
    elsif t = 'valorisations' and ex.id is null and coalesce(p->>'mouvementId', '') = '' then
      motif := 'un prix se rattache à une entrée de stock';
    elsif t = 'valorisations' and ex.id is not null and r <> 'responsable' then
      motif := 'correction d''un prix : réservée au responsable';
    end if;

    if motif is null and t not in ('personnes', 'articles') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        defaut);
      if s is null then motif := 'site non déterminé (choisissez un site)';
      elsif not (s = any (mes)) then motif := 'site non autorisé';
      elsif ex.site_id is not null and s <> ex.site_id and r <> 'responsable' then motif := 'changement de site réservé au responsable';
      end if;
    end if;

    if motif is not null then
      refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
      refuses := refuses || (f->>'id');
      continue;
    end if;

    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
    if t = 'mouvements' and ex.id is not null then
      update fiches set data = fiches.data || p, seq = nextval('public.fiches_seq'), recu_le = now() where id = ex.id;   -- vérification seule
    elsif t in ('journal', 'mouvements', 'photos') then
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do nothing;
    else
      insert into fiches (id, type, data, auteur, entreprise_id, site_id)
      values (f->>'id', t, p || data_site, auth.uid(), ent, s)
      on conflict (id) do update
        set data = fiches.data || excluded.data, site_id = excluded.site_id,
            seq = nextval('public.fiches_seq'), recu_le = now(), auteur = auth.uid();
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('acceptes', n, 'refuses', refus);
end $$;
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;
