-- Tests d'étanchéité multi-entreprise (volet A1). À exécuter dans Supabase → SQL Editor.
-- Crée une entreprise B, un site A2 et deux techniciens fictifs, vérifie les règles avec la
-- vraie RLS (set local role authenticated), puis nettoie tout. Résultat : une ligne JSON.
-- Pré-requis : entreprise « DEMO » avec site « TNG » et un responsable (migration multitenant.sql).
-- Résultats attendus (6 nov. 2026) : 1 site_ok true · 2,3,4,6,11 refusés avec motif ·
-- 5 fiches_de_A_visibles 0 · 7 site_ok true · 8 journal_site_A2 true · 9 fiches_A2_visibles 0 ·
-- 10 fiches_B_visibles 0 · 12 fiches_test 0.

create or replace function public.gmao_test_etancheite() returns table(n int, test text, r jsonb) language plpgsql as $$
declare
  entA uuid; tng uuid; entB uuid; siteB uuid; siteA2 uuid; resp uuid;
  techA uuid := '00000000-0000-0000-0000-0000000000a1';
  techB uuid := '00000000-0000-0000-0000-0000000000b1';
  demA text;
begin
  select id into entA from entreprises where code = 'DEMO';
  select id into tng from sites where entreprise_id = entA and code = 'TNG';
  select user_id into resp from profils where role = 'responsable' and entreprise_id = entA limit 1;
  select id into demA from fiches where entreprise_id = entA and type = 'demandes' limit 1;
  insert into entreprises(code, nom) values ('TEST-B', 'Test B') returning id into entB;
  insert into sites(entreprise_id, code, nom) values (entB, 'SB', 'Site B') returning id into siteB;
  insert into abonnements(entreprise_id, pack) values (entB, 'essentiel');
  insert into sites(entreprise_id, code, nom) values (entA, 'TEST-A2', 'Site A2 test') returning id into siteA2;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values
    (techA, 'techa@test.test', 'Tech A', 'technicien', entA, tng),
    (techB, 'techb@test.test', 'Tech B', 'technicien', entB, siteB);
  insert into profil_sites values (techA, tng), (techB, siteB);

  perform set_config('request.jwt.claims', json_build_object('sub', techB, 'role', 'authenticated')::text, true);
  n:=1; test:='B : demande sans site -> site B'; r:=push_fiches('[{"id":"x-b1","type":"demandes","patch":{"id":"x-b1"}}]'); r:= r || jsonb_build_object('site_ok', (select site_id = siteB from fiches where id='x-b1')); return next;
  n:=2; test:='B : demande sur le site de A (refus)'; r:=push_fiches(jsonb_build_array(jsonb_build_object('id','x-b2','type','demandes','patch',jsonb_build_object('id','x-b2','siteId',tng)))); return next;
  n:=3; test:='B : ecrase une fiche de A par son id (refus)'; r:=push_fiches(jsonb_build_array(jsonb_build_object('id',demA,'type','demandes','patch',jsonb_build_object('constat','pirate')))); return next;
  n:=4; test:='B (pack Essentiel) : mouvement de stock (refus module)'; r:=push_fiches('[{"id":"x-b3","type":"mouvements","patch":{"id":"x-b3","qte":-1,"otId":"x"}}]'); return next;
  set local role authenticated;
  n:=5; test:='B : lecture RLS'; r:=jsonb_build_object('fiches_visibles', (select count(*) from fiches), 'fiches_de_A_visibles', (select count(*) from fiches where entreprise_id = entA), 'profils_visibles', (select count(*) from profils), 'entreprises_visibles', (select count(*) from entreprises)); return next;
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', techA, 'role', 'authenticated')::text, true);
  n:=6; test:='A technicien : demande sur un site non affecte (refus)'; r:=push_fiches(jsonb_build_array(jsonb_build_object('id','x-a1','type','demandes','patch',jsonb_build_object('id','x-a1','siteId',siteA2)))); return next;
  n:=7; test:='A technicien : demande sans site -> Site Tanger (compat v14)'; r:=push_fiches('[{"id":"x-a2","type":"demandes","patch":{"id":"x-a2"}}]'); r:= r || jsonb_build_object('site_ok', (select site_id = tng from fiches where id='x-a2')); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=8; test:='A responsable : demande sur site A2 + journal herite'; r:=push_fiches(jsonb_build_array(jsonb_build_object('id','x-a3','type','demandes','patch',jsonb_build_object('id','x-a3','siteId',siteA2)), jsonb_build_object('id','x-j3','type','journal','patch',jsonb_build_object('id','x-j3','entite','demandes','entiteId','x-a3')))); r:= r || jsonb_build_object('journal_site_A2', (select site_id = siteA2 from fiches where id='x-j3')); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', techA, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=9; test:='A technicien : ne lit pas le site A2'; r:=jsonb_build_object('fiches_A2_visibles', (select count(*) from fiches where site_id = siteA2), 'fiches_TNG_visibles', (select count(*) from fiches where site_id = tng)); return next;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=10; test:='A responsable : lit A2, rien de B'; r:=jsonb_build_object('fiches_A2_visibles', (select count(*) from fiches where site_id = siteA2), 'fiches_B_visibles', (select count(*) from fiches where entreprise_id = entB)); return next;
  reset role;
  update abonnements set statut = 'suspendu' where entreprise_id = entB;
  perform set_config('request.jwt.claims', json_build_object('sub', techB, 'role', 'authenticated')::text, true);
  n:=11; test:='B abonnement suspendu : ecriture (refus), lecture OK'; r:=push_fiches('[{"id":"x-b4","type":"demandes","patch":{"id":"x-b4"}}]'); return next;

  delete from fiches where id like 'x-%';
  delete from profil_sites where user_id in (techA, techB);
  delete from profils where user_id in (techA, techB);
  delete from abonnements where entreprise_id = entB;
  delete from sites where id in (siteB, siteA2);
  delete from entreprises where id = entB;
  n:=12; test:='nettoyage'; r:=jsonb_build_object('fiches_test', (select count(*) from fiches where id like 'x-%'), 'entreprises', (select count(*) from entreprises), 'sites', (select count(*) from sites), 'profils', (select count(*) from profils)); return next;
end $$;
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_etancheite();
-- Puis, dans une seconde exécution :
-- drop function if exists public.gmao_test_etancheite();
