"""Séquence SQL numérotée pour construire une base Perfora neuve (production) — étape 5 du chemin vers le pilote.

Les scripts de supabase/ restent la source (historique, tests) ; ce programme en fait une séquence unique et ordonnée :
  supabase/production/01_schema.sql … 20_demo_energie.sql, 99_controles.sql   (copies numérotées, générées)
  supabase/production/construire_base.sql                                       (tout, dans l'ordre, en un seul fichier)
  supabase/production/MANIFESTE.txt                                             (ordre + empreinte SHA-256 de chaque source)

Usage : python scripts/assembler_sql.py          (régénère)
        python scripts/assembler_sql.py --verifier  (échoue si la séquence n'est plus à jour : à lancer avant un commit)
Ne jamais modifier les fichiers de supabase/production/ à la main.
"""
import hashlib
import os
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(RACINE, "supabase")
DEST = os.path.join(SRC, "production")

# Ordre validé (docs/PROMPT_REPRISE.md) ; chaque script suppose les précédents.
ORDRE = ["schema", "roles", "multitenant", "quotas", "plateforme", "durcissement", "magasin", "achats", "energie",
         "mise_en_service", "centre_controle", "centre_controle_cc2", "references", "fichiers", "securite", "roles_r1", "interventions_r2", "membres_r3", "demo", "demo_energie"]

CONTROLES = """-- 99 — contrôles de fin de construction (base neuve). Rejouable.
-- 1) multitenant.sql a créé « Perfora Démo » pour migrer d'anciennes données : sur une base neuve elle est vide,
--    on la retire (les démos commerciales se créent depuis la console, entreprise « démo »).
do $$
declare ent uuid;
begin
  select id into ent from public.entreprises where code = 'DEMO' and not demo;
  if ent is not null and not exists (select 1 from public.fiches where entreprise_id = ent)
     and not exists (select 1 from public.profils where entreprise_id = ent) then
    delete from public.abonnements where entreprise_id = ent;
    delete from public.sites where entreprise_id = ent;
    delete from public.entreprises where id = ent;
  end if;
end $$;

-- 2) Résultat attendu : une seule ligne, tout à 0 / vrai.
select json_build_object(
  'fonctions_ouvertes_sans_compte', (select coalesce(json_agg(p.proname), '[]') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')),
  'tables_sans_rls', (select coalesce(json_agg(c.relname), '[]') from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  'packs', (select count(*) from public.packs),
  'espace_fichiers', (select count(*) from storage.buckets where id = 'fichiers'),
  'entreprises', (select count(*) from public.entreprises),
  'fiches', (select count(*) from public.fiches)
)::text as controle_construction;
"""


def empreinte(t):
    return hashlib.sha256(t.encode("utf-8")).hexdigest()[:16]


def construire():
    fichiers, morceaux, manifeste = {}, [], ["Séquence de construction d'une base Perfora neuve (générée par scripts/assembler_sql.py)", ""]
    for i, nom in enumerate(ORDRE, 1):
        texte = open(os.path.join(SRC, nom + ".sql"), encoding="utf-8").read().replace("\r\n", "\n")
        cible = f"{i:02d}_{nom}.sql"
        tete = f"-- ===== {cible} — copie générée de supabase/{nom}.sql (empreinte {empreinte(texte)}) : ne pas modifier ici =====\n"
        fichiers[cible] = tete + texte
        morceaux.append(tete + texte.rstrip() + "\n")
        manifeste.append(f"{cible:28s} supabase/{nom}.sql  sha256:{empreinte(texte)}")
    fichiers["99_controles.sql"] = CONTROLES
    morceaux.append("-- ===== 99_controles.sql =====\n" + CONTROLES)
    manifeste.append(f"{'99_controles.sql':28s} (contrôles de fin, généré)")
    fichiers["construire_base.sql"] = ("-- Perfora — construction complète d'une base neuve (Supabase → SQL Editor, en une fois).\n"
                                       "-- FICHIER GÉNÉRÉ par scripts/assembler_sql.py : ne pas modifier à la main.\n"
                                       "-- Ensuite : désigner l'administrateur plateforme (voir docs/PRODUCTION_ET_SAUVEGARDE.md).\n\n"
                                       + "\n".join(morceaux))
    fichiers["MANIFESTE.txt"] = "\n".join(manifeste) + "\n"
    return fichiers


def anciens(fichiers):
    """Fichiers NN_*.sql du dossier qui ne font plus partie de la séquence (numérotation changée)."""
    if not os.path.isdir(DEST):
        return []
    return sorted(n for n in os.listdir(DEST) if n[:2].isdigit() and n.endswith(".sql") and n not in fichiers)


def main():
    fichiers = construire()
    if "--verifier" in sys.argv:
        perimes = [n for n, t in fichiers.items()
                   if not os.path.exists(os.path.join(DEST, n)) or open(os.path.join(DEST, n), encoding="utf-8").read() != t]
        perimes += [n + " (en trop)" for n in anciens(fichiers)]
        if perimes:
            sys.exit("Séquence SQL périmée : python scripts/assembler_sql.py  (" + ", ".join(perimes) + ")")
        print("Séquence SQL à jour")
        return
    os.makedirs(DEST, exist_ok=True)
    for n in anciens(fichiers):   # copies numérotées d'une séquence précédente : à ne jamais rejouer
        os.remove(os.path.join(DEST, n))
    for n, t in fichiers.items():
        open(os.path.join(DEST, n), "w", encoding="utf-8", newline="\n").write(t)
    print(f"supabase/production : {len(fichiers)} fichiers, construire_base.sql = {len(fichiers['construire_base.sql']) // 1024} Ko")


if __name__ == "__main__":
    main()
