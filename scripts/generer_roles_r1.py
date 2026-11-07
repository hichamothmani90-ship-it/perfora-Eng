"""Génère supabase/roles_r1.sql (lot R1 : droits par rôle) à partir des dernières versions des fonctions concernées.
Usage : python scripts/generer_roles_r1.py — ne pas modifier supabase/roles_r1.sql à la main.
Sources : push_fiches (references.sql), mon_profil, preparer_invitation (securite.sql), definir_profil (multitenant.sql),
affecter_sites, utilisation, finaliser_invitation (quotas.sql)."""
import os
import re

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SQL = os.path.join(RACINE, "supabase")


def fonction(fichier, nom):
    s = open(os.path.join(SQL, fichier), encoding="utf-8").read().replace("\r\n", "\n")
    i = s.rindex(f"create or replace function public.{nom}(")
    j = s.index("end $$;", i) + len("end $$;")
    return s[i:j]


def remplacer(texte, avant, apres):
    assert avant in texte, avant[:80]
    return texte.replace(avant, apres, 1)


# ---------- push_fiches : règles du prestataire (écriture limitée à ses interventions) ----------
push = fonction("references.sql", "push_fiches")
push = remplacer(push, """    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
""", """    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    -- R1 : un prestataire n'écrit que sur les interventions qui lui sont confiées (et ce qui s'y rattache).
    elsif r = 'prestataire' and public.prestataire_refus(t, f->>'id', p, ex.id is null) is not null then
      motif := public.prestataire_refus(t, f->>'id', p, ex.id is null);
""")

mon_profil = fonction("securite.sql", "mon_profil")
mon_profil = remplacer(mon_profil, "    'adminPlateforme', public.est_admin_plateforme(),",
                       "    'adminPlateforme', public.est_admin_plateforme(),\n    'adminClient', p.admin_client,")

prep = fonction("securite.sql", "preparer_invitation")
prep = remplacer(prep, "  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;",
                 "  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;")

definir = fonction("multitenant.sql", "definir_profil")
definir = remplacer(definir, """  if public.mon_role() is distinct from 'responsable' then
    raise exception 'Réservé au responsable' using errcode = '42501';
  end if;""", """  if not public.est_admin_client() then
    raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501';
  end if;""")
definir = remplacer(definir, """  if cible = auth.uid() and (nouveau_role <> 'responsable' or not est_actif) then
    raise exception 'Vous ne pouvez pas retirer vos propres droits de responsable';
  end if;""", """  if cible = auth.uid() and not est_actif then
    raise exception 'Vous ne pouvez pas désactiver votre propre compte';
  end if;""")

affecter = fonction("quotas.sql", "affecter_sites")
affecter = remplacer(affecter, "  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;",
                     "  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;")
util = fonction("quotas.sql", "utilisation")
util = remplacer(util, "  if public.mon_role() is distinct from 'responsable' then raise exception 'Réservé au responsable' using errcode = '42501'; end if;",
                 "  if not (public.est_admin_client() or public.mon_role() = 'responsable') then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;")
final = fonction("quotas.sql", "finaliser_invitation")
final = remplacer(final, """  foreach s in array p_sites loop""", """  -- R1 : le premier compte d'une entreprise (invité par Perfora) en devient l'administrateur.
  if not exists (select 1 from profils where entreprise_id = p_entreprise and admin_client and actif and user_id <> p_user) then
    update profils set admin_client = true where user_id = p_user;
  end if;
  foreach s in array p_sites loop""")

ENTETE = """-- GMAO terrain — lot R1 « navigation et droits par rôle » (docs/MAQUETTES_R1.md §5). APRÈS securite.sql. Rejouable.
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
"""

FONCTIONS = [
    (push, "revoke all on function public.push_fiches(jsonb) from public, anon;\ngrant execute on function public.push_fiches(jsonb) to authenticated;"),
    (mon_profil, "revoke all on function public.mon_profil() from public, anon;\ngrant execute on function public.mon_profil() to authenticated;"),
    (prep, "revoke all on function public.preparer_invitation(text, text, uuid[]) from public, anon;\ngrant execute on function public.preparer_invitation(text, text, uuid[]) to authenticated;"),
    (definir, "revoke all on function public.definir_profil(uuid, text, text, boolean) from public, anon;\ngrant execute on function public.definir_profil(uuid, text, text, boolean) to authenticated;"),
    (affecter, "revoke all on function public.affecter_sites(uuid, uuid[]) from public, anon;\ngrant execute on function public.affecter_sites(uuid, uuid[]) to authenticated;"),
    (util, "revoke all on function public.utilisation() from public, anon;\ngrant execute on function public.utilisation() to authenticated;"),
    (final, "revoke all on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) from public, anon, authenticated;\ngrant execute on function public.finaliser_invitation(uuid, uuid, text, text, uuid[]) to service_role;"),
]

FIN = """
-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
"""

sortie = ENTETE + "\n\n".join(f + "\n" + d for f, d in FONCTIONS) + "\n" + FIN
open(os.path.join(SQL, "roles_r1.sql"), "w", encoding="utf-8", newline="\n").write(sortie)
print(f"supabase/roles_r1.sql : {len(sortie) // 1024} Ko")
