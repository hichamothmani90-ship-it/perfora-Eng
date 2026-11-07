-- Empreinte du schéma Perfora (fonctions, règles d'accès, déclencheurs, colonnes, droits d'exécution).
-- À lancer sur deux bases (projet Supabase / base reconstruite) : les deux résultats doivent être identiques.
-- Fonctions comparées sans les commentaires ni les espaces (un commentaire ajouté après coup n'est pas un écart).
select '##' || json_build_object(
  'fonctions', (select json_object_agg(k, v order by k) from (
      select p.oid::regprocedure::text as k, md5(btrim(regexp_replace(regexp_replace(pg_get_functiondef(p.oid), '--[^
]*', '', 'g'), '\s+', ' ', 'g'))) as v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public') x),
  'appelables_sans_compte', (select coalesce(json_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text), '[]') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')),
  'appelables_connecte', (select md5(string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')),
  'regles', (select json_object_agg(k, v order by k) from (
      select schemaname || '.' || tablename || ':' || policyname as k, md5(coalesce(cmd, '') || array_to_string(roles, ',') || coalesce(qual, '') || '|' || coalesce(with_check, '')) as v
      from pg_policies where schemaname in ('public', 'storage')) x),
  'declencheurs', (select json_object_agg(k, v order by k) from (
      select c.relname || ':' || t.tgname as k, md5(pg_get_triggerdef(t.oid)) as v
      from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and not t.tgisinternal) x),
  'colonnes', (select md5(string_agg(table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, ''), ',' order by table_name, column_name))
      from information_schema.columns where table_schema = 'public'),
  'index', (select md5(string_agg(indexdef, ',' order by indexname)) from pg_indexes where schemaname = 'public'),
  'contraintes', (select md5(string_agg(conname || pg_get_constraintdef(oid), ',' order by conname)) from pg_constraint where connamespace = 'public'::regnamespace),
  'rls', (select json_object_agg(relname, relrowsecurity order by relname) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'),
  'espace_fichiers', (select json_build_object('public', public, 'taille', file_size_limit, 'types', allowed_mime_types) from storage.buckets where id = 'fichiers')
)::text as empreinte;
