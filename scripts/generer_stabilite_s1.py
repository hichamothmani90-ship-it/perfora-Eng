"""Génère supabase/stabilite_s1.sql (lot S1 de stabilisation : fusion des listes élément par élément, version minimale
de l'appli) à partir de la dernière version de push_fiches (membres_r3.sql).
Usage : python scripts/generer_stabilite_s1.py — ne pas modifier supabase/stabilite_s1.sql à la main."""
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


push = fonction("membres_r3.sql", "push_fiches")
push = remplacer(push, "create or replace function public.push_fiches(lot jsonb)", "create or replace function public.push_fiches(lot jsonb, version text default null)")
push = remplacer(push, "gere boolean; soi boolean; lie boolean;", "gere boolean; soi boolean; lie boolean; listes jsonb;")
push = remplacer(push, """  terrain := r in ('technicien', 'prestataire');
""", """  -- S1 : version minimale de l'appli (appel par l'API seulement ; rien n'est accepté, la file reste sur le téléphone).
  motif := public.s1_version_refus(version);
  if motif is not null then raise exception '%', motif using errcode = 'P0001'; end if;
  terrain := r in ('technicien', 'prestataire');
""")
push = remplacer(push, """    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
""", """    t := f->>'type'; p := coalesce(f->'patch', '{}'::jsonb);
    -- S1 : changements de listes décrits par l'appareil (jamais enregistrés tels quels).
    listes := p->'$listes'; p := p - '$listes';
""")
push = remplacer(push, """    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
""", """    -- S1 : une liste modifiée en même temps par deux appareils garde les ajouts des deux (fusion élément par élément).
    if ex.id is not null and t not in ('journal', 'mouvements', 'photos') then
      p := public.s1_fusion_listes(ex.data, p, listes);
    end if;
    data_site := case when s is null then '{}'::jsonb else jsonb_build_object('siteId', s) end;
""")

ENTETE = """-- GMAO terrain — lot S1 de stabilisation (docs/AUDIT_STABILITE_MODELE.md §4 A et D). APRÈS membres_r3.sql. Rejouable.
-- FICHIER GÉNÉRÉ par scripts/generer_stabilite_s1.py : ne pas modifier à la main.
-- A : listes fusionnées élément par élément. Une liste dont tous les éléments ont un « id » (intervenants, pièces,
--     réserves, lignes…) ou sont de simples valeurs (activités, demandeIds, membreIds…) n'est plus remplacée en entier :
--     l'appareil décrit ses changements (« $listes » : clés ajoutées ou modifiées, clés retirées) ; le serveur garde ses
--     éléments et n'applique que ces changements. Sans description (ancienne appli) : tous les éléments envoyés
--     comptent comme modifiés, rien n'est retiré. Autres listes : remplacées comme avant.
-- D : version minimale de l'appli (pf_reglages.version_minimale, « v0 » = pas de contrôle) : push_fiches(lot, version)
--     refuse tout le lot d'une version plus ancienne, seulement quand l'appel vient de l'API (pas du SQL Editor).
--     Pour l'imposer : update public.pf_reglages set valeur = 'v39' where cle = 'version_minimale';

create table if not exists public.pf_reglages (cle text primary key, valeur text not null);
alter table public.pf_reglages enable row level security;
revoke all on public.pf_reglages from public, anon, authenticated;
insert into public.pf_reglages (cle, valeur) values ('version_minimale', 'v0') on conflict (cle) do nothing;

create or replace function public.s1_version_num(v text)
returns integer language sql immutable set search_path = public as $$
  select coalesce(nullif(regexp_replace(coalesce(v, ''), '[^0-9]', '', 'g'), '')::integer, 0)
$$;
revoke all on function public.s1_version_num(text) from public, anon, authenticated;

/** Motif de refus si l'appli qui appelle par l'API est plus ancienne que la version minimale (null = accepté). */
create or replace function public.s1_version_refus(version text)
returns text language plpgsql stable security definer set search_path = public as $$
declare mini text := (select valeur from pf_reglages where cle = 'version_minimale');
begin
  if current_setting('request.method', true) is null or current_setting('request.method', true) = '' then return null; end if;
  if public.s1_version_num(version) < public.s1_version_num(mini) then
    return 'Version de l''appli trop ancienne (' || coalesce(version, 'inconnue') || ') : rechargez la page pour passer à la version '
      || mini || ' ou plus récente. Vos saisies restent sur l''appareil.';
  end if;
  return null;
end $$;
revoke all on function public.s1_version_refus(text) from public, anon, authenticated;

/** Clé d'un élément de liste : son « id » (objet), sa valeur (texte, nombre) ; null si l'élément n'a pas de clé. */
create or replace function public.s1_cle(e jsonb)
returns text language sql immutable set search_path = public as $$
  select case jsonb_typeof(e) when 'object' then e->>'id' when 'array' then null when 'null' then null else e #>> '{}' end
$$;
revoke all on function public.s1_cle(jsonb) from public, anon, authenticated;

create or replace function public.s1_fusionnable(a jsonb)
returns boolean language sql immutable set search_path = public as $$
  select jsonb_typeof(a) = 'array' and not exists (select 1 from jsonb_array_elements(a) x where public.s1_cle(x) is null)
$$;
revoke all on function public.s1_fusionnable(jsonb) from public, anon, authenticated;

/** Fusion des listes d'un patch avec la fiche du serveur (voir l'en-tête). listes = { champ: { modifies: [clés],
    retraits: [clés] } } : seuls les éléments ajoutés ou modifiés par l'appareil remplacent ceux du serveur ; sans
    description (ancienne appli), tous les éléments envoyés comptent comme modifiés (rien n'est retiré). */
create or replace function public.s1_fusion_listes(d jsonb, p jsonb, listes jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare k text; a jsonb; b jsonb; m jsonb; rem text[]; mod text[]; vus text[]; res jsonb; e jsonb; c text;
begin
  if d is null then return p; end if;
  for k in select jsonb_object_keys(p) loop
    a := d->k; b := p->k;
    continue when not public.s1_fusionnable(a) or not public.s1_fusionnable(b);
    m := case when jsonb_typeof(listes->k) = 'object' then listes->k else '{}'::jsonb end;
    rem := array(select jsonb_array_elements_text(case when jsonb_typeof(m->'retraits') = 'array' then m->'retraits' else '[]'::jsonb end));
    mod := case when jsonb_typeof(m->'modifies') = 'array' then array(select jsonb_array_elements_text(m->'modifies'))
                else array(select public.s1_cle(x) from jsonb_array_elements(b) x) end;
    res := '[]'::jsonb; vus := '{}';
    for e in select value from jsonb_array_elements(a) loop        -- ce que le serveur a déjà, dans son ordre
      c := public.s1_cle(e);
      continue when c = any (vus);
      vus := vus || c;
      continue when c = any (rem);
      res := res || jsonb_build_array(case when c = any (mod)
        then coalesce((select x from jsonb_array_elements(b) x where public.s1_cle(x) = c limit 1), e) else e end);
    end loop;
    for e in select value from jsonb_array_elements(b) loop        -- puis les éléments ajoutés par l'appareil
      c := public.s1_cle(e);
      continue when c = any (vus) or c = any (rem) or not (c = any (mod));
      vus := vus || c;
      res := res || jsonb_build_array(e);
    end loop;
    p := jsonb_set(p, array[k], res);
  end loop;
  return p;
end $$;
revoke all on function public.s1_fusion_listes(jsonb, jsonb, jsonb) from public, anon, authenticated;

-- Nouvelle signature (version de l'appli) : l'ancienne est retirée ; les appels « push_fiches(lot) » restent valables.
drop function if exists public.push_fiches(jsonb);
"""

FIN = """
revoke all on function public.push_fiches(jsonb, text) from public, anon;
grant execute on function public.push_fiches(jsonb, text) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
"""

sortie = ENTETE + "\n" + push + "\n" + FIN
open(os.path.join(SQL, "stabilite_s1.sql"), "w", encoding="utf-8", newline="\n").write(sortie)
print(f"supabase/stabilite_s1.sql : {len(sortie) // 1024} Ko")
