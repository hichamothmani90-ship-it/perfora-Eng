-- Tests de l'espace « fichiers » (fichiers.sql). Vérifie la règle d'accès (fichier_autorise) pour chaque rôle, sans
-- déposer de fichier, et la présence de l'espace et de ses règles. Entreprises fictives FTEST / FAUTRE. Nettoie ses données.
-- Attendu : 1 espace privé, 10 Mo, 4 types ; 2 règles lecture + dépôt ; 3 technicien dépose une photo sur son site : true ;
--  4 sur un autre site : false ; 5 dans « couts » : false ; 6 lit « couts » : false ; 7 magasinier lit « couts » : true ;
--  8 pilote lit une photo : true ; 9 pilote dépose : false ; 10 autre entreprise : false ; 11 nom invalide : false ;
--  12 abonnement suspendu : dépôt false, lecture true ; 13 nettoyage.
create or replace function public.gmao_test_fichiers() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; ent2 uuid; s1 uuid; s2 uuid; s3 uuid;
  tech uuid := '00000000-0000-0000-0000-0000000000b1'; mag uuid := '00000000-0000-0000-0000-0000000000b2';
  pil uuid := '00000000-0000-0000-0000-0000000000b3'; autre uuid := '00000000-0000-0000-0000-0000000000b4';
  q text;
begin
  insert into entreprises(code, nom) values ('FTEST', 'Fichiers test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'F1', 'Site F1') returning id into s1;
  insert into sites(entreprise_id, code, nom) values (ent, 'F2', 'Site F2') returning id into s2;
  insert into entreprises(code, nom) values ('FAUTRE', 'Fichiers autre') returning id into ent2;
  insert into abonnements(entreprise_id, pack) values (ent2, 'pro');
  insert into sites(entreprise_id, code, nom) values (ent2, 'A1', 'Site A1') returning id into s3;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values
    (tech, 'tech@f.test', 'Tech', 'technicien', ent, s1), (mag, 'mag@f.test', 'Mag', 'magasinier', ent, s1),
    (pil, 'pil@f.test', 'Pilote', 'pilote', ent, s1), (autre, 'resp@fa.test', 'Autre', 'responsable', ent2, s3);
  insert into profil_sites values (tech, s1), (mag, s1), (pil, s1), (autre, s3);

  n:=1; test:='espace fichiers'; r := (select jsonb_build_object('prive', not public, 'limite_Mo', file_size_limit / 1048576, 'types', array_length(allowed_mime_types, 1)) from storage.buckets where id = 'fichiers'); return next;
  n:=2; test:='regles'; r := jsonb_build_object('regles', (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname in ('fichiers lecture', 'fichiers depot'))); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=3; test:='technicien depose une photo sur son site'; r := to_jsonb(fichier_autorise(ent || '/' || s1 || '/photos/abcdef123456.jpg', true)); return next;
  n:=4; test:='technicien depose sur un autre site'; r := to_jsonb(fichier_autorise(ent || '/' || s2 || '/photos/abcdef123456.jpg', true)); return next;
  n:=5; test:='technicien depose dans couts'; r := to_jsonb(fichier_autorise(ent || '/' || s1 || '/couts/abcdef123456.pdf', true)); return next;
  n:=6; test:='technicien lit couts'; r := to_jsonb(fichier_autorise(ent || '/' || s1 || '/couts/abcdef123456.pdf', false)); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=7; test:='magasinier lit couts'; r := to_jsonb(fichier_autorise(ent || '/' || s1 || '/couts/abcdef123456.pdf', false)); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', pil, 'role', 'authenticated')::text, true);
  n:=8; test:='pilote lit une photo'; r := to_jsonb(fichier_autorise(ent || '/' || s1 || '/photos/abcdef123456.jpg', false)); return next;
  n:=9; test:='pilote depose'; r := to_jsonb(fichier_autorise(ent || '/' || s1 || '/photos/abcdef123456.jpg', true)); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', autre, 'role', 'authenticated')::text, true);
  n:=10; test:='autre entreprise lit et depose'; r := jsonb_build_object('lit', fichier_autorise(ent || '/commun/documents/abcdef123456.pdf', false), 'depose', fichier_autorise(ent || '/commun/documents/abcdef123456.pdf', true)); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=11; test:='nom invalide'; r := jsonb_build_object('chemin_court', fichier_autorise(ent || '/photos/x.jpg', true), 'extension', fichier_autorise(ent || '/' || s1 || '/photos/abcdef123456.exe', true)); return next;
  update abonnements set statut = 'suspendu' where entreprise_id = ent;
  n:=12; test:='abonnement suspendu'; r := jsonb_build_object('depose', fichier_autorise(ent || '/' || s1 || '/photos/abcdef123456.jpg', true), 'lit', fichier_autorise(ent || '/' || s1 || '/photos/abcdef123456.jpg', false)); return next;

  delete from profil_sites where site_id in (s1, s2, s3);
  delete from profils where entreprise_id in (ent, ent2);
  delete from abonnements where entreprise_id in (ent, ent2);
  delete from sites where entreprise_id in (ent, ent2);
  delete from entreprises where id in (ent, ent2);
  n:=13; test:='nettoyage'; r := jsonb_build_object('entreprises', (select string_agg(code, ', ') from entreprises)); return next;
end $$;
revoke all on function public.gmao_test_fichiers() from public, anon, authenticated;   -- jamais appelable par l'API, même si on oublie le « drop »
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_fichiers();
drop function if exists public.gmao_test_fichiers();
