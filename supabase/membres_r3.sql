-- GMAO terrain — lot R3 « membres, équipes, sociétés prestataires » (docs/MAQUETTES_R3.md §1 à §9). APRÈS interventions_r2.sql.
-- Rejouable. FICHIER GÉNÉRÉ par scripts/generer_membres_r3.py : ne pas modifier à la main.
-- Membre = fiche « personnes » (avec ou sans compte) ; le compte (profils.personne_id) y est relié. Nom et rôle d'un membre
--   avec accès : une seule valeur (definir_profil écrit les deux ; le nom changé sur la fiche passe au compte) ; le rôle
--   et la désactivation d'un membre avec accès ne passent pas par la fiche. Retirer l'accès ne rend pas le membre inactif.
-- relier_membre : relie un compte (juste invité) à une fiche membre existante (pas de doublon).
-- Membres, équipes (nouveau type « equipes ») et sociétés prestataires (fiche « fournisseurs » avec prestataire = true,
--   module de base) : écrits par le responsable et l'administrateur ; chacun peut changer son nom et son téléphone.
-- Interventions : equipeId / societeId posés par le responsable (refusés au terrain).
-- Prestataire (Q3 élargi) : voit ses interventions ET celles confiées à sa société (societeId de sa fiche membre), la
--   fiche de sa société et les équipes.
-- Reprise : fiches des comptes alignées (nom, rôle) ; texte libre « societe » → société prestataire + societeId.

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs','equipes'));

/** Société de l'appelant (fiche « fournisseurs » prestataire), lue sur sa fiche membre. */
create or replace function public.ma_societe()
returns text language sql stable security definer set search_path = public as $$
  select nullif(f.data->>'societeId', '') from fiches f
  where f.id = public.ma_personne() and f.type = 'personnes' and f.entreprise_id = public.mon_entreprise()
$$;
revoke all on function public.ma_societe() from public, anon, authenticated;

/** Intervention confiée à l'appelant : il en est intervenant, ou elle est confiée à sa société. */
create or replace function public.ot_a_moi(oid text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(oid, '') <> '' and exists (
    select 1 from fiches o where o.id = oid and o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and (o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne()))
           or (public.ma_societe() is not null and o.data->>'societeId' = public.ma_societe())))
$$;
revoke all on function public.ot_a_moi(text) from public, anon, authenticated;

create or replace function public.prestataire_voit(t text, fid text, d jsonb, aut uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare x record;
begin
  if t in ('equipements', 'localisations', 'personnes', 'articles', 'compteurs', 'releves', 'parametres', 'journal', 'equipes') then return true; end if;
  if t = 'fournisseurs' then return fid = public.ma_societe(); end if;   -- R3 : sa société seulement
  if t = 'ots' then return public.ot_a_moi(fid); end if;
  if t = 'demandes' then
    return aut = auth.uid() or exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and o.data->'demandeIds' ? fid and public.ot_a_moi(o.id));
  end if;
  if t in ('besoins', 'mouvements') then return public.ot_a_moi(d->>'otId'); end if;
  if t = 'programmes' then
    return exists (select 1 from fiches o where o.type = 'ots' and o.entreprise_id = public.mon_entreprise() and o.data->>'programmeId' = fid
      and public.ot_a_moi(o.id));
  end if;
  if t = 'photos' then
    select type, id, data, auteur into x from fiches where id = d->>'parentId' and entreprise_id = public.mon_entreprise();
    return found and x.type <> 'photos' and public.prestataire_voit(x.type, x.id, x.data, x.auteur);
  end if;
  return false;   -- magasin, achats, prix, seuils, factures, fournisseurs…
end $$;

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
      and o.data->'demandeIds' ? x.id and public.ot_a_moi(o.id));
  end if;
  return false;
end $$;

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
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'nom', p.nom),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = p.personne_id;
end $$;

revoke all on function public.prestataire_voit(text, text, jsonb, uuid) from public, anon;
grant execute on function public.prestataire_voit(text, text, jsonb, uuid) to authenticated;   -- appelée par la règle de lecture
revoke all on function public.journal_visible(jsonb, uuid) from public, anon;
grant execute on function public.journal_visible(jsonb, uuid) to authenticated;
revoke all on function public.definir_profil(uuid, text, text, boolean) from public, anon;
grant execute on function public.definir_profil(uuid, text, text, boolean) to authenticated;

/** Relier un compte de l'entreprise à une fiche membre existante (après « Donner un accès »). La fiche prend le rôle
    du compte ; le compte prend le nom de la fiche ; l'ancienne fiche du compte, s'il en avait une autre, devient inactive. */
create or replace function public.relier_membre(cible uuid, personne text)
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); ancien text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = ent) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if not exists (select 1 from fiches where id = personne and type = 'personnes' and entreprise_id = ent) then
    raise exception 'Membre inconnu de l''entreprise';
  end if;
  if exists (select 1 from profils where personne_id = personne and user_id <> cible) then
    raise exception 'Ce membre a déjà un autre accès';
  end if;
  select personne_id into ancien from profils where user_id = cible;
  update profils set personne_id = personne,
    nom = coalesce(nullif(trim((select data->>'nom' from fiches where id = personne)), ''), nom) where user_id = cible;
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'email', p.email, 'actif', true,
      'modifieLe', maintenant, 'modifiePar', 'serveur'), seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = personne;
  if ancien is not null and ancien <> personne then
    update fiches set data = data || jsonb_build_object('actif', false, 'remplaceePar', personne, 'modifieLe', maintenant, 'modifiePar', 'serveur'),
      seq = nextval('public.fiches_seq'), recu_le = now()
    where id = ancien and type = 'personnes' and entreprise_id = ent;
  end if;
end $$;
revoke all on function public.relier_membre(uuid, text) from public, anon;
grant execute on function public.relier_membre(uuid, text) to authenticated;

-- ---------- Reprise de l'existant (rejouable : ne refait rien la deuxième fois) ----------
create or replace function public.r3_reprise()
returns void language plpgsql security definer set search_path = public as $$
declare x record; sid text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  -- 1) fiche d'un compte : même nom et même rôle que le compte
  update fiches f set data = f.data || jsonb_build_object('nom', coalesce(nullif(trim(p.nom), ''), f.data->>'nom'), 'role', p.role),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.personne_id = f.id and f.type = 'personnes' and f.entreprise_id = p.entreprise_id
    and (f.data->>'role' is distinct from p.role or (coalesce(trim(p.nom), '') <> '' and f.data->>'nom' is distinct from trim(p.nom)));
  -- 2) texte libre « societe » → société prestataire (même nom sans casse ni accents) + societeId
  for x in select f.id, f.entreprise_id, trim(f.data->>'societe') as nom from fiches f
           where f.type = 'personnes' and coalesce(trim(f.data->>'societe'), '') <> '' and coalesce(f.data->>'societeId', '') = '' loop
    select s.id into sid from fiches s where s.type = 'fournisseurs' and s.entreprise_id = x.entreprise_id
      and lower(translate(trim(s.data->>'nom'), 'ÀÂÄÉÈÊËÎÏÔÖÙÛÜÇàâäéèêëîïôöùûüç', 'AAAEEEEIIOOUUUCaaaeeeeiioouuuc'))
        = lower(translate(x.nom, 'ÀÂÄÉÈÊËÎÏÔÖÙÛÜÇàâäéèêëîïôöùûüç', 'AAAEEEEIIOOUUUCaaaeeeeiioouuuc')) limit 1;
    if sid is null then
      sid := 'soc-' || substr(md5(x.entreprise_id::text || lower(x.nom)), 1, 16);
      insert into fiches (id, type, data, entreprise_id) values (sid, 'fournisseurs', jsonb_build_object('id', sid, 'nom', x.nom,
        'prestataire', true, 'actif', true, 'creeLe', maintenant, 'creePar', 'serveur', 'modifieLe', maintenant, 'modifiePar', 'serveur'), x.entreprise_id)
      on conflict (id) do nothing;
    else
      update fiches set data = data || '{"prestataire":true}'::jsonb, seq = nextval('public.fiches_seq'), recu_le = now()
      where id = sid and data->>'prestataire' is distinct from 'true';
    end if;
    update fiches set data = data || jsonb_build_object('societeId', sid), seq = nextval('public.fiches_seq'), recu_le = now() where id = x.id;
    sid := null;
  end loop;
end $$;
revoke all on function public.r3_reprise() from public, anon, authenticated;
select public.r3_reprise();

create or replace function public.push_fiches(lot jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  f jsonb; p jsonb; t text; cible text; motif text;
  r text := public.mon_role();
  ent uuid := public.mon_entreprise();
  droits jsonb; mes uuid[]; defaut uuid;
  ex record; s uuid; data_site jsonb; terrain boolean; mod text; u text; gere boolean; soi boolean; lie boolean;
  n integer := 0; refus jsonb := '[]'::jsonb; refuses text[] := '{}';
begin
  if r is null or ent is null then
    raise exception 'Compte sans droits (profil absent, désactivé ou sans entreprise)' using errcode = '42501';
  end if;
  terrain := r in ('technicien', 'prestataire');
  gere := r = 'responsable' or public.est_admin_client();   -- R3 : membres, équipes, sociétés prestataires
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
    -- R3 : une société prestataire relève du module de base (pas du magasin).
    if cible = 'fournisseurs' and (t = 'journal' or coalesce(p->>'prestataire', ex.data->>'prestataire', '') = 'true') then mod := 'base'; end if;
    -- R3 : sa propre fiche membre (nom, téléphone) ; fiche reliée à un compte (rôle par l'administrateur).
    soi := cible = 'personnes' and coalesce(case when t = 'journal' then p->>'entiteId' else f->>'id' end, '') = coalesce(public.ma_personne(), '-')
           and (t = 'journal' or (ex.id is not null and not exists (
             select 1 from jsonb_object_keys(p) k where k not in ('nom', 'telephone', 'modifieLe', 'modifiePar'))));
    lie := t = 'personnes' and exists (select 1 from profils x where x.personne_id = f->>'id' and x.entreprise_id = ent);
    -- Renvoi identique d'un mouvement ou d'un relevé déjà reçu (réponse perdue, envoi complet) : accepté sans rien changer.
    if t in ('mouvements', 'releves') and ex.id is not null and ex.entreprise_id = ent and ex.data @> p then
      n := n + 1; continue;
    end if;

    if t not in ('localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs','equipes') then
      motif := 'type inconnu';
    elsif droits is null or not coalesce((droits->>'ecriture')::boolean, false) then
      motif := 'abonnement suspendu ou expiré : lecture seule';
    elsif ex.id is not null and ex.entreprise_id is distinct from ent then
      motif := 'fiche d''une autre entreprise';
    elsif t = 'journal' and (p->>'entiteId') = any (refuses) then
      motif := 'modification liée refusée';
    elsif not ((droits->'modules') ? mod) then
      motif := 'module « ' || mod || ' » non inclus dans l''abonnement';
    elsif cible in ('personnes', 'equipes') and not gere and not soi then
      motif := 'membres et équipes : réservés au responsable et à l''administrateur';
    elsif cible not in ('personnes', 'equipes') and not (cible = 'fournisseurs' and gere) and not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'fournisseurs' and not gere and (p->>'prestataire' = 'true' or ex.data->>'prestataire' = 'true') then
      motif := 'société prestataire : réservée au responsable et à l''administrateur';
    elsif lie and ex.id is not null and ((p ? 'role' and p->'role' is distinct from ex.data->'role')
          or (p ? 'actif' and p->'actif' is distinct from ex.data->'actif' and p->'actif' = 'false'::jsonb)) then
      motif := 'membre avec un accès : rôle et accès se changent par l''administrateur (Membres)';
    elsif t = 'ots' and terrain and ((p ? 'equipeId' and p->'equipeId' is distinct from coalesce(ex.data->'equipeId', 'null'::jsonb) and coalesce(p->>'equipeId', '') <> '')
          or (p ? 'societeId' and p->'societeId' is distinct from coalesce(ex.data->'societeId', 'null'::jsonb) and coalesce(p->>'societeId', '') <> '')) then
      motif := 'intervention confiée à une équipe ou une société : réservé au responsable';
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

    if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs', 'equipes') then
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
    -- R3 : le nom d'un membre avec accès est aussi celui de son compte.
    if t = 'personnes' and lie and coalesce(trim(p->>'nom'), '') <> '' then
      update profils set nom = trim(p->>'nom') where personne_id = f->>'id' and entreprise_id = ent;
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
