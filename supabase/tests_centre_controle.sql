-- Tests du centre de contrôle (CC1). Supabase → SQL Editor, après centre_controle.sql.
-- Entreprise fictive KTEST. Utilise le premier administrateur plateforme. Nettoie ses données (grille remise à l'état initial).
-- Attendu : 1 non-admin pf_clients : erreur « Réservé… » ; 2 fiche client enregistrée (ville Safi, 1 contact) ;
--  3 ICE invalide : erreur « ICE : 15 chiffres » ; 4 conditions : prix 900, mensuel, remise 10 ; 5 périodicité invalide :
--  erreur ; 6 pf_clients contient KTEST avec fiche et prix ; 7 grille : prix mensuel 600 ; 8 responsable lit pf_objets
--  directement : 0 ligne (aucune politique) ; 9 nettoyage sans KTEST.
create or replace function public.gmao_test_cc() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; site uuid; adm uuid; resp uuid := '00000000-0000-0000-0000-0000000000f1';
  t_avant record; x jsonb;
begin
  select user_id into adm from admins_plateforme limit 1;
  if adm is null then raise exception 'Aucun administrateur plateforme'; end if;
  insert into entreprises(code, nom) values ('KTEST', 'Centre de controle test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'essentiel');
  insert into sites(entreprise_id, code, nom) values (ent, 'K1', 'Site K1') returning id into site;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values (resp, 'resp@k.test', 'Resp', 'responsable', ent, site);
  insert into profil_sites values (resp, site);
  select * into t_avant from pf_tarifs where pack = 'essentiel';

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=1; test:='non-admin lit pf_clients (erreur)';
  begin r := pf_clients(); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  n:=2; test:='fiche client'; r := pf_client_maj(ent, '{"raisonSociale":"K SARL","ice":"001234567000089","ville":"Safi","contacts":[{"nom":"M. Test","telephone":"+212600000000"}]}'::jsonb);
  r := jsonb_build_object('ville', r->>'ville', 'contacts', jsonb_array_length(r->'contacts')); return next;
  n:=3; test:='ICE invalide (erreur)';
  begin r := pf_client_maj(ent, '{"ice":"123"}'::jsonb); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=4; test:='conditions d abonnement'; perform pf_abonnement_conditions(ent, 900, 'mensuel', 10, null, 'Engagement 12 mois');
  r := (select jsonb_build_object('prix', prix, 'periodicite', periodicite, 'remise', remise_pct) from abonnements where entreprise_id = ent); return next;
  n:=5; test:='periodicite invalide (erreur)';
  begin perform pf_abonnement_conditions(ent, 900, 'hebdo', 0, null, null); r := '{"erreur":null}'; exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=6; test:='pf_clients'; x := (select e from jsonb_array_elements(pf_clients()) e where e->>'code' = 'KTEST');
  r := jsonb_build_object('raisonSociale', x->'fiche'->>'raisonSociale', 'prix', x->'abonnement'->'prix', 'periodicite', x->'abonnement'->>'periodicite', 'actifs', x->'actifs'); return next;
  n:=7; test:='grille tarifaire'; perform pf_tarif_maj('essentiel', 600, 6000, 'test');
  r := (select e from jsonb_array_elements(pf_tarifs_lire()) e where e->>'pack' = 'essentiel'); r := jsonb_build_object('prixMensuel', r->'prixMensuel', 'prixAnnuel', r->'prixAnnuel'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=8; test:='responsable lit pf_objets directement'; r := jsonb_build_object('lignes', (select count(*) from pf_objets)); return next;
  reset role;

  update pf_tarifs set prix_mensuel = t_avant.prix_mensuel, prix_annuel = t_avant.prix_annuel, note = t_avant.note where pack = 'essentiel';
  delete from pf_objets where entreprise_id = ent;
  delete from profil_sites where site_id = site;
  delete from profils where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from sites where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=9; test:='nettoyage'; r := jsonb_build_object('entreprises', (select string_agg(code, ', ') from entreprises)); return next;
end $$;
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_cc();
-- Puis, OBLIGATOIREMENT (sinon la fonction reste appelable par l'API) : drop function if exists public.gmao_test_cc();
