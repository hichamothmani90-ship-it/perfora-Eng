-- Tests des règles du magasin relié au terrain (volet B2). Supabase → SQL Editor. Nettoie ses données.
-- Entreprise fictive MTEST (pack Pro) + entreprise ETEST (pack Essentiel, sans module magasin).
create or replace function public.gmao_test_magasin() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; site uuid; ent2 uuid; site2 uuid;
  resp uuid := '00000000-0000-0000-0000-0000000000d1'; tech uuid := '00000000-0000-0000-0000-0000000000d2';
  mag uuid := '00000000-0000-0000-0000-0000000000d3'; tech2 uuid := '00000000-0000-0000-0000-0000000000d4';
  claims text;
begin
  insert into entreprises(code, nom) values ('MTEST', 'Magasin test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'pro');
  insert into sites(entreprise_id, code, nom) values (ent, 'M1', 'Site M1') returning id into site;
  insert into entreprises(code, nom) values ('ETEST', 'Essentiel test') returning id into ent2;
  insert into abonnements(entreprise_id, pack) values (ent2, 'essentiel');
  insert into sites(entreprise_id, code, nom) values (ent2, 'E1', 'Site E1') returning id into site2;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values
    (resp, 'resp@m.test', 'Resp', 'responsable', ent, site), (tech, 'tech@m.test', 'Tech', 'technicien', ent, site),
    (mag, 'mag@m.test', 'Mag', 'magasinier', ent, site), (tech2, 'tech@e.test', 'Tech E', 'technicien', ent2, site2);
  insert into profil_sites values (resp, site), (tech, site), (mag, site), (tech2, site2);

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"m-ot","type":"ots","patch":{"id":"m-ot","statut":"en_cours"}},{"id":"m-art","type":"articles","patch":{"id":"m-art","ref":"J80"}},{"id":"m-e","type":"mouvements","patch":{"id":"m-e","type":"entree","articleId":"m-art","qte":5}}]');

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=1; test:='technicien demande une piece (ok, site herite de l intervention)';
  r:=push_fiches('[{"id":"m-b1","type":"besoins","patch":{"id":"m-b1","otId":"m-ot","articleId":"m-art","qte":2,"statut":"demande"}}]');
  r:= r || jsonb_build_object('site_ok', (select site_id = site from fiches where id = 'm-b1')); return next;
  n:=2; test:='technicien reserve lui-meme (refus)'; r:=push_fiches('[{"id":"m-b1","type":"besoins","patch":{"qteReservee":2,"statut":"reserve"}}]'); return next;
  n:=3; test:='technicien : besoin sans intervention (refus)'; r:=push_fiches('[{"id":"m-b2","type":"besoins","patch":{"id":"m-b2","qte":1}}]'); return next;
  n:=4; test:='technicien : remise normale (refus)'; r:=push_fiches('[{"id":"m-r1","type":"mouvements","patch":{"id":"m-r1","type":"remise","qte":-1,"articleId":"m-art","besoinId":"m-b1"}}]'); return next;
  n:=5; test:='technicien : reception de stock (refus)'; r:=push_fiches('[{"id":"m-e2","type":"mouvements","patch":{"id":"m-e2","type":"entree","qte":10,"articleId":"m-art","otId":"m-ot"}}]'); return next;
  n:=6; test:='technicien : retrait urgent (ok)'; r:=push_fiches('[{"id":"m-u1","type":"mouvements","patch":{"id":"m-u1","type":"remise","urgent":true,"aVerifier":true,"qte":-1,"articleId":"m-art","besoinId":"m-b1"}}]'); return next;
  n:=7; test:='technicien : modifie la quantite du retrait (refus)'; r:=push_fiches('[{"id":"m-u1","type":"mouvements","patch":{"qte":-5}}]'); return next;
  n:=8; test:='technicien : retour (ok)'; r:=push_fiches('[{"id":"m-rt","type":"mouvements","patch":{"id":"m-rt","type":"retour","qte":1,"articleId":"m-art","besoinId":"m-b1"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=9; test:='magasinier reserve (ok)'; r:=push_fiches('[{"id":"m-b1","type":"besoins","patch":{"qteReservee":2,"statut":"reserve"}}]'); return next;
  n:=10; test:='magasinier remet (ok)'; r:=push_fiches('[{"id":"m-r2","type":"mouvements","patch":{"id":"m-r2","type":"remise","qte":-1,"articleId":"m-art","besoinId":"m-b1"}}]'); return next;
  n:=11; test:='magasinier verifie le retrait urgent (ok, quantite inchangee)';
  r:=push_fiches('[{"id":"m-u1","type":"mouvements","patch":{"verifieLe":"2026-11-06T18:00","verifiePar":"Mag"}}]');
  r:= r || jsonb_build_object('qte', (select data->'qte' from fiches where id = 'm-u1'), 'verifie', (select data->>'verifieLe' from fiches where id = 'm-u1')); return next;
  n:=16; test:='renvoi identique du retour (ok, idempotent)'; perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  r:=push_fiches('[{"id":"m-rt","type":"mouvements","patch":{"id":"m-rt","type":"retour","qte":1,"articleId":"m-art","besoinId":"m-b1"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=12; test:='magasinier modifie une quantite (refus)'; r:=push_fiches('[{"id":"m-r2","type":"mouvements","patch":{"qte":-9}}]'); return next;
  n:=13; test:='stock physique final (5 - 1 urgent + 1 retour - 1 remise = 4)';
  r:=jsonb_build_object('stock', (select sum((data->>'qte')::numeric) from fiches where entreprise_id = ent and type = 'mouvements' and data->>'articleId' = 'm-art')); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech2, 'role', 'authenticated')::text, true);
  insert into fiches (id, type, data, entreprise_id, site_id) values ('e-ot', 'ots', '{"id":"e-ot"}', ent2, site2);
  n:=14; test:='pack Essentiel : besoin de piece (refus module)'; r:=push_fiches('[{"id":"e-b1","type":"besoins","patch":{"id":"e-b1","otId":"e-ot","qte":1}}]'); return next;

  delete from fiches where entreprise_id in (ent, ent2);
  delete from profil_sites where site_id in (site, site2);
  delete from profils where entreprise_id in (ent, ent2);
  delete from abonnements where entreprise_id in (ent, ent2);
  delete from sites where entreprise_id in (ent, ent2);
  delete from entreprises where id in (ent, ent2);
  n:=15; test:='nettoyage'; r:=jsonb_build_object('entreprises', (select string_agg(code, ', ') from entreprises)); return next;
end $$;
revoke all on function public.gmao_test_magasin() from public, anon, authenticated;   -- jamais appelable par l'API, même si on oublie le « drop »
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_magasin();
-- Puis : drop function if exists public.gmao_test_magasin();
