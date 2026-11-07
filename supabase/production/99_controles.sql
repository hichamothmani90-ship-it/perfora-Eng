-- 99 — contrôles de fin de construction (base neuve). Rejouable.
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
