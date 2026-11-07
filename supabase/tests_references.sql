-- Tests de l'intégrité des références (references.sql). Entreprise fictive RTEST. Nettoie ses données.
-- Attendu : 1 demande sur équipement inconnu : refus « équipement inconnu… » ; 2 sur équipement connu : ok ;
--  3 équipement + intervention dans le même envoi : ok (2) ; 4 équipement d'une autre entreprise : refus ; 5 nettoyage.
create or replace function public.gmao_test_ref() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; site uuid; tech uuid := '00000000-0000-0000-0000-0000000000a7'; resp uuid := '00000000-0000-0000-0000-0000000000a8'; autre text;
begin
  insert into entreprises(code, nom) values ('RTEST', 'References test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'pro');
  insert into sites(entreprise_id, code, nom) values (ent, 'R1', 'Site R1') returning id into site;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values (tech, 'tech@r.test', 'Tech R', 'technicien', ent, site), (resp, 'resp@r.test', 'Resp R', 'responsable', ent, site);
  insert into profil_sites values (tech, site), (resp, site);
  select id into autre from fiches where type = 'equipements' and entreprise_id <> ent limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"r-eq","type":"equipements","patch":{"id":"r-eq","code":"R-01","designation":"Pompe"}}]');
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=1; test:='demande sur equipement inconnu (refus)'; r := push_fiches('[{"id":"r-d1","type":"demandes","patch":{"id":"r-d1","equipementId":"absent","constat":"x"}}]'); return next;
  n:=2; test:='demande sur equipement connu (ok)'; r := push_fiches('[{"id":"r-d2","type":"demandes","patch":{"id":"r-d2","equipementId":"r-eq","constat":"x"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=3; test:='equipement + intervention dans le meme envoi (ok)';
  r := push_fiches('[{"id":"r-eq2","type":"equipements","patch":{"id":"r-eq2","code":"R-02","designation":"Moteur"}},{"id":"r-o1","type":"ots","patch":{"id":"r-o1","equipementId":"r-eq2","statut":"a_planifier"}}]'); return next;
  n:=4; test:='equipement d une autre entreprise (refus)';
  r := push_fiches(jsonb_build_array(jsonb_build_object('id', 'r-d3', 'type', 'demandes', 'patch', jsonb_build_object('id', 'r-d3', 'equipementId', coalesce(autre, 'absent'), 'constat', 'x')))); return next;
  delete from fiches where entreprise_id = ent;
  delete from profil_sites where site_id = site;
  delete from profils where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from sites where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=5; test:='nettoyage'; r := jsonb_build_object('entreprises', (select string_agg(code, ', ') from entreprises)); return next;
end $$;
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_ref();
-- Puis : drop function if exists public.gmao_test_ref();
