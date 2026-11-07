-- GMAO terrain — centre de contrôle, étape CC2 : prospects, support, échanges, modèles de messages, annonces (rejouable).
-- APRÈS centre_controle.sql. Voir docs/CENTRE_CONTROLE_CONCEPTION.md.
--   pf_objets (table de CC1) porte les types : prospect, ticket (demande de support), echange (journal), modele (message).
--   pf_annonces : bandeau affiché dans l'appli (tous les clients ou un seul), lu par les utilisateurs via mes_annonces().
--   support_creer : un utilisateur connecté (responsable…) envoie une demande au support depuis l'appli.

create sequence if not exists public.pf_tickets_seq;

-- ---------- lecture / écriture des objets (administrateur) ----------
create or replace function public.pf_objets_lire(p_type text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  if p_type not in ('prospect', 'ticket', 'echange', 'modele') then raise exception 'Type inconnu'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'type', o.type, 'entrepriseId', o.entreprise_id, 'creeLe', o.cree_le, 'majLe', o.maj_le)
                    || o.data order by o.cree_le desc) from pf_objets o where o.type = p_type), '[]'::jsonb);
end $$;
revoke all on function public.pf_objets_lire(text) from public, anon;
grant execute on function public.pf_objets_lire(text) to authenticated;

create or replace function public.pf_objet_enregistrer(p_id text, p_type text, p_entreprise uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); ex pf_objets; id_ text := nullif(trim(coalesce(p_id, '')), '');
begin
  perform public.exiger_admin();
  if p_type not in ('prospect', 'ticket', 'echange', 'modele') then raise exception 'Type inconnu'; end if;
  if jsonb_typeof(d) is distinct from 'object' then raise exception 'Données invalides'; end if;
  if p_entreprise is not null and not exists (select 1 from entreprises where id = p_entreprise) then raise exception 'Entreprise inconnue'; end if;
  d := d - 'id' - 'type' - 'entrepriseId' - 'creeLe' - 'majLe';
  if id_ is not null then
    select * into ex from pf_objets where id = id_;
    if ex.id is not null and ex.type <> p_type then raise exception 'Identifiant déjà utilisé par un autre type'; end if;
  end if;
  -- règles par type
  if p_type = 'prospect' then
    if coalesce(trim(d->>'nom'), '') = '' and coalesce(trim(d->>'societe'), '') = '' then raise exception 'Prospect : nom ou société obligatoire'; end if;
    if coalesce(d->>'etape', 'nouveau') not in ('nouveau', 'contacte', 'demo_prevue', 'demo_faite', 'essai', 'gagne', 'perdu') then raise exception 'Étape inconnue'; end if;
    if d->>'etape' = 'perdu' and coalesce(trim(d->>'motifPerte'), '') = '' then raise exception 'Prospect perdu : motif obligatoire'; end if;
  elsif p_type = 'ticket' then
    if p_entreprise is null then raise exception 'Demande de support : client obligatoire'; end if;
    if coalesce(trim(d->>'sujet'), '') = '' then raise exception 'Demande de support : sujet obligatoire'; end if;
    if coalesce(d->>'statut', 'ouverte') not in ('ouverte', 'en_cours', 'en_attente_client', 'resolue', 'fermee') then raise exception 'Statut inconnu'; end if;
    if coalesce(d->>'priorite', 'normale') not in ('basse', 'normale', 'haute', 'urgente') then raise exception 'Priorité inconnue'; end if;
    if coalesce(d->>'nature', 'question') not in ('question', 'anomalie', 'evolution', 'facturation') then raise exception 'Nature de la demande inconnue'; end if;
    if ex.id is null then d := d || jsonb_build_object('ref', 'SUP-' || lpad(nextval('pf_tickets_seq')::text, 4, '0')); else d := d || jsonb_build_object('ref', ex.data->>'ref'); end if;
  elsif p_type = 'echange' then
    if coalesce(d->>'canal', '') not in ('whatsapp', 'email', 'telephone', 'rencontre', 'autre') then raise exception 'Canal inconnu'; end if;
    if coalesce(trim(d->>'resume'), '') = '' then raise exception 'Échange : résumé obligatoire'; end if;
    if p_entreprise is null and coalesce(d->>'prospectId', '') = '' then raise exception 'Échange : client ou prospect obligatoire'; end if;
    if ex.id is not null then raise exception 'Un échange noté ne se modifie pas : ajoutez-en un autre'; end if;
  elsif p_type = 'modele' then
    if coalesce(trim(d->>'nom'), '') = '' or coalesce(trim(d->>'texte'), '') = '' then raise exception 'Modèle : nom et texte obligatoires'; end if;
  end if;
  id_ := coalesce(id_, p_type || '-' || replace(gen_random_uuid()::text, '-', ''));
  insert into pf_objets (id, type, entreprise_id, data, par) values (id_, p_type, p_entreprise, d, auth.uid())
  on conflict (id) do update set data = excluded.data, entreprise_id = excluded.entreprise_id, maj_le = now(), par = auth.uid();
  return (select jsonb_build_object('id', o.id, 'type', o.type, 'entrepriseId', o.entreprise_id, 'creeLe', o.cree_le, 'majLe', o.maj_le) || o.data from pf_objets o where o.id = id_);
end $$;
revoke all on function public.pf_objet_enregistrer(text, text, uuid, jsonb) from public, anon;
grant execute on function public.pf_objet_enregistrer(text, text, uuid, jsonb) to authenticated;

-- Suppression : modèles de messages, et prospects (droit d'effacement, loi 09-08) avec leurs échanges.
create or replace function public.pf_objet_supprimer(p_id text)
returns void language plpgsql security definer set search_path = public as $$
declare o pf_objets;
begin
  perform public.exiger_admin();
  select * into o from pf_objets where id = p_id;
  if o.id is null then raise exception 'Introuvable'; end if;
  if o.type not in ('modele', 'prospect') then raise exception 'Seuls un modèle ou un prospect se suppriment (l''historique client est conservé)'; end if;
  if o.type = 'prospect' then delete from pf_objets where type = 'echange' and data->>'prospectId' = p_id; end if;
  delete from pf_objets where id = p_id;
end $$;
revoke all on function public.pf_objet_supprimer(text) from public, anon;
grant execute on function public.pf_objet_supprimer(text) to authenticated;

-- ---------- modèles de messages par défaut (variables : {contact} {entreprise} {fin} {montant} {lien}) ----------
insert into public.pf_objets (id, type, data) values
  ('modele-bienvenue', 'modele', jsonb_build_object('nom', 'Bienvenue', 'cible', 'client', 'texte',
    'Bonjour {contact}, bienvenue sur Perfora ! Votre espace {entreprise} est prêt : {lien}. Je reste disponible pour toute question. Hicham')),
  ('modele-relance-essai', 'modele', jsonb_build_object('nom', 'Relance fin d''essai', 'cible', 'client', 'texte',
    'Bonjour {contact}, votre essai Perfora se termine le {fin}. Comment se passe la prise en main par vos équipes ? Je vous propose un point de 15 minutes pour faire le bilan.')),
  ('modele-echeance', 'modele', jsonb_build_object('nom', 'Rappel d''échéance', 'cible', 'client', 'texte',
    'Bonjour {contact}, l''abonnement Perfora de {entreprise} arrive à échéance le {fin} ({montant}). Merci de prévoir le règlement pour éviter le passage en lecture seule.')),
  ('modele-demo', 'modele', jsonb_build_object('nom', 'Proposition de démo', 'cible', 'prospect', 'texte',
    'Bonjour {contact}, suite à votre intérêt pour Perfora (GMAO terrain, utilisable sans réseau), je vous propose une démonstration de 20 minutes. Quel créneau vous conviendrait ?')),
  ('modele-parrainage', 'modele', jsonb_build_object('nom', 'Parrainage', 'cible', 'client', 'texte',
    'Bonjour {contact}, merci pour votre confiance. Si un confrère directeur pourrait être intéressé par Perfora, n''hésitez pas à lui transmettre mon numéro : un mois vous sera offert à sa souscription.'))
on conflict (id) do nothing;

-- ---------- annonces dans l'appli ----------
create table if not exists public.pf_annonces (
  id            uuid primary key default gen_random_uuid(),
  titre         text not null,
  texte         text not null,
  niveau        text not null default 'info' check (niveau in ('info', 'attention')),
  entreprise_id uuid references public.entreprises(id),     -- null = tous les clients
  debut         timestamptz not null default now(),
  fin           timestamptz,
  actif         boolean not null default true,
  cree_le       timestamptz not null default now()
);
alter table public.pf_annonces enable row level security;

create or replace function public.pf_annonces_lire()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'titre', titre, 'texte', texte, 'niveau', niveau, 'entrepriseId', entreprise_id,
    'debut', debut, 'fin', fin, 'actif', actif, 'creeLe', cree_le) order by cree_le desc) from pf_annonces), '[]'::jsonb);
end $$;
revoke all on function public.pf_annonces_lire() from public, anon;
grant execute on function public.pf_annonces_lire() to authenticated;

create or replace function public.pf_annonce_enregistrer(p_id uuid, p_titre text, p_texte text, p_niveau text, p_entreprise uuid, p_debut timestamptz, p_fin timestamptz, p_actif boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare i uuid;
begin
  perform public.exiger_admin();
  if coalesce(trim(p_titre), '') = '' or coalesce(trim(p_texte), '') = '' then raise exception 'Titre et texte obligatoires'; end if;
  if length(p_texte) > 500 then raise exception 'Texte trop long (500 caractères)'; end if;
  if p_fin is not null and p_fin <= coalesce(p_debut, now()) then raise exception 'La fin doit suivre le début'; end if;
  if p_id is null then
    insert into pf_annonces (titre, texte, niveau, entreprise_id, debut, fin, actif)
    values (trim(p_titre), trim(p_texte), coalesce(p_niveau, 'info'), p_entreprise, coalesce(p_debut, now()), p_fin, coalesce(p_actif, true)) returning id into i;
  else
    update pf_annonces set titre = trim(p_titre), texte = trim(p_texte), niveau = coalesce(p_niveau, 'info'), entreprise_id = p_entreprise,
      debut = coalesce(p_debut, debut), fin = p_fin, actif = coalesce(p_actif, true) where id = p_id returning id into i;
    if i is null then raise exception 'Annonce introuvable'; end if;
  end if;
  return i;
end $$;
revoke all on function public.pf_annonce_enregistrer(uuid, text, text, text, uuid, timestamptz, timestamptz, boolean) from public, anon;
grant execute on function public.pf_annonce_enregistrer(uuid, text, text, text, uuid, timestamptz, timestamptz, boolean) to authenticated;

-- Annonces en cours pour le compte connecté (toutes entreprises, ou la sienne).
create or replace function public.mes_annonces()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'titre', titre, 'texte', texte, 'niveau', niveau) order by debut desc), '[]'::jsonb)
  from pf_annonces
  where actif and debut <= now() and (fin is null or fin > now())
    and (entreprise_id is null or entreprise_id = public.mon_entreprise())
    and public.mon_role() is not null
$$;
revoke all on function public.mes_annonces() from public, anon;
grant execute on function public.mes_annonces() to authenticated;

-- ---------- demande au support depuis l'appli ----------
create or replace function public.support_creer(p_nature text, p_sujet text, p_message text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); p profils; i text := 'ticket-' || replace(gen_random_uuid()::text, '-', ''); ref text;
begin
  if ent is null or public.mon_role() is null then raise exception 'Compte sans entreprise' using errcode = '42501'; end if;
  if coalesce(p_nature, '') not in ('question', 'anomalie', 'evolution', 'facturation') then raise exception 'Nature de la demande inconnue'; end if;
  if coalesce(trim(p_sujet), '') = '' or coalesce(trim(p_message), '') = '' then raise exception 'Sujet et message obligatoires'; end if;
  if length(p_message) > 3000 or length(p_sujet) > 150 then raise exception 'Message trop long'; end if;
  if (select count(*) from pf_objets where type = 'ticket' and entreprise_id = ent and data->>'statut' in ('ouverte', 'en_cours', 'en_attente_client')) >= 20 then
    raise exception 'Trop de demandes ouvertes : le support vous recontacte';
  end if;
  select * into p from profils where user_id = auth.uid();
  ref := 'SUP-' || lpad(nextval('pf_tickets_seq')::text, 4, '0');
  insert into pf_objets (id, type, entreprise_id, data, par) values (i, 'ticket', ent, jsonb_build_object(
    'ref', ref, 'nature', p_nature, 'sujet', trim(p_sujet), 'description', trim(p_message), 'statut', 'ouverte', 'priorite', 'normale',
    'source', 'appli', 'demandeur', jsonb_build_object('nom', p.nom, 'email', p.email, 'role', p.role)), auth.uid());
  return jsonb_build_object('ref', ref);
end $$;
revoke all on function public.support_creer(text, text, text) from public, anon;
grant execute on function public.support_creer(text, text, text) to authenticated;
