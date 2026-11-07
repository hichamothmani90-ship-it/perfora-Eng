"""Génère supabase/interventions_r2.sql (lot R2 : qualification proposée / validée, arrêts planifiés / non planifiés)
à partir de la dernière version de push_fiches (roles_r1.sql).
Usage : python scripts/generer_interventions_r2.py — ne pas modifier supabase/interventions_r2.sql à la main."""
import os

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


push = fonction("roles_r1.sql", "push_fiches")
# 1) nature et priorité écrites par le terrain deviennent des propositions (avant toute règle)
push = remplacer(push, """    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
""", """    select id, entreprise_id, site_id, data into ex from fiches where id = f->>'id';
    -- R2 : nature et priorité écrites par le terrain = proposition (le responsable valide).
    if t = 'ots' and terrain then p := public.r2_qualif_terrain(p, ex.data, ex.id is null); end if;
""")
# 2) refus : validation par le terrain, proposition sur une qualification déjà validée, arrêt non planifié incomplet
push = remplacer(push, """    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then""",
"""    elsif t = 'ots' and terrain and (p->'qualificationValidee' = 'true'::jsonb or p ? 'qualifieePar' or p ? 'qualifieeLe') then
      motif := 'validation de la qualification : réservée au responsable';
    elsif t = 'ots' and terrain and ex.data->'qualificationValidee' = 'true'::jsonb
          and (p ? 'natureProposee' or p ? 'prioriteProposee' or p ? 'qualificationValidee') then
      motif := 'qualification déjà validée par le responsable : demandez-lui de la changer';
    elsif t = 'ots' and p->>'statut' in ('cloturee', 'travail_termine') and coalesce(ex.data->>'statut', '') <> p->>'statut'
          and public.r2_arret_incomplet(coalesce(ex.data, '{}'::jsonb) || p) then
      motif := 'arrêt non planifié : indiquer la remise à disposition ou « heures inconnues »';
    elsif t = 'ots' and r <> 'responsable' and ex.data->>'statut' = 'cloturee' then""")

ENTETE = """-- GMAO terrain — lot R2 « fiche intervention en étapes » (docs/MAQUETTES_R2.md §2, §3, §7). APRÈS roles_r1.sql. Rejouable.
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

"""

FIN = """
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
"""

sortie = ENTETE + push + "\n" + FIN
open(os.path.join(SQL, "interventions_r2.sql"), "w", encoding="utf-8", newline="\n").write(sortie)
print(f"supabase/interventions_r2.sql : {len(sortie) // 1024} Ko")
