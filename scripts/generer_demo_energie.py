"""Génère supabase/demo_energie.sql à partir de Calculs.demoEnergie (js/calculs.js) : une seule définition des données
énergie de la démo pour l'appli et pour le serveur.

Usage : python scripts/generer_demo_energie.py   (node doit être installé)
Le script SQL produit :
  - public.pf_demo_energie(entreprise, site, k, comp) : insère compteurs, relevés, programme selon les heures, factures ;
  - public.pf_reinitialiser_demo : la version de supabase/demo.sql, qui appelle en plus pf_demo_energie.
"""
import json
import os
import re
import subprocess

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JS = ("const C = require('./js/calculs.js');"
      "console.log(JSON.stringify(C.demoEnergie((n, hm) => '@J(' + n + (hm ? ',' + hm : '') + ')', k => '@K' + k, '@COMP')));")


def sql_valeur(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, list):
        return "jsonb_build_array(" + ", ".join(sql_valeur(x) for x in v) + ")"
    if isinstance(v, dict):
        return "jsonb_build_object(" + ", ".join(f"'{k}', {sql_valeur(x)}" for k, x in v.items()) + ")"
    m = re.fullmatch(r"@J\((-?\d+)(?:,(\d\d:\d\d))?\)", v)
    if m:
        return f"public.pf_j({m.group(1)}, '{m.group(2)}')" if m.group(2) else f"public.pf_j({m.group(1)})"
    if v.startswith("@K"):
        return f"k || '-n{v[2:]}'"
    if v == "@COMP":
        return "comp"
    return "'" + v.replace("'", "''") + "'"


def main():
    donnees = json.loads(subprocess.run(["node", "-e", JS], cwd=RACINE, capture_output=True, text=True, encoding="utf-8", check=True).stdout)
    lignes = []
    for t, o in donnees:
        ident = sql_valeur(o["id"])
        corps = {k: v for k, v in o.items() if k != "id"}
        lignes.append(f"    ({ident}, '{t}', {sql_valeur(corps)})")
    demo = open(os.path.join(RACINE, "supabase", "demo.sql"), encoding="utf-8").read()
    debut = demo.index("create or replace function public.pf_reinitialiser_demo")
    fonction = demo[debut:]
    appel = "  update entreprises set reinit_le = now() where id = e.id;"
    assert appel in fonction
    fonction = fonction.replace(appel, "  perform public.pf_demo_energie(e.id, site, k, comp);   -- volet D : énergie et eau\n" + appel)
    sortie = f"""-- GMAO terrain — démo : énergie et eau (volet D, étape D5). APRÈS fichiers.sql (et demo.sql).
-- FICHIER GÉNÉRÉ par scripts/generer_demo_energie.py depuis Calculs.demoEnergie (js/calculs.js) : ne pas modifier à la main.
-- Scénario : arrivée générale + 3 sous-compteurs (résidu ≈ 7 % « à expliquer »), compteur de la ligne remplacé il y a
-- 30 jours, eau avec une lecture erronée (à examiner), heures du compresseur (vidange 2 000 h en alerte), factures ONEE
-- concordante puis en écart (+6 %), facture d'eau. Les écrans n'apparaissent que si l'abonnement inclut le module energie.

create or replace function public.pf_demo_energie(p_ent uuid, p_site uuid, k text, comp text)
returns integer language plpgsql security definer set search_path = public as $$
declare
  maint text := public.pf_j(0, to_char(now() at time zone 'Africa/Casablanca', 'HH24:MI'));
  n integer;
begin
  insert into fiches (id, type, entreprise_id, site_id, data)
  select v.id, v.type, p_ent, p_site,
         v.data || jsonb_build_object('id', v.id, 'siteId', p_site, 'creeLe', coalesce(v.data->>'creeLe', maint), 'creePar', coalesce(v.data->>'creePar', 'Démo'), 'modifieLe', maint, 'modifiePar', 'Démo')
  from (values
{(','+chr(10)).join(lignes)}
  ) as v(id, type, data);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.pf_demo_energie(uuid, uuid, text, text) from public, anon, authenticated;

-- Version de supabase/demo.sql + appel de pf_demo_energie.
{fonction}"""
    open(os.path.join(RACINE, "supabase", "demo_energie.sql"), "w", encoding="utf-8", newline="\n").write(sortie)
    print(f"supabase/demo_energie.sql : {len(lignes)} fiches")


if __name__ == "__main__":
    main()
