-- ===== 16_roles_r1.sql — copie générée de supabase/roles_r1.sql (empreinte 9717964d661a9956) : ne pas modifier ici =====
-- GMAO terrain — lot R1 « navigation et droits par rôle » (docs/MAQUETTES_R1.md §5). APRÈS securite.sql. Rejouable.
-- FICHIER GÉNÉRÉ par scripts/generer_roles_r1.py : ne pas modifier à la main.
-- S1 prestataire : ne lit et n'écrit que ses interventions (celles où il est intervenant) et ce qui s'y rattache ;
--    parc, lieux, personnes, articles, compteurs et relevés restent lisibles (signaler, relever).
-- S2 journal d'audit : lu en entier par le responsable, la direction (pilote) et l'administrateur de l'entreprise ;
--    les autres ne lisent que les lignes de leurs propres saisies et de leurs interventions.
-- S3 administrateur de l'entreprise : droit cumulable (profils.admin_client) ; il invite, active, change les rôles et
--    les sites ; les responsables actuels le reçoivent ; le premier compte d'une entreprise l'obtient à l'invitation.

-- ---------- S3 : droit « administrateur de l'entreprise » ----------
alter table public.profils add column if not exists admin_client boolean not null default false;
do $$ begin
  -- migration (une seule fois) : chaque responsable actuel devient administrateur de son entreprise
  if not exists (select 1 from public.profils where admin_client) then
    update public.profils set admin_client = true where role = 'responsable';
  end if;
end $$;

create or replace function public.est_admin_client()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select admin_client and actif from profils where user_id = auth.uid()), false)
$$;
create or replace function public.voit_journal_complet()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mon_role() in ('responsable', 'pilote') or public.est_admin_client()
$$;
create or replace function public.ma_personne()
returns text language sql stable security definer set search_path = public as $$
  select personne_id from profils where user_id = auth.uid()
$$;
revoke all on function public.est_admin_client() from public, anon;
grant execute on function public.est_admin_client() to authenticated;
revoke all on function public.voit_journal_complet() from public, anon;
grant execute on function public.voit_journal_complet() to authenticated;
revoke all on function public.ma_personne() from public, anon, authenticated;

/** Donner ou retirer le droit d'administrateur de l'entreprise (jamais au dernier administrateur actif). */
create or replace function public.definir_admin_client(cible uuid, valeur boolean)
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise();
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = ent) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if not valeur and not exists (select 1 from profils where entreprise_id = ent and admin_client and actif and user_id <> cible) then
    raise exception 'L''entreprise doit garder au moins un administrateur';
  end if;
  update profils set admin_client = valeur where user_id = cible;
end $$;
revoke all on function public.definir_admin_client(uuid, boolean) from public, anon;
grant execute on function public.definir_admin_client(uuid, boolean) to authenticated;

-- ---------- S1 : périmètre du prestataire ----------
/** Intervention confiée à l'appelant (il en est intervenant). */
create or replace function public.ot_a_moi(oid text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(oid, '') <> '' and exists (
    select 1 from fiches o where o.id = oid and o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())))
$$;
revoke all on function public.ot_a_moi(text) from public, anon, authenticated;

/** Lecture autorisée à un prestataire (appelée par la règle de lecture de « fiches »). */
create or replace function public.prestataire_voit(t text, fid text, d jsonb, aut uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  if t in ('equipements', 'localisations', 'personnes', 'articles', 'compteurs', 'releves', 'parametres', 'journal') then return true; end if;
  if t = 'ots' then return public.ot_a_moi(fid); end if;
  if t = 'demandes' then
    return aut = auth.uid() or exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'demandeIds' ? fid and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));
  end if;
  if t in ('besoins', 'mouvements') then return public.ot_a_moi(d->>'otId'); end if;
  if t = 'programmes' then
    return exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise() and o.data->>'programmeId' = fid
      and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));
  end if;
  if t = 'photos' then
    select type, id, data, auteur into x from fiches where id = d->>'parentId' and entreprise_id = public.mon_entreprise();
    return found and x.type <> 'photos' and public.prestataire_voit(x.type, x.id, x.data, x.auteur);
  end if;
  return false;   -- magasin, achats, prix, seuils, factures, fournisseurs…
end $$;
revoke all on function public.prestataire_voit(text, text, jsonb, uuid) from public, anon;
grant execute on function public.prestataire_voit(text, text, jsonb, uuid) to authenticated;   -- appelée par la règle de lecture

/** Motif de refus d'une écriture du prestataire hors de ses interventions (null = accepté). */
create or replace function public.prestataire_refus(t text, fid text, p jsonb, nouvelle boolean)
returns text language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  select type, id, data, auteur into x from fiches where id = fid and entreprise_id = public.mon_entreprise();
  if t = 'ots' then
    if nouvelle then return 'un prestataire ne crée pas d''intervention : signalez, le responsable vous la confie'; end if;
    if not public.ot_a_moi(fid) then return 'intervention qui ne vous est pas confiée'; end if;
  elsif t in ('besoins', 'mouvements') then
    if not public.ot_a_moi(coalesce(p->>'otId', x.data->>'otId')) then return 'pièce hors de vos interventions'; end if;
  elsif t = 'demandes' then
    if not nouvelle and x.auteur is distinct from auth.uid() then return 'demande qui n''est pas la vôtre'; end if;
  elsif t = 'photos' then
    if not public.prestataire_voit(coalesce(p->>'parentType', x.data->>'parentType'),
        coalesce(p->>'parentId', x.data->>'parentId'),
        (select data from fiches where id = coalesce(p->>'parentId', x.data->>'parentId')),
        (select auteur from fiches where id = coalesce(p->>'parentId', x.data->>'parentId'))) then
      return 'fichier hors de vos interventions';
    end if;
  elsif t = 'journal' then
    if (p->>'entite') = 'ots' and not public.ot_a_moi(p->>'entiteId')
       and exists (select 1 from fiches where id = p->>'entiteId') then return 'intervention qui ne vous est pas confiée'; end if;
  end if;
  return null;
end $$;
revoke all on function public.prestataire_refus(text, text, jsonb, boolean) from public, anon, authenticated;

-- ---------- S2 : journal d'audit restreint ----------
/** Ligne du journal lisible par l'appelant. */
create or replace function public.journal_visible(d jsonb, aut uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  if public.voit_journal_complet() or aut = auth.uid() then return true; end if;
  select type, id, data, auteur into x from fiches where id = d->>'entiteId' and entreprise_id = public.mon_entreprise();
  if not found then return false; end if;
  if x.auteur = auth.uid() then return true; end if;                       -- ses propres fiches
  if x.type = 'ots' then return public.ot_a_moi(x.id); end if;             -- ses interventions
  if x.type in ('besoins', 'mouvements') then return public.ot_a_moi(x.data->>'otId'); end if;
  if x.type = 'demandes' then
    return exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'demandeIds' ? x.id and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));
  end if;
  return false;
end $$;
revoke all on function public.journal_visible(jsonb, uuid) from public, anon;
grant execute on function public.journal_visible(jsonb, uuid) to authenticated;   -- appelée par la règle de lecture

-- Règle de lecture des fiches (version de energie.sql + périmètre du prestataire + journal restreint).
drop policy if exists "lecture equipe" on public.fiches;
create policy "lecture equipe" on public.fiches for select to authenticated using (
  public.mon_role() is not null
  and entreprise_id = public.mon_entreprise()
  and (site_id is null or site_id in (select public.mes_sites()))
  and (public.voit_couts()
       or not (type in ('achats', 'valorisations', 'factures_energie')
               or (type = 'journal' and data->>'entite' in ('achats', 'valorisations', 'factures_energie'))
               or (type = 'photos' and data->>'parentType' = 'factures_energie')))
  and (public.mon_role() <> 'prestataire' or public.prestataire_voit(type, id, data, auteur))
  and (type <> 'journal' or public.journal_visible(data, auteur)));
create index if not exists fiches_ots_intervenants on public.fiches using gin ((data->'intervenants')) where type = 'ots';

-- Comptes et affectations : lisibles par l'administrateur de l'entreprise (et le responsable, pour l'affichage).
drop policy if exists "profil lisible" on public.profils;
create policy "profil lisible" on public.profils for select to authenticated using (
  user_id = auth.uid() or public.est_admin_plateforme()
  or ((public.mon_role() = 'responsable' or public.est_admin_client()) and entreprise_id = public.mon_entreprise()));
drop policy if exists "affectations visibles" on public.profil_sites;
create policy "affectations visibles" on public.profil_sites for select to authenticated using (
  user_id = auth.uid() or public.est_admin_plateforme()
  or ((public.mon_role() = 'responsable' or public.est_admin_client())
      and exists (select 1 from profils p where p.user_id = profil_sites.user_id and p.entreprise_id = public.mon_entreprise())));

-- ---------- fonctions mises à jour ----------
create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean; mod text; u text;
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
    -- D2 bis : un compteur d'équipement (heures, cycles) relève du préventif, un compteur de ressource de l'énergie.
    mod := public.module_de(cible);
    if cible in ('compteurs', 'releves') then
      u := case
        when t = 'compteurs' then coalesce(p->>'usage', ex.data->>'usage')
        when t = 'releves' then (select c.data->>'usage' from fiches c where c.id = coalesce(p->>'compteurId', ex.data->>'compteurId') and c.entreprise_id = ent)
        else (select case when x.type = 'compteurs' then x.data->>'usage'
                          else (select c.data->>'usage' from fiches c where c.id = x.data->>'compteurId' and c.entreprise_id = ent) end
              from fiches x where x.id = p->>'entiteId' and x.entreprise_id = ent)
      end;
      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? mod) then
      motif := 'module « ' || mod || ' » non inclus dans l''abonnement';
    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    -- R1 : un prestataire n'écrit que sur les interventions qui lui sont confiées (et ce qui s'y rattache).
    elsif r = 'prestataire' and public.prestataire_refus(t, f->>'id', p, ex.id is null) is not null then
      motif := public.prestataire_refus(t, f->>'id', p, ex.id is null);
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then
      motif := 'intervention clôturée : modification réservée au responsable';
    elsif t = 'ots' and r <> 'responsable' and p->>'statut' = 'cloturee' and public.cloture_par_responsable(ent) then
      motif := 'clôture réservée au responsable (réglage de l''entreprise) : terminez l''intervention, le responsable la clôture';
    -- réglages de l'entreprise : une seule fiche, d'identifiant fixe
    elsif t = 'parametres' and f->>'id' <> ('parametres-' || ent::text) then
      motif := 'paramètres : identifiant réservé à l''entreprise';
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
    -- intégrité : une fiche rattachée à un équipement exige un équipement connu de l'entreprise (lot en cours compris)
    elsif t in ('demandes', 'ots', 'programmes') and ex.id is null and coalesce(p->>'equipementId', '') <> ''
          and not exists (select 1 from fiches x where x.id = p->>'equipementId' and x.type = 'equipements' and x.entreprise_id = ent) then
      motif := 'équipement inconnu de l''entreprise (créé hors connexion ou supprimé ?)';
    -- volet D : compteurs (référentiel du responsable), relevés jamais modifiés, factures à lecture restreinte
    elsif t = 'compteurs' and ex.id is not null
          and ((p ? 'mode' and p->'mode' is distinct from ex.data->'mode') or (p ? 'unite' and p->'unite' is distinct from ex.data->'unite')
               or (p ? 'coefficient' and p->'coefficient' is distinct from ex.data->'coefficient')
               or (p ? 'usage' and p->'usage' is distinct from ex.data->'usage'))
          and exists (select 1 from fiches x where x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = ex.id) then
      motif := 'compteur déjà relevé : usage, mode, unité et coefficient ne changent plus (rupture déclarée ou nouveau compteur)';
    elsif t = 'releves' and ex.id is null and not exists (select 1 from fiches c where c.id = p->>'compteurId' and c.type = 'compteurs' and c.entreprise_id = ent) then
      motif := 'un relevé se rattache à un compteur connu';
    elsif t = 'releves' and ex.id is null and r <> 'responsable' and (p ? 'decision' or p ? 'decidePar' or p ? 'decideLe') then
      motif := 'qualification d''un relevé : réservée au responsable';
    elsif t = 'releves' and ex.id is null and coalesce(p->>'remplaceId', '') <> '' and not exists (
            select 1 from fiches x where x.id = p->>'remplaceId' and x.type = 'releves' and x.entreprise_id = ent and x.data->>'compteurId' = p->>'compteurId') then
      motif := 'une correction remplace un relevé du même compteur';
    elsif t = 'releves' and ex.id is not null and (r <> 'responsable' or exists (
            select 1 from jsonb_object_keys(p) k where k not in ('decision', 'motifDecision', 'decideLe', 'decidePar', 'modifieLe', 'modifiePar'))) then
      motif := 'un relevé ne se modifie pas : saisissez une correction (seule sa qualification par le responsable)';
    end if;

    if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs') then
      s := coalesce(
        public.uuid_ou_null(p->>'siteId'),
        ex.site_id,
        case when t = 'journal' then (select site_id from fiches where id = p->>'entiteId' and entreprise_id = ent) end,
        case when t = 'photos' then (select site_id from fiches where id = p->>'parentId' and entreprise_id = ent) end,
        case when t in ('besoins', 'mouvements') then (select site_id from fiches where id = coalesce(p->>'besoinId', p->>'otId') and entreprise_id = ent) end,
        case when t = 'valorisations' then (select site_id from fiches where id = p->>'mouvementId' and entreprise_id = ent) end,
        case when t = 'releves' then (select site_id from fiches where id = p->>'compteurId' and entreprise_id = ent) end,
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
    'adminPlateforme', public.est_admin_plateforme(),
    'adminClient', p.admin_client,
    -- inscrit mais session sans code : la console demande le code (ou l'inscription de l'application d'authentification)
    'adminMfa', case when not public.admin_inscrit() then null
                     else (select jsonb_build_object('obligatoire', a.mfa_obligatoire, 'niveau', public.niveau_session())
                           from admins_plateforme a where a.user_id = auth.uid()) end);
end $$;
revoke all on function public.mon_profil() from public, anon;
grant execute on function public.mon_profil() to authenticated;

create or replace function public.preparer_invitation(p_email text, p_role text, p_sites uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  perform public.limiter('invitation:' || public.mon_entreprise(), 20, interval '1 hour', 'Trop d''invitations en une heure : réessayez plus tard');
  return public.controle_invitation(public.mon_entreprise(), p_email, p_role, p_sites);
end $$;
revoke all on function public.preparer_invitation(text, text, uuid[]) from public, anon;
grant execute on function public.preparer_invitation(text, text, uuid[]) to authenticated;

create or replace function public.definir_profil(cible uuid, nouveau_role text, nouveau_nom text, est_actif boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.est_admin_client() then
    raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501';
  end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = public.mon_entreprise()) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if cible = auth.uid() and not est_actif then
    raise exception 'Vous ne pouvez pas désactiver votre propre compte';
  end if;
  update profils set role = coalesce(nouveau_role, role), nom = coalesce(nullif(trim(nouveau_nom), ''), nom),
    actif = coalesce(est_actif, actif) where user_id = cible;
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'nom', p.nom, 'actif', p.actif),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = p.personne_id;
end $$;
revoke all on function public.definir_profil(uuid, text, text, boolean) from public, anon;
grant execute on function public.definir_profil(uuid, text, text, boolean) to authenticated;

create or replace function public.affecter_sites(cible uuid, liste uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); s uuid;
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
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

create or replace function public.utilisation()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); lim jsonb;
begin
  if not (public.est_admin_client() or public.mon_role() = 'responsable') then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
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

create or replace function public.finaliser_invitation(p_user uuid, p_entreprise uuid, p_role text, p_nom text, p_sites uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_email text; s uuid;
begin
  select u.email into v_email from auth.users u where u.id = p_user;
  insert into profils (user_id, email, nom) values (p_user, v_email, coalesce(nullif(trim(p_nom), ''), split_part(v_email, '@', 1)))
    on conflict (user_id) do nothing;
  update profils set entreprise_id = p_entreprise, role = p_role, actif = true,
    nom = coalesce(nullif(trim(p_nom), ''), nom), site_defaut = p_sites[1] where user_id = p_user;   -- quota total : déclencheur
  -- R1 : le premier compte d'une entreprise (invité par Perfora) en devient l'administrateur.
  if not exists (select 1 from profils where entreprise_id = p_entreprise and admin_client and actif and user_id <> p_user) then
    update profils set admin_client = true where user_id = p_user;
  end if;
  foreach s in array p_sites loop
    insert into profil_sites (user_id, site_id) values (p_user, s) on conflict do nothing;      -- quota site : déclencheur
  end loop;
end $$;
revoke all on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) from public, anon, authenticated;
grant execute on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) to service_role;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
