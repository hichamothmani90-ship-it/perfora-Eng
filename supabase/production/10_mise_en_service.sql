-- ===== 10_mise_en_service.sql — copie générée de supabase/mise_en_service.sql (empreinte 6c8c210c16e06f31) : ne pas modifier ici =====
-- GMAO terrain — mise en service des clients + D2 bis (rejouable). APRÈS energie.sql.
-- Voir docs/DISCUSSION_MODELE_DONNEES.md (§3 compteurs, §5 démarrage d'un client) et docs/CLASSIFICATION_PARC.md.
--   D2 bis       : le module d'un compteur dépend de son usage : « equipement » (heures, cycles) → preventif (pack Pro),
--                  « ressource » → energie (pack Entreprise) ; idem pour ses relevés et son journal. Usage figé après
--                  le premier relevé.
--   fournisseurs : liste commune à l'entreprise (module magasin) ; écrite par responsable, magasinier, achats.
--   Reprise      : pf_referentiel, pf_importer (vérification à blanc ou import, tout ou rien, lot annulable),
--                  pf_annuler_lot (seulement si le client n'a rien saisi depuis), pf_mes_lire / pf_mes_etape (étapes de
--                  mise en service). Réservé à l'administrateur plateforme.

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs'));

create or replace function public.module_de(t text)
returns text language sql immutable set search_path = public as $$
  select case when t in ('articles', 'mouvements', 'besoins', 'seuils', 'fournisseurs') then 'magasin'
              when t in ('achats', 'valorisations') then 'achats'
              when t in ('compteurs', 'releves', 'factures_energie') then 'energie'
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
    when t = 'fournisseurs' then r in ('magasinier', 'achats')
    when t = 'releves' then r in ('technicien', 'prestataire', 'exploitation')
    when t = 'factures_energie' then r = 'achats'
    else false
  end
$$;
revoke execute on function public.module_de(text) from public, anon, authenticated;
revoke execute on function public.peut_ecrire(text, text) from public, anon, authenticated;

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

-- ---------- reprise des données d'un client (console plateforme) ----------
create table if not exists public.pf_lots_import (
  id            text primary key,
  entreprise_id uuid not null references public.entreprises(id),
  cree_le       timestamptz not null default now(),
  par           uuid,
  fichier       text,
  resume        jsonb not null default '{}'::jsonb,
  seq_fin       bigint,                       -- dernière fiche du lot : toute fiche reçue après = activité
  annule_le     timestamptz
);
alter table public.pf_lots_import add column if not exists seq_fin bigint;
alter table public.pf_lots_import enable row level security;     -- aucune politique : accès par les fonctions pf_* seulement
create table if not exists public.pf_mise_en_service (
  entreprise_id uuid primary key references public.entreprises(id),
  etapes        jsonb not null default '{}'::jsonb,
  maj_le        timestamptz not null default now()
);
alter table public.pf_mise_en_service enable row level security;

-- Codes déjà présents chez le client (pour relier le kit à l'existant et refuser les doublons).
create or replace function public.pf_referentiel(p_entreprise uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return jsonb_build_object(
    'sites', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', code, 'nom', nom) order by code), '[]'::jsonb) from sites where entreprise_id = p_entreprise and actif),
    'localisations', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', data->>'code', 'siteId', site_id)), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'localisations'),
    'equipements', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', data->>'code', 'siteId', site_id)), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'equipements'),
    'compteurs', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', data->>'code', 'siteId', site_id, 'unite', data->>'unite')), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'compteurs'),
    'articles', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ref', data->>'ref')), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'articles'),
    'fournisseurs', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nom', data->>'nom')), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'fournisseurs'),
    'personnes', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nom', data->>'nom')), '[]'::jsonb) from fiches where entreprise_id = p_entreprise and type = 'personnes'));
end $$;
revoke all on function public.pf_referentiel(uuid) from public, anon;
grant execute on function public.pf_referentiel(uuid) to authenticated;

-- Import d'un lot : tout ou rien. p_essai = vérification à blanc (même contrôles, rien n'est gardé).
create or replace function public.pf_importer(p_entreprise uuid, p_lot text, p_fichier text, p_fiches jsonb, p_essai boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; t text; d jsonb; s uuid; motif text; n integer := 0;
  refus jsonb := '[]'::jsonb; resume jsonb := '{}'::jsonb;
  admis constant text[] := array['localisations','equipements','compteurs','releves','fournisseurs','articles','mouvements','valorisations','programmes','personnes'];
  communs constant text[] := array['articles','fournisseurs','personnes'];
begin
  perform public.exiger_admin();
  if not exists (select 1 from entreprises where id = p_entreprise) then raise exception 'Entreprise inconnue'; end if;
  if coalesce(p_lot, '') !~ '^[A-Za-z0-9-]{6,64}$' then raise exception 'Identifiant de lot invalide'; end if;
  if exists (select 1 from pf_lots_import where id = p_lot) then raise exception 'Ce lot a déjà été importé'; end if;
  if jsonb_typeof(p_fiches) is distinct from 'array' or jsonb_array_length(p_fiches) = 0 then raise exception 'Aucune fiche à importer'; end if;
  if jsonb_array_length(p_fiches) > 20000 then raise exception 'Lot trop volumineux (20 000 fiches maximum) : découpez le kit'; end if;
  begin
    for f in select value from jsonb_array_elements(p_fiches) loop
      t := f->>'type'; motif := null; s := null;
      d := coalesce(f->'data', '{}'::jsonb) || jsonb_build_object('id', f->>'id', 'lotImport', p_lot);
      if not (t = any (admis)) then motif := 'type non importable';
      elsif coalesce(f->>'id', '') = '' then motif := 'identifiant manquant';
      elsif exists (select 1 from fiches where id = f->>'id') then motif := 'identifiant déjà utilisé';
      elsif not (t = any (communs)) then
        s := public.uuid_ou_null(d->>'siteId');
        if s is null or not exists (select 1 from sites where id = s and entreprise_id = p_entreprise) then motif := 'site absent ou d''une autre entreprise'; end if;
      end if;
      if motif is null then
        motif := case
          when t = 'equipements' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and upper(x.data->>'code') = upper(d->>'code')) then 'code équipement déjà utilisé'
          when t = 'compteurs' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and upper(x.data->>'code') = upper(d->>'code')) then 'code compteur déjà utilisé'
          when t = 'localisations' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and x.site_id = s and upper(x.data->>'code') = upper(d->>'code')) then 'code de lieu déjà utilisé sur ce site'
          when t = 'articles' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and upper(x.data->>'ref') = upper(d->>'ref')) then 'référence d''article déjà utilisée'
          when t = 'fournisseurs' and exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.type = t and lower(x.data->>'nom') = lower(d->>'nom')) then 'fournisseur déjà présent'
          when t in ('equipements', 'compteurs', 'localisations') and coalesce(d->>'code', '') = '' then 'code manquant'
          when t = 'articles' and coalesce(d->>'ref', '') = '' then 'référence manquante'
        end;
      end if;
      if motif is not null then
        refus := refus || jsonb_build_object('id', f->>'id', 'type', t, 'motif', motif);
        continue;
      end if;
      insert into fiches (id, type, data, auteur, entreprise_id, site_id) values (f->>'id', t, d, auth.uid(), p_entreprise, s);
      n := n + 1;
      resume := jsonb_set(resume, array[t], to_jsonb(coalesce((resume->>t)::int, 0) + 1));
    end loop;
    -- Références : chaque lien pointe vers une fiche du bon type, dans la même entreprise (lot ou existant).
    refus := refus || coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'type', x.type, 'motif', 'référence introuvable (' || r.k || ')'))
      from fiches x cross join lateral (values ('localisationId', 'localisations'), ('parentId', x.type), ('equipementId', 'equipements'),
        ('compteurId', 'compteurs'), ('articleId', 'articles'), ('mouvementId', 'mouvements'), ('fournisseurId', 'fournisseurs')) as r(k, cible)
      where x.entreprise_id = p_entreprise and x.data->>'lotImport' = p_lot and coalesce(x.data->>r.k, '') <> ''
        and not exists (select 1 from fiches y where y.id = x.data->>r.k and y.entreprise_id = p_entreprise and y.type = r.cible)), '[]'::jsonb);
    if p_essai or jsonb_array_length(refus) > 0 then raise exception 'pf_essai'; end if;
  exception when raise_exception then
    if sqlerrm <> 'pf_essai' then raise; end if;   -- annule les insertions du bloc ; les compteurs restent
  end;
  if not p_essai and jsonb_array_length(refus) = 0 then
    insert into pf_lots_import (id, entreprise_id, par, fichier, resume, seq_fin)
    values (p_lot, p_entreprise, auth.uid(), left(p_fichier, 200), resume,
            (select max(seq) from fiches where entreprise_id = p_entreprise and data->>'lotImport' = p_lot));
  end if;
  return jsonb_build_object('essai', p_essai, 'acceptes', n, 'refus', refus, 'resume', resume,
    'importe', not p_essai and jsonb_array_length(refus) = 0);
end $$;
revoke all on function public.pf_importer(uuid, text, text, jsonb, boolean) from public, anon;
grant execute on function public.pf_importer(uuid, text, text, jsonb, boolean) to authenticated;

-- Annulation d'un lot : seulement si rien n'a été reçu pour ce client depuis (ni nouvelle fiche, ni modification d'une
-- fiche importée) ; sinon : correction fiche par fiche.
create or replace function public.pf_annuler_lot(p_entreprise uuid, p_lot text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l pf_lots_import; n integer;
begin
  perform public.exiger_admin();
  select * into l from pf_lots_import where id = p_lot and entreprise_id = p_entreprise;
  if l.id is null then raise exception 'Lot inconnu pour cette entreprise'; end if;
  if l.annule_le is not null then raise exception 'Lot déjà annulé'; end if;
  if exists (select 1 from fiches x where x.entreprise_id = p_entreprise and x.seq > coalesce(l.seq_fin, 0) and x.type <> 'parametres') then
    raise exception 'Le client (ou un lot plus récent) a enregistré des données depuis cet import : annulation impossible, corrigez fiche par fiche';
  end if;
  delete from fiches where entreprise_id = p_entreprise and data->>'lotImport' = p_lot;
  get diagnostics n = row_count;
  update pf_lots_import set annule_le = now() where id = p_lot;
  return jsonb_build_object('supprimees', n);
end $$;
revoke all on function public.pf_annuler_lot(uuid, text) from public, anon;
grant execute on function public.pf_annuler_lot(uuid, text) to authenticated;

create or replace function public.pf_mes_lire(p_entreprise uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return jsonb_build_object(
    'etapes', coalesce((select etapes from pf_mise_en_service where entreprise_id = p_entreprise), '{}'::jsonb),
    'lots', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'creeLe', cree_le, 'fichier', fichier, 'resume', resume, 'annuleLe', annule_le) order by cree_le desc), '[]'::jsonb)
             from pf_lots_import where entreprise_id = p_entreprise));
end $$;
revoke all on function public.pf_mes_lire(uuid) from public, anon;
grant execute on function public.pf_mes_lire(uuid) to authenticated;

create or replace function public.pf_mes_etape(p_entreprise uuid, p_cle text, p_fait boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e jsonb;
begin
  perform public.exiger_admin();
  if p_cle not in ('kit_envoye', 'kit_recu', 'import', 'responsable_invite', 'qr_imprimes', 'equipe_invitee', 'mise_en_service') then raise exception 'Étape inconnue'; end if;
  if not exists (select 1 from entreprises where id = p_entreprise) then raise exception 'Entreprise inconnue'; end if;
  insert into pf_mise_en_service (entreprise_id) values (p_entreprise) on conflict (entreprise_id) do nothing;
  update pf_mise_en_service
     set etapes = case when p_fait then etapes || jsonb_build_object(p_cle, now()) else etapes - p_cle end, maj_le = now()
   where entreprise_id = p_entreprise
  returning etapes into e;
  return e;
end $$;
revoke all on function public.pf_mes_etape(uuid, text, boolean) from public, anon;
grant execute on function public.pf_mes_etape(uuid, text, boolean) to authenticated;
