-- Tests du volet C (seuils, achats, valorisation, prix invisibles aux techniciens). Supabase → SQL Editor.
-- Entreprise fictive CTEST (pack Entreprise : module achats) + PTEST (pack Pro : sans module achats).
-- Vérifie les règles de push_fiches ET la lecture réelle (set local role authenticated). Nettoie ses données.
-- Attendu : 1, 3, 6, 10, 11, 13, 15, 19 acceptés ; 2, 4, 5, 7, 8, 9, 12, 14, 18, 20 refusés avec motif ;
-- 16 technicien : achats 0, valorisations 0, journal_prix 0, receptions_visibles 1 ; 17 pilote : achats 1,
-- valorisations 1, journal_prix ≥ 1 ; 21 nettoyage sans CTEST ni PTEST.
create or replace function public.gmao_test_achats() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; site uuid; ent2 uuid; site2 uuid;
  resp uuid := '00000000-0000-0000-0000-0000000000c1'; mag uuid := '00000000-0000-0000-0000-0000000000c2';
  ach uuid := '00000000-0000-0000-0000-0000000000c3'; tech uuid := '00000000-0000-0000-0000-0000000000c4';
  pil uuid := '00000000-0000-0000-0000-0000000000c5'; mag2 uuid := '00000000-0000-0000-0000-0000000000c6';
begin
  insert into entreprises(code, nom) values ('CTEST', 'Achats test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'C1', 'Site C1') returning id into site;
  insert into entreprises(code, nom) values ('PTEST', 'Pro test') returning id into ent2;
  insert into abonnements(entreprise_id, pack) values (ent2, 'pro');
  insert into sites(entreprise_id, code, nom) values (ent2, 'P1', 'Site P1') returning id into site2;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values
    (resp, 'resp@c.test', 'Resp', 'responsable', ent, site), (mag, 'mag@c.test', 'Mag', 'magasinier', ent, site),
    (ach, 'ach@c.test', 'Acheteur', 'achats', ent, site), (tech, 'tech@c.test', 'Tech', 'technicien', ent, site),
    (pil, 'pil@c.test', 'Pilote', 'pilote', ent, site), (mag2, 'mag@p.test', 'Mag P', 'magasinier', ent2, site2);
  insert into profil_sites values (resp, site), (mag, site), (ach, site), (tech, site), (pil, site), (mag2, site2);

  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"c-art","type":"articles","patch":{"id":"c-art","ref":"FIL","designation":"Filtre"}}]');
  n:=1; test:='magasinier propose un seuil (ok)'; r:=push_fiches('[{"id":"c-s1","type":"seuils","patch":{"id":"c-s1","articleId":"c-art","statut":"propose","pointCommande":8,"cible":14}}]'); return next;
  n:=2; test:='magasinier valide son seuil (refus)'; r:=push_fiches('[{"id":"c-s1","type":"seuils","patch":{"statut":"valide","valideLe":"2026-11-06T10:00"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=3; test:='responsable valide le seuil (ok)'; r:=push_fiches('[{"id":"c-s1","type":"seuils","patch":{"statut":"valide","valideLe":"2026-11-06T10:00","validePar":"Resp"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=4; test:='magasinier modifie un seuil valide (refus)'; r:=push_fiches('[{"id":"c-s1","type":"seuils","patch":{"pointCommande":2}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=5; test:='technicien ecrit un seuil (refus)'; r:=push_fiches('[{"id":"c-s2","type":"seuils","patch":{"id":"c-s2","articleId":"c-art","statut":"propose"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=6; test:='magasinier soumet une demande d achat avec prix estime (ok)';
  r:=push_fiches('[{"id":"c-a1","type":"achats","patch":{"id":"c-a1","ref":"DA-1","statut":"soumise","lignes":[{"id":"l1","articleId":"c-art","qte":10,"prixEstime":95}]}},{"id":"c-j1","type":"journal","patch":{"id":"c-j1","entite":"achats","entiteId":"c-a1","champ":"lignes","avant":null,"apres":"prixEstime 95"}}]'); return next;
  n:=7; test:='magasinier valide la demande (refus)'; r:=push_fiches('[{"id":"c-a1","type":"achats","patch":{"statut":"validee"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', ach, 'role', 'authenticated')::text, true);
  n:=8; test:='achats cree une demande (refus)'; r:=push_fiches('[{"id":"c-a2","type":"achats","patch":{"id":"c-a2","statut":"brouillon"}}]'); return next;
  n:=9; test:='achats renseigne la commande avant validation (refus)'; r:=push_fiches('[{"id":"c-a1","type":"achats","patch":{"statut":"commandee","fournisseur":"X"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=10; test:='responsable valide (ok)'; r:=push_fiches('[{"id":"c-a1","type":"achats","patch":{"statut":"validee","valideLe":"2026-11-06T11:00"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', ach, 'role', 'authenticated')::text, true);
  n:=11; test:='achats renseigne la commande externe et le prix (ok)';
  r:=push_fiches('[{"id":"c-a1","type":"achats","patch":{"statut":"commandee","fournisseur":"Fournisseur X","refCommande":"BC-778","lignes":[{"id":"l1","articleId":"c-art","qte":10,"qteCommandee":10,"prixUnitaire":100}]}}]'); return next;
  n:=12; test:='achats remet la demande en validee (refus)'; r:=push_fiches('[{"id":"c-a1","type":"achats","patch":{"statut":"validee"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=13; test:='magasinier receptionne 6 dont 1 isolee + prix de l entree (ok, site herite)';
  r:=push_fiches('[{"id":"c-e1","type":"mouvements","patch":{"id":"c-e1","type":"entree","articleId":"c-art","qte":5,"achatId":"c-a1","ligneId":"l1"}},{"id":"c-i1","type":"mouvements","patch":{"id":"c-i1","type":"isolement","articleId":"c-art","qte":0,"quantite":1,"achatId":"c-a1","ligneId":"l1"}},{"id":"c-v1","type":"valorisations","patch":{"id":"c-v1","mouvementId":"c-e1","prixUnitaire":100,"devise":"MAD","statut":"connu"}}]');
  r:= r || jsonb_build_object('site_valorisation_ok', (select site_id = site from fiches where id = 'c-v1')); return next;
  n:=14; test:='magasinier corrige le prix (refus)'; r:=push_fiches('[{"id":"c-v1","type":"valorisations","patch":{"prixUnitaire":90}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=15; test:='responsable regularise le prix (ok)'; r:=push_fiches('[{"id":"c-v1","type":"valorisations","patch":{"prixUnitaire":98,"motif":"Avoir fournisseur"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=16; test:='technicien : aucun prix lisible (lecture RLS)';
  r:=jsonb_build_object('achats', (select count(*) from fiches where type = 'achats'), 'valorisations', (select count(*) from fiches where type = 'valorisations'),
    'journal_prix', (select count(*) from fiches where type = 'journal' and data->>'entite' in ('achats', 'valorisations')),
    'receptions_visibles', (select count(*) from fiches where id = 'c-e1')); return next;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', pil, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=17; test:='pilote : lit les achats et les prix';
  r:=jsonb_build_object('achats', (select count(*) from fiches where type = 'achats'), 'valorisations', (select count(*) from fiches where type = 'valorisations'),
    'journal_prix', (select count(*) from fiches where type = 'journal' and data->>'entite' in ('achats', 'valorisations'))); return next;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=18; test:='technicien isole une piece (refus)'; r:=push_fiches('[{"id":"c-i2","type":"mouvements","patch":{"id":"c-i2","type":"isolement","articleId":"c-art","qte":0,"quantite":1,"otId":"x"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', mag2, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"p-art","type":"articles","patch":{"id":"p-art","ref":"J"}}]');
  n:=19; test:='pack Pro : seuil propose (ok, module magasin)'; r:=push_fiches('[{"id":"p-s1","type":"seuils","patch":{"id":"p-s1","articleId":"p-art","statut":"propose"}}]'); return next;
  n:=20; test:='pack Pro : demande d achat (refus module achats)'; r:=push_fiches('[{"id":"p-a1","type":"achats","patch":{"id":"p-a1","statut":"soumise"}}]'); return next;

  delete from fiches where entreprise_id in (ent, ent2);
  delete from profil_sites where site_id in (site, site2);
  delete from profils where entreprise_id in (ent, ent2);
  delete from abonnements where entreprise_id in (ent, ent2);
  delete from sites where entreprise_id in (ent, ent2);
  delete from entreprises where id in (ent, ent2);
  n:=21; test:='nettoyage'; r:=jsonb_build_object('entreprises', (select string_agg(code, ', ') from entreprises)); return next;
end $$;
revoke all on function public.gmao_test_achats() from public, anon, authenticated;   -- jamais appelable par l'API, même si on oublie le « drop »
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_achats();
-- Puis : drop function if exists public.gmao_test_achats();
