-- ===== 21_stabilite_s2.sql — copie générée de supabase/stabilite_s2.sql (empreinte f7e65e549314f13d) : ne pas modifier ici =====
-- GMAO terrain — lot S2 de stabilisation (docs/AUDIT_STABILITE_MODELE.md §4 E, F, G, K). APRÈS magasin_r5.sql,
-- AVANT push_fiches.sql. Rejouable. FICHIER GÉNÉRÉ par scripts/generer_stabilite_s2.py : ne pas modifier à la main.
-- E : pf_importer renumérote ses fiches avant de valider (curseur des téléphones sûr pendant un import).
-- F : code appareil unique dans l'entreprise (références lisibles OT-K3-0007 sans doublon) : appareil_code.
-- G : contrôle léger du contenu (statuts, natures, priorités, types, quantités, dates) : s2_controle.
-- K : liens vérifiés à la création (intervention, article, besoin, équipe, société) : s2_lien.
-- Rapport des fiches anormales pour la console : pf_fiches_anormales.

-- ---------- F : code appareil ----------
create table if not exists public.pf_appareils (
  entreprise_id uuid not null references public.entreprises(id) on delete cascade,
  code text not null, appareil text not null, user_id uuid, cree_le timestamptz not null default now(),
  primary key (entreprise_id, code));
alter table public.pf_appareils enable row level security;
revoke all on public.pf_appareils from public, anon, authenticated;

/** Code de l'appareil, unique dans l'entreprise : le sien s'il est libre (ou déjà à lui), sinon un nouveau.
    Un code n'est jamais redonné à un autre appareil (même après « Effacer cet appareil »). */
create or replace function public.appareil_code(p_code text, p_appareil text)
returns text language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); c text; a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i integer;
begin
  if ent is null then raise exception 'Compte sans entreprise' using errcode = '42501'; end if;
  if coalesce(p_appareil, '') = '' or length(p_appareil) > 64 then raise exception 'Appareil inconnu'; end if;
  select code into c from pf_appareils where entreprise_id = ent and appareil = p_appareil order by cree_le limit 1;
  if c is not null then return c; end if;   -- appareil déjà inscrit : il garde son code
  perform public.limiter('appareil:' || ent::text, 60, interval '1 hour', 'Trop de nouveaux appareils en une heure : réessayez plus tard');
  if p_code ~ '^[A-Z0-9]{2,4}$' and not exists (select 1 from pf_appareils where entreprise_id = ent and code = p_code) then
    insert into pf_appareils (entreprise_id, code, appareil, user_id) values (ent, p_code, p_appareil, auth.uid());
    return p_code;
  end if;
  for i in 1 .. 200 loop
    c := substr(a, 1 + floor(random() * 32)::int, 1) || substr(a, 1 + floor(random() * 32)::int, 1)
         || case when i > 100 then substr(a, 1 + floor(random() * 32)::int, 1) else '' end;
    if not exists (select 1 from pf_appareils where entreprise_id = ent and code = c) then
      insert into pf_appareils (entreprise_id, code, appareil, user_id) values (ent, c, p_appareil, auth.uid());
      return c;
    end if;
  end loop;
  raise exception 'Aucun code appareil libre';
end $$;
revoke all on function public.appareil_code(text, text) from public, anon;
grant execute on function public.appareil_code(text, text) to authenticated;

-- ---------- G : contrôle léger du contenu ----------
/** Motif si une valeur du patch n'est pas reconnue (null = accepté). Seuls les champs présents sont contrôlés ;
    une valeur vide (null) est toujours acceptée. */
create or replace function public.s2_controle(t text, p jsonb)
returns text language plpgsql immutable set search_path = public as $$
declare k text; v jsonb; permis text[];
begin
  for k, v in select key, value from jsonb_each(p) loop
    continue when v is null or jsonb_typeof(v) = 'null';
    permis := case
      when t = 'ots' and k = 'statut' then array['a_preparer','a_planifier','planifiee','prete','en_cours','suspendue','travail_termine','cloturee','annulee']
      when t = 'ots' and k in ('nature', 'natureProposee') then array['a_qualifier','corrective','preventive','assistance_production','travaux_techniques']
      when t = 'ots' and k in ('priorite', 'prioriteProposee') then array['urgence_securite','critique_service','rapide','planifiable','a_qualifier']
      when t = 'ots' and k = 'avecArret' then array['oui','non','inconnu']
      when t = 'ots' and k = 'arretType' then array['planifie','non_planifie']
      when t = 'demandes' and k = 'statut' then array['a_examiner','prise_en_charge','traitement_organise','close_sans_travail','annulee']
      when t = 'besoins' and k = 'statut' then array['demande','reserve','indisponible','annule','partiellement_remis','remis']
      when t = 'mouvements' and k = 'type' then array['entree','sortie','remise','retour','rebut','ajustement','isolement','liberation','disposition']
      when t = 'achats' and k = 'statut' then array['brouillon','soumise','a_completer','validee','refusee','transmise','commandee','partiellement_recue','recue','close','annulee']
      else null end;
    if permis is not null and (jsonb_typeof(v) <> 'string' or not (v #>> '{}') = any (permis)) then
      return 'valeur non reconnue pour « ' || k || ' » : ' || left(v::text, 40) || ' (mettez l''appli à jour)';
    end if;
    if ((t in ('besoins', 'mouvements') and k in ('qte', 'qteReservee', 'quantite')) or (t = 'releves' and k = 'valeur'))
       and jsonb_typeof(v) <> 'number' then
      return 'quantité non numérique pour « ' || k || ' »';
    end if;
    if k in ('creeLe','modifieLe','le','demandeLe','depuis','fin','arretDebut','arretFin','arretPrevuDebut','arretPrevuFin','creneau',
             'echeance','clotureLe','dateCommande','livraisonPrevue','valideLe','soumiseLe','redigeLe','delai','reserveLe','contratFin')
       and jsonb_typeof(v) = 'string' and v #>> '{}' <> ''
       and v #>> '{}' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2}([.][0-9]+)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$' then
      return 'date mal formée pour « ' || k || ' » : ' || left(v #>> '{}', 30);
    end if;
  end loop;
  return null;
end $$;
revoke all on function public.s2_controle(text, jsonb) from public, anon, authenticated;

-- ---------- K : liens vérifiés ----------
/** Motif si un lien du patch pointe vers une fiche absente de l'entreprise (null = accepté). À la création pour les
    liens de rattachement ; à chaque écriture pour l'équipe et la société d'une intervention. */
create or replace function public.s2_lien(t text, p jsonb, ent uuid, nouvelle boolean)
returns text language plpgsql stable security definer set search_path = public as $$
declare k text; cible text;
begin
  for k, cible in select x.champ, x.ct from (values
      ('besoins', 'otId', 'ots', true), ('besoins', 'articleId', 'articles', true),
      ('mouvements', 'articleId', 'articles', true), ('mouvements', 'besoinId', 'besoins', true), ('mouvements', 'otId', 'ots', true),
      ('ots', 'equipeId', 'equipes', false), ('ots', 'societeId', 'fournisseurs', false)) x(ty, champ, ct, creation)
    where x.ty = t and (nouvelle or not x.creation) and coalesce(p->>x.champ, '') <> ''
    loop
    if not exists (select 1 from fiches y where y.id = p->>k and y.type = cible and y.entreprise_id = ent) then
      return 'lien vers une fiche inconnue de l''entreprise (' || k || ')';
    end if;
  end loop;
  return null;
end $$;
revoke all on function public.s2_lien(text, jsonb, uuid, boolean) from public, anon, authenticated;

-- ---------- Rapport des fiches anormales (console) ----------
/** Par entreprise : fiches dont le contenu n'est pas reconnu, liens cassés, fiches sans date de création. */
create or replace function public.pf_fiches_anormales()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('code', e.code, 'nom', e.nom, 'fiches', r.n, 'contenu', r.contenu, 'liens', r.liens,
      'sansCreeLe', r.sans_cree, 'exemples', r.exemples) order by e.code)
    from entreprises e cross join lateral (
      select count(*) n,
        count(*) filter (where x.type <> 'journal' and public.s2_controle(x.type, x.data) is not null) contenu,
        count(*) filter (where public.s2_lien(x.type, x.data, e.id, true) is not null) liens,
        count(*) filter (where x.type not in ('journal', 'mouvements', 'photos') and coalesce(x.data->>'creeLe', '') = '') sans_cree,
        (select jsonb_agg(z) from (select jsonb_build_object('id', y.id, 'type', y.type,
            'motif', coalesce(public.s2_controle(y.type, y.data), public.s2_lien(y.type, y.data, e.id, true))) z
          from fiches y where y.entreprise_id = e.id and y.type <> 'journal'
            and (public.s2_controle(y.type, y.data) is not null or public.s2_lien(y.type, y.data, e.id, true) is not null) limit 5) w) exemples
      from fiches x where x.entreprise_id = e.id) r), '[]'::jsonb);
end $$;
revoke all on function public.pf_fiches_anormales() from public, anon;
grant execute on function public.pf_fiches_anormales() to authenticated;

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
    -- S2 (risque E) : une longue transaction prend ses numéros au début ; les téléphones qui lisent pendant l'import
    -- avancent leur curseur au-delà et ne reçoivent jamais une partie des fiches. Renumérotées à la fin, elles passent
    -- après tout ce qui a été lu entre-temps (essai du 7 nov. : 101 fiches sur 300 perdues sans ce correctif, 0 avec).
    update fiches set seq = nextval('public.fiches_seq') where entreprise_id = p_entreprise and data->>'lotImport' = p_lot;
    insert into pf_lots_import (id, entreprise_id, par, fichier, resume, seq_fin)
    values (p_lot, p_entreprise, auth.uid(), left(p_fichier, 200), resume,
            (select max(seq) from fiches where entreprise_id = p_entreprise and data->>'lotImport' = p_lot));
  end if;
  return jsonb_build_object('essai', p_essai, 'acceptes', n, 'refus', refus, 'resume', resume,
    'importe', not p_essai and jsonb_array_length(refus) = 0);
end $$;

revoke all on function public.pf_importer(uuid, text, text, jsonb, boolean) from public, anon;
grant execute on function public.pf_importer(uuid, text, text, jsonb, boolean) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
