-- ===== 11_centre_controle.sql — copie générée de supabase/centre_controle.sql (empreinte d914ec7cc7249993) : ne pas modifier ici =====
-- GMAO terrain — centre de contrôle, étape CC1 : fiches clients, conditions d'abonnement, grille tarifaire (rejouable).
-- APRÈS mise_en_service.sql. Voir docs/CENTRE_CONTROLE_CONCEPTION.md.
-- Données de plateforme : jamais visibles des clients (règles d'accès actives, aucune politique de lecture) ;
-- lecture et écriture uniquement par les fonctions pf_* réservées à l'administrateur plateforme.

-- ---------- conditions commerciales de l'abonnement ----------
alter table public.abonnements add column if not exists prix numeric(12, 2);           -- HT, MAD, par période
alter table public.abonnements add column if not exists periodicite text not null default 'mensuel';
alter table public.abonnements add column if not exists remise_pct numeric(5, 2) not null default 0;
alter table public.abonnements add column if not exists conditions text;               -- notes contractuelles
alter table public.abonnements drop constraint if exists abonnements_periodicite_check;
alter table public.abonnements add constraint abonnements_periodicite_check check (periodicite in ('mensuel', 'annuel'));
alter table public.abonnements drop constraint if exists abonnements_remise_check;
alter table public.abonnements add constraint abonnements_remise_check check (remise_pct >= 0 and remise_pct <= 100);
alter table public.abonnements drop constraint if exists abonnements_prix_check;
alter table public.abonnements add constraint abonnements_prix_check check (prix is null or prix >= 0);

-- ---------- grille tarifaire (prix publics HT par pack) ----------
create table if not exists public.pf_tarifs (
  pack         text primary key references public.packs(code),
  prix_mensuel numeric(12, 2) check (prix_mensuel is null or prix_mensuel >= 0),
  prix_annuel  numeric(12, 2) check (prix_annuel is null or prix_annuel >= 0),
  note         text,
  maj_le       timestamptz not null default now()
);
alter table public.pf_tarifs enable row level security;
insert into public.pf_tarifs (pack) select code from public.packs on conflict (pack) do nothing;

-- ---------- objets de plateforme (fiche client ; prospects, support, échanges… en CC2) ----------
create table if not exists public.pf_objets (
  id            text primary key,
  type          text not null,
  entreprise_id uuid references public.entreprises(id),
  data          jsonb not null default '{}'::jsonb,
  cree_le       timestamptz not null default now(),
  maj_le        timestamptz not null default now(),
  par           uuid
);
alter table public.pf_objets enable row level security;
create index if not exists pf_objets_type on public.pf_objets (type, entreprise_id);

-- ---------- lecture : tous les clients avec usage, abonnement et fiche ----------
create or replace function public.pf_clients()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(x order by x->>'nom') from (
    select jsonb_build_object(
      'id', e.id, 'code', e.code, 'nom', e.nom, 'statut', e.statut, 'demo', e.demo, 'creeLe', e.cree_le,
      'abonnement', public.droits_entreprise(e.id) || jsonb_build_object('debut', a.debut, 'prix', a.prix, 'periodicite', a.periodicite,
        'remisePct', a.remise_pct, 'conditions', a.conditions, 'statutAbonnement', a.statut,
        'derogations', jsonb_build_object('maxSites', a.max_sites, 'maxUtilisateursSite', a.max_utilisateurs_site, 'maxUtilisateursTotal', a.max_utilisateurs_total)),
      'actifs', public.nb_actifs_entreprise(e.id, null),
      'sites', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'nom', s.nom, 'actif', s.actif) order by s.nom), '[]'::jsonb) from sites s where s.entreprise_id = e.id),
      'responsables', (select coalesce(jsonb_agg(p.email order by p.email), '[]'::jsonb) from profils p where p.entreprise_id = e.id and p.role = 'responsable' and p.actif),
      'fiches', (select count(*) from fiches f where f.entreprise_id = e.id),
      'activite7j', (select count(*) from fiches f where f.entreprise_id = e.id and f.recu_le > now() - interval '7 days' and f.data->>'lotImport' is null),
      'derniereActivite', (select max(f.recu_le) from fiches f where f.entreprise_id = e.id and f.data->>'lotImport' is null),
      'miseEnService', (select etapes from pf_mise_en_service m where m.entreprise_id = e.id),
      'fiche', (select o.data from pf_objets o where o.id = 'client-' || e.id::text)) x
    from entreprises e left join abonnements a on a.entreprise_id = e.id) q), '[]'::jsonb);
end $$;
revoke all on function public.pf_clients() from public, anon;
grant execute on function public.pf_clients() to authenticated;

-- ---------- fiche client : identité et contacts (raison sociale, ICE, adresse, contacts, secteur, notes) ----------
create or replace function public.pf_client_maj(p_entreprise uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  perform public.exiger_admin();
  if not exists (select 1 from entreprises where id = p_entreprise) then raise exception 'Entreprise inconnue'; end if;
  if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Fiche invalide'; end if;
  if coalesce(p_data->>'ice', '') <> '' and p_data->>'ice' !~ '^[0-9]{15}$' then raise exception 'ICE : 15 chiffres'; end if;
  if p_data ? 'contacts' and jsonb_typeof(p_data->'contacts') is distinct from 'array' then raise exception 'Contacts : liste attendue'; end if;
  insert into pf_objets (id, type, entreprise_id, data, par) values ('client-' || p_entreprise::text, 'fiche_client', p_entreprise, p_data, auth.uid())
  on conflict (id) do update set data = excluded.data, maj_le = now(), par = auth.uid()
  returning data into d;
  return d;
end $$;
revoke all on function public.pf_client_maj(uuid, jsonb) from public, anon;
grant execute on function public.pf_client_maj(uuid, jsonb) to authenticated;

-- ---------- conditions d'abonnement (prix convenu, périodicité, remise, début, notes) ----------
create or replace function public.pf_abonnement_conditions(p_entreprise uuid, p_prix numeric, p_periodicite text, p_remise numeric, p_debut date, p_conditions text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  if p_periodicite not in ('mensuel', 'annuel') then raise exception 'Périodicité : mensuel ou annuel'; end if;
  if p_prix is not null and p_prix < 0 then raise exception 'Prix négatif'; end if;
  if coalesce(p_remise, 0) < 0 or coalesce(p_remise, 0) > 100 then raise exception 'Remise entre 0 et 100 %%'; end if;
  update abonnements set prix = p_prix, periodicite = p_periodicite, remise_pct = coalesce(p_remise, 0),
    debut = coalesce(p_debut, debut), conditions = nullif(trim(coalesce(p_conditions, '')), '')
  where entreprise_id = p_entreprise;
  if not found then raise exception 'Entreprise sans abonnement'; end if;
end $$;
revoke all on function public.pf_abonnement_conditions(uuid, numeric, text, numeric, date, text) from public, anon;
grant execute on function public.pf_abonnement_conditions(uuid, numeric, text, numeric, date, text) to authenticated;

-- ---------- grille tarifaire ----------
create or replace function public.pf_tarifs_lire()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return (select coalesce(jsonb_agg(jsonb_build_object('pack', p.code, 'packNom', p.nom, 'modules', p.modules, 'maxSites', p.max_sites,
    'maxUtilisateursSite', p.max_utilisateurs_site, 'maxUtilisateursTotal', p.max_utilisateurs_total,
    'prixMensuel', t.prix_mensuel, 'prixAnnuel', t.prix_annuel, 'note', t.note) order by coalesce(p.max_utilisateurs_total, 1000000)), '[]'::jsonb)
    from packs p left join pf_tarifs t on t.pack = p.code);
end $$;
revoke all on function public.pf_tarifs_lire() from public, anon;
grant execute on function public.pf_tarifs_lire() to authenticated;

create or replace function public.pf_tarif_maj(p_pack text, p_prix_mensuel numeric, p_prix_annuel numeric, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  if not exists (select 1 from packs where code = p_pack) then raise exception 'Pack inconnu'; end if;
  if coalesce(p_prix_mensuel, 0) < 0 or coalesce(p_prix_annuel, 0) < 0 then raise exception 'Prix négatif'; end if;
  insert into pf_tarifs (pack, prix_mensuel, prix_annuel, note) values (p_pack, p_prix_mensuel, p_prix_annuel, nullif(trim(coalesce(p_note, '')), ''))
  on conflict (pack) do update set prix_mensuel = excluded.prix_mensuel, prix_annuel = excluded.prix_annuel, note = excluded.note, maj_le = now();
end $$;
revoke all on function public.pf_tarif_maj(text, numeric, numeric, text) from public, anon;
grant execute on function public.pf_tarif_maj(text, numeric, numeric, text) to authenticated;
