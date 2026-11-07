-- GMAO terrain — lot R2 « fiche intervention en étapes » (docs/MAQUETTES_R2.md §2, §3, §7). APRÈS roles_r1.sql. Rejouable.
-- FICHIER GÉNÉRÉ par scripts/generer_interventions_r2.py : ne pas modifier à la main.
-- Q6 : le terrain (technicien, prestataire) propose la nature et la priorité ; le responsable valide.
--   Toute nature / priorité écrite par le terrain est rangée en « proposée » (natureProposee, prioriteProposee,
--   qualificationValidee = false) — y compris par une ancienne version de l'appli ; exception : préventif lancé
--   depuis un programme (nature fixée par le programme). Le terrain ne peut ni valider, ni proposer sur une
--   qualification déjà validée par le responsable.
-- Q9 : terminer ou clôturer une intervention avec arrêt non planifié exige la remise à disposition ou « heures
--   inconnues ». Contrôle serveur sur les arrêts saisis depuis R2 (champ arretType présent) ; l'appli contrôle aussi
--   les plus anciens (type déduit de la nature). Les temps des intervenants ne sont jamais demandés.

create or replace function public.r2_qualif_terrain(p jsonb, d jsonb, nouvelle boolean)
returns jsonb language plpgsql immutable set search_path = public as $$
declare q jsonb := p;
begin
  if nouvelle and coalesce(p->>'programmeId', '') <> '' then return p; end if;   -- préventif d'un programme
  if p ? 'nature' and p->>'nature' is distinct from coalesce(d->>'nature', 'a_qualifier') then
    q := (q - 'nature') || jsonb_build_object('natureProposee', p->'nature', 'qualificationValidee', false);
    if nouvelle then q := q || '{"nature":"a_qualifier"}'::jsonb; end if;
  end if;
  if p ? 'priorite' and p->>'priorite' is distinct from coalesce(d->>'priorite', 'a_qualifier') then
    q := (q - 'priorite') || jsonb_build_object('prioriteProposee', p->'priorite', 'qualificationValidee', false);
    if nouvelle then q := q || '{"priorite":"a_qualifier"}'::jsonb; end if;
  end if;
  return q;
end $$;
revoke all on function public.r2_qualif_terrain(jsonb, jsonb, boolean) from public, anon, authenticated;

create or replace function public.r2_arret_incomplet(d jsonb)
returns boolean language sql immutable set search_path = public as $$
  select d->>'avecArret' = 'oui' and d ? 'arretType'
     and coalesce(d->>'arretType',
           case when (case when d->'qualificationValidee' = 'false'::jsonb then coalesce(d->>'natureProposee', d->>'nature') else d->>'nature' end)
                     in ('preventive', 'travaux_techniques') then 'planifie' else 'non_planifie' end) = 'non_planifie'
     and coalesce(d->>'arretFin', '') = ''
     and d->'arretHeuresInconnues' is distinct from 'true'::jsonb
$$;
revoke all on function public.r2_arret_incomplet(jsonb) from public, anon, authenticated;

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
    -- R2 : nature et priorité écrites par le terrain = proposition (le responsable valide).
    if t = 'ots' and terrain then p := public.r2_qualif_terrain(p, ex.data, ex.id is null); end if;
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
    elsif t = 'ots' and terrain and (p->'qualificationValidee' = 'true'::jsonb or p ? 'qualifieePar' or p ? 'qualifieeLe') then
      motif := 'validation de la qualification : réservée au responsable';
    elsif t = 'ots' and terrain and ex.data->'qualificationValidee' = 'true'::jsonb
          and (p ? 'natureProposee' or p ? 'prioriteProposee' or p ? 'qualificationValidee') then
      motif := 'qualification déjà validée par le responsable : demandez-lui de la changer';
    elsif t = 'ots' and p->>'statut' in ('cloturee', 'travail_termine') and coalesce(ex.data->>'statut', '') <> p->>'statut'
          and public.r2_arret_incomplet(coalesce(ex.data, '{}'::jsonb) || p) then
      motif := 'arrêt non planifié : indiquer la remise à disposition ou « heures inconnues »';
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

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
