-- Tests du volet D2 (énergie et eau, réglage « clôture par le responsable »). Supabase → SQL Editor, après energie.sql.
-- Entreprise fictive DTEST (pack Entreprise) + QTEST (pack Pro : sans module energie).
-- Vérifie les règles de push_fiches ET la lecture réelle (set local role authenticated). Nettoie ses données.
-- Attendu : 1, 3, 4, 5, 9, 11, 13, 15, 17, 19, 21 acceptés ; 2, 6, 7, 8, 10, 12, 14, 16, 18, 20, 22 refusés avec motif ;
-- 23 technicien : factures 0, pieces_jointes 0, journal_factures 0, releves ≥ 3, parametres 1 ;
-- 24 magasinier : factures 1, pieces_jointes 1 ; 25 nettoyage sans DTEST ni QTEST.
create or replace function public.gmao_test_energie() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; site uuid; ent2 uuid; site2 uuid;
  resp uuid := '00000000-0000-0000-0000-0000000000d1'; tech uuid := '00000000-0000-0000-0000-0000000000d2';
  expl uuid := '00000000-0000-0000-0000-0000000000d3'; ach uuid := '00000000-0000-0000-0000-0000000000d4';
  mag uuid := '00000000-0000-0000-0000-0000000000d5'; resp2 uuid := '00000000-0000-0000-0000-0000000000d6';
  pid text;
begin
  insert into entreprises(code, nom) values ('DTEST', 'Energie test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'D1', 'Site D1') returning id into site;
  insert into entreprises(code, nom) values ('QTEST', 'Pro test') returning id into ent2;
  insert into abonnements(entreprise_id, pack) values (ent2, 'pro');
  insert into sites(entreprise_id, code, nom) values (ent2, 'Q1', 'Site Q1') returning id into site2;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values
    (resp, 'resp@d.test', 'Resp', 'responsable', ent, site), (tech, 'tech@d.test', 'Tech', 'technicien', ent, site),
    (expl, 'expl@d.test', 'Operateur', 'exploitation', ent, site), (ach, 'ach@d.test', 'Acheteur', 'achats', ent, site),
    (mag, 'mag@d.test', 'Mag', 'magasinier', ent, site), (resp2, 'resp@q.test', 'Resp Q', 'responsable', ent2, site2);
  insert into profil_sites values (resp, site), (tech, site), (expl, site), (ach, site), (mag, site), (resp2, site2);
  pid := 'parametres-' || ent::text;

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=1; test:='responsable cree un compteur (ok)'; r:=push_fiches('[{"id":"d-c1","type":"compteurs","patch":{"id":"d-c1","code":"EL-01","unite":"kWh","mode":"cumulatif","coefficient":1}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=2; test:='technicien cree un compteur (refus)'; r:=push_fiches('[{"id":"d-c2","type":"compteurs","patch":{"id":"d-c2","unite":"kWh"}}]'); return next;
  n:=3; test:='technicien saisit un releve (ok, site du compteur)'; r:=push_fiches('[{"id":"d-r1","type":"releves","patch":{"id":"d-r1","compteurId":"d-c1","le":"2026-11-01T08:00","valeur":1000}}]');
  r:= r || jsonb_build_object('site_ok', (select site_id = site from fiches where id = 'd-r1')); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', expl, 'role', 'authenticated')::text, true);
  n:=4; test:='exploitation saisit un releve (ok)'; r:=push_fiches('[{"id":"d-r2","type":"releves","patch":{"id":"d-r2","compteurId":"d-c1","le":"2026-11-08T08:00","valeur":9999}}]'); return next;
  n:=5; test:='renvoi identique du releve (ok, rien ne change)'; r:=push_fiches('[{"id":"d-r2","type":"releves","patch":{"id":"d-r2","compteurId":"d-c1","le":"2026-11-08T08:00","valeur":9999}}]'); return next;
  n:=6; test:='exploitation modifie la valeur (refus)'; r:=push_fiches('[{"id":"d-r2","type":"releves","patch":{"valeur":1025}}]'); return next;
  n:=7; test:='releve sur compteur inconnu (refus)'; r:=push_fiches('[{"id":"d-r3","type":"releves","patch":{"id":"d-r3","compteurId":"inconnu","le":"2026-11-08T08:00","valeur":1}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=8; test:='technicien qualifie un releve (refus)'; r:=push_fiches('[{"id":"d-r2","type":"releves","patch":{"decision":"invalide"}}]'); return next;
  n:=9; test:='correction = nouveau releve lie (ok)'; r:=push_fiches('[{"id":"d-r4","type":"releves","patch":{"id":"d-r4","compteurId":"d-c1","le":"2026-11-08T08:05","valeur":1025,"remplaceId":"d-r2"}}]'); return next;
  n:=10; test:='correction d un releve d un autre compteur (refus)'; r:=push_fiches('[{"id":"d-r5","type":"releves","patch":{"id":"d-r5","compteurId":"d-c1","le":"2026-11-09T08:00","valeur":1030,"remplaceId":"inconnu"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=11; test:='responsable qualifie un releve (ok)'; r:=push_fiches('[{"id":"d-r1","type":"releves","patch":{"decision":"confirme","motifDecision":"Verifie sur place","decidePar":"Resp"}}]'); return next;
  n:=12; test:='compteur releve : changement de coefficient (refus, rupture)'; r:=push_fiches('[{"id":"d-c1","type":"compteurs","patch":{"coefficient":2}}]'); return next;
  n:=13; test:='compteur releve : libelle modifiable (ok)'; r:=push_fiches('[{"id":"d-c1","type":"compteurs","patch":{"libelle":"Arrivee generale"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=14; test:='technicien saisit une facture (refus)'; r:=push_fiches('[{"id":"d-f0","type":"factures_energie","patch":{"id":"d-f0","montantHT":1}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', ach, 'role', 'authenticated')::text, true);
  n:=15; test:='achats saisit une facture + piece jointe + journal (ok)';
  r:=push_fiches('[{"id":"d-f1","type":"factures_energie","patch":{"id":"d-f1","du":"2026-10-15","au":"2026-11-15","quantite":1010,"unite":"kWh","montantHT":1500,"compteurIds":["d-c1"]}},{"id":"d-pj","type":"photos","patch":{"id":"d-pj","parentType":"factures_energie","parentId":"d-f1","dataUrl":"data:application/pdf;base64,AA=="}},{"id":"d-j1","type":"journal","patch":{"id":"d-j1","entite":"factures_energie","entiteId":"d-f1","action":"creation","apres":"1500"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=16; test:='technicien change les reglages (refus)'; r:=push_fiches(jsonb_build_array(jsonb_build_object('id', pid, 'type', 'parametres', 'patch', jsonb_build_object('id', pid, 'clotureParResponsable', true)))); return next;
  n:=17; test:='sans reglage : le technicien cloture (ok)'; r:=push_fiches('[{"id":"d-o1","type":"ots","patch":{"id":"d-o1","statut":"en_cours"}},{"id":"d-o1","type":"ots","patch":{"statut":"cloturee"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=18; test:='reglages : identifiant d une autre entreprise (refus)'; r:=push_fiches('[{"id":"parametres-autre","type":"parametres","patch":{"id":"parametres-autre","clotureParResponsable":true}}]'); return next;
  n:=19; test:='responsable active la cloture par le responsable (ok)'; r:=push_fiches(jsonb_build_array(jsonb_build_object('id', pid, 'type', 'parametres', 'patch', jsonb_build_object('id', pid, 'clotureParResponsable', true)))); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=20; test:='avec reglage : technicien termine (ok) puis cloture (refus)'; r:=push_fiches('[{"id":"d-o2","type":"ots","patch":{"id":"d-o2","statut":"en_cours"}},{"id":"d-o2","type":"ots","patch":{"statut":"travail_termine"}},{"id":"d-o2","type":"ots","patch":{"statut":"cloturee"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=21; test:='le responsable cloture (ok)'; r:=push_fiches('[{"id":"d-o2","type":"ots","patch":{"statut":"cloturee"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp2, 'role', 'authenticated')::text, true);
  n:=22; test:='pack Pro : compteur (refus module energie)'; r:=push_fiches('[{"id":"q-c1","type":"compteurs","patch":{"id":"q-c1","unite":"kWh"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=23; test:='technicien : ni facture, ni piece jointe, ni journal de facture (lecture RLS)';
  r:=jsonb_build_object('factures', (select count(*) from fiches where type = 'factures_energie'),
    'pieces_jointes', (select count(*) from fiches where type = 'photos' and data->>'parentType' = 'factures_energie'),
    'journal_factures', (select count(*) from fiches where type = 'journal' and data->>'entite' = 'factures_energie'),
    'releves', (select count(*) from fiches where type = 'releves'), 'parametres', (select count(*) from fiches where type = 'parametres')); return next;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=24; test:='magasinier : lit les montants (comme les prix)';
  r:=jsonb_build_object('factures', (select count(*) from fiches where type = 'factures_energie'),
    'pieces_jointes', (select count(*) from fiches where type = 'photos' and data->>'parentType' = 'factures_energie')); return next;
  reset role;

  delete from fiches where entreprise_id in (ent, ent2);
  delete from profil_sites where site_id in (site, site2);
  delete from profils where entreprise_id in (ent, ent2);
  delete from abonnements where entreprise_id in (ent, ent2);
  delete from sites where entreprise_id in (ent, ent2);
  delete from entreprises where id in (ent, ent2);
  n:=25; test:='nettoyage'; r:=jsonb_build_object('entreprises', (select string_agg(code, ', ') from entreprises)); return next;
end $$;
revoke all on function public.gmao_test_energie() from public, anon, authenticated;   -- jamais appelable par l'API, même si on oublie le « drop »
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_energie();
-- Puis : drop function if exists public.gmao_test_energie();
