-- Tests de la mise en service (reprise des données) et de D2 bis. Supabase → SQL Editor, après mise_en_service.sql.
-- Entreprise fictive MTEST (pack Pro, sans module energie). Utilise le premier administrateur plateforme.
-- Nettoie ses données. Attendu :
--  1 non-admin : erreur « Réservé à l'administrateur plateforme » ; 2 essai : acceptes 3, importe false, fiches_restantes 0 ;
--  3 refus doublon (code équipement déjà utilisé) ; 4 refus référence introuvable (localisationId) ; 5 refus site d'une autre
--  entreprise ; 6 import : importe true, fiches_lot 3, lot 1 ; 7 erreur « déjà importé » ; 8 référentiel : equipements 1 ;
--  9 compteur d'équipement en pack Pro : ok ; 10 compteur de ressource en pack Pro : refus module energie ; 11 relevé d'un
--  compteur d'équipement par le technicien : ok ; 12 changement d'usage : refus (en pack Pro, motif module energie) ; 13 technicien lit l'équipement importé : 1 ;
--  14 annulation après activité : erreur ; 15 nouveau lot puis annulation immédiate : supprimees 1 ; 16 étapes : import coché ;
--  17 nettoyage sans MTEST.
create or replace function public.gmao_test_mes() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; site uuid; site_autre uuid; adm uuid;
  resp uuid := '00000000-0000-0000-0000-0000000000e1'; tech uuid := '00000000-0000-0000-0000-0000000000e2';
  lot_ok jsonb;
begin
  select user_id into adm from admins_plateforme limit 1;
  if adm is null then raise exception 'Aucun administrateur plateforme'; end if;
  insert into entreprises(code, nom) values ('MTEST', 'Mise en service test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'pro');
  insert into sites(entreprise_id, code, nom) values (ent, 'M1', 'Site M1') returning id into site;
  select id into site_autre from sites where entreprise_id <> ent limit 1;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values
    (resp, 'resp@m.test', 'Resp', 'responsable', ent, site), (tech, 'tech@m.test', 'Tech', 'technicien', ent, site);
  insert into profil_sites values (resp, site), (tech, site);
  lot_ok := jsonb_build_array(
    jsonb_build_object('id', 'm-l1', 'type', 'localisations', 'data', jsonb_build_object('code', 'ATL', 'nom', 'Atelier', 'siteId', site)),
    jsonb_build_object('id', 'm-e1', 'type', 'equipements', 'data', jsonb_build_object('code', 'CMP-01', 'designation', 'Compresseur', 'siteId', site, 'localisationId', 'm-l1', 'classe', 'ROT-COMPR', 'criticite', 'A')),
    jsonb_build_object('id', 'm-a1', 'type', 'articles', 'data', jsonb_build_object('ref', 'FIL', 'designation', 'Filtre', 'unite', 'u')));

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=1; test:='non-admin appelle pf_importer (erreur)';
  begin r := pf_importer(ent, 'lot-test-0', 'x.xlsx', lot_ok, true); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  n:=2; test:='verification a blanc : rien ne reste'; r := pf_importer(ent, 'lot-test-1', 'kit.xlsx', lot_ok, true);
  r := r || jsonb_build_object('fiches_restantes', (select count(*) from fiches where entreprise_id = ent)); return next;
  n:=3; test:='doublon de code dans le lot (refus)';
  r := pf_importer(ent, 'lot-test-1', 'kit.xlsx', lot_ok || jsonb_build_array(jsonb_build_object('id', 'm-e2', 'type', 'equipements', 'data', jsonb_build_object('code', 'cmp-01', 'designation', 'Doublon', 'siteId', site))), true); return next;
  n:=4; test:='reference introuvable (refus)';
  r := pf_importer(ent, 'lot-test-1', 'kit.xlsx', jsonb_build_array(jsonb_build_object('id', 'm-e3', 'type', 'equipements', 'data', jsonb_build_object('code', 'P-1', 'designation', 'Pompe', 'siteId', site, 'localisationId', 'inconnu'))), true); return next;
  n:=5; test:='site d une autre entreprise (refus)';
  r := pf_importer(ent, 'lot-test-1', 'kit.xlsx', jsonb_build_array(jsonb_build_object('id', 'm-l9', 'type', 'localisations', 'data', jsonb_build_object('code', 'X', 'nom', 'X', 'siteId', site_autre))), true); return next;
  n:=6; test:='import reel (ok)'; r := pf_importer(ent, 'lot-test-1', 'kit.xlsx', lot_ok, false);
  r := r || jsonb_build_object('fiches_lot', (select count(*) from fiches where entreprise_id = ent and data->>'lotImport' = 'lot-test-1'),
    'lot', (select count(*) from pf_lots_import where id = 'lot-test-1')); return next;
  n:=7; test:='meme lot une 2e fois (erreur)';
  begin r := pf_importer(ent, 'lot-test-1', 'kit.xlsx', lot_ok, false); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=8; test:='referentiel'; r := pf_referentiel(ent);
  r := jsonb_build_object('equipements', jsonb_array_length(r->'equipements'), 'localisations', jsonb_array_length(r->'localisations'), 'articles', jsonb_array_length(r->'articles')); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=9; test:='D2 bis : compteur d equipement en pack Pro (ok)';
  r := push_fiches(jsonb_build_array(jsonb_build_object('id', 'm-c1', 'type', 'compteurs', 'patch', jsonb_build_object('id', 'm-c1', 'code', 'HRS', 'usage', 'equipement', 'equipementId', 'm-e1', 'unite', 'h', 'mode', 'cumulatif', 'siteId', site)),
    jsonb_build_object('id', 'm-j1', 'type', 'journal', 'patch', jsonb_build_object('id', 'm-j1', 'entite', 'compteurs', 'entiteId', 'm-c1', 'action', 'creation')))); return next;
  n:=10; test:='D2 bis : compteur de ressource en pack Pro (refus module energie)';
  r := push_fiches(jsonb_build_array(jsonb_build_object('id', 'm-c2', 'type', 'compteurs', 'patch', jsonb_build_object('id', 'm-c2', 'code', 'EL', 'usage', 'ressource', 'unite', 'kWh', 'mode', 'cumulatif', 'siteId', site)))); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=11; test:='D2 bis : releve d heures par le technicien (ok)';
  r := push_fiches(jsonb_build_array(jsonb_build_object('id', 'm-r1', 'type', 'releves', 'patch', jsonb_build_object('id', 'm-r1', 'compteurId', 'm-c1', 'le', '2026-11-06T08:00', 'valeur', 12300)))); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=12; test:='D2 bis : changement d usage apres releve (refus)';
  r := push_fiches(jsonb_build_array(jsonb_build_object('id', 'm-c1', 'type', 'compteurs', 'patch', jsonb_build_object('usage', 'ressource')))); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=13; test:='technicien lit l equipement importe'; r := jsonb_build_object('equipements', (select count(*) from fiches where type = 'equipements' and id = 'm-e1')); return next;
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  n:=14; test:='annulation apres activite du client (erreur)';
  begin r := pf_annuler_lot(ent, 'lot-test-1'); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=15; test:='nouveau lot puis annulation immediate (ok)';
  perform pf_importer(ent, 'lot-test-2', 'complement.xlsx', jsonb_build_array(jsonb_build_object('id', 'm-e4', 'type', 'equipements', 'data', jsonb_build_object('code', 'PRS-01', 'designation', 'Presse', 'siteId', site, 'localisationId', 'm-l1'))), false);
  r := pf_annuler_lot(ent, 'lot-test-2') || jsonb_build_object('reste', (select count(*) from fiches where id = 'm-e4'), 'annule', (select annule_le is not null from pf_lots_import where id = 'lot-test-2')); return next;
  n:=16; test:='etapes de mise en service'; perform pf_mes_etape(ent, 'import', true); perform pf_mes_etape(ent, 'kit_envoye', true); perform pf_mes_etape(ent, 'kit_envoye', false);
  r := jsonb_build_object('etapes', (select jsonb_object_keys_agg from (select jsonb_agg(k) as jsonb_object_keys_agg from jsonb_object_keys(pf_mes_lire(ent)->'etapes') k) z), 'lots', jsonb_array_length(pf_mes_lire(ent)->'lots')); return next;

  delete from fiches where entreprise_id = ent;
  delete from pf_lots_import where entreprise_id = ent;
  delete from pf_mise_en_service where entreprise_id = ent;
  delete from profil_sites where site_id = site;
  delete from profils where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from sites where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=17; test:='nettoyage'; r := jsonb_build_object('entreprises', (select string_agg(code, ', ') from entreprises)); return next;
end $$;
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_mes();
-- Puis : drop function if exists public.gmao_test_mes();
