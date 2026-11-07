-- Tests du lot R3 (membres, équipes, sociétés prestataires, relier un compte). Supabase → SQL Editor, après
-- membres_r3.sql. Entreprise fictive R3TEST, comptes fictifs. Nettoie ses données.
-- Attendu : 1 technicien crée un membre : refus ; 2 technicien change son téléphone : ok ; 3 technicien change son rôle :
--  refus ; 4 responsable (non admin) crée un membre sans accès : ok ; 5 administrateur (direction) crée une équipe : ok ;
--  6 technicien crée une équipe : refus ; 7 responsable change le rôle d'un membre avec accès : refus ; 8 responsable
--  renomme un membre avec accès : ok, le compte suit ; 9 magasinier crée une société prestataire : refus ; 10 magasinier
--  crée un fournisseur : ok ; 11 responsable crée une société prestataire : ok ; 12 prestataire voit l'intervention
--  confiée à sa société, l'autre prestataire non ; 13 prestataire s'y ajoute comme intervenant : ok ; 14 technicien confie
--  une intervention à une équipe : refus ; 15 prestataire lit sa société, pas un autre fournisseur ; 16 relier_membre par
--  un responsable non admin : refus ; 17 par l'administrateur : relié, rôle repris, ancienne fiche inactive ; 18 retirer
--  l'accès : compte désactivé, membre actif ; 19 reprise du texte « societe » ; 20 aucune fonction ouverte sans compte ;
--  21 nettoyage.
create or replace function public.gmao_test_r3() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; s uuid;
  adm uuid := '00000000-0000-0000-0000-0000000000f1'; resp uuid := '00000000-0000-0000-0000-0000000000f2';
  tech uuid := '00000000-0000-0000-0000-0000000000f3'; pres uuid := '00000000-0000-0000-0000-0000000000f4';
  pres2 uuid := '00000000-0000-0000-0000-0000000000f5'; mag uuid := '00000000-0000-0000-0000-0000000000f6';
  nouveau uuid := '00000000-0000-0000-0000-0000000000f7';
  q jsonb; e text;
begin
  insert into entreprises(code, nom) values ('R3TEST', 'R3 test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'R3', 'Site R3') returning id into s;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut, personne_id, admin_client) values
    (adm, 'adm@r3.test', 'Adm R3', 'pilote', ent, s, 'z-p-adm', true),
    (resp, 'resp@r3.test', 'Resp R3', 'responsable', ent, s, 'z-p-resp', false),
    (tech, 'tech@r3.test', 'Tech R3', 'technicien', ent, s, 'z-p-tech', false),
    (pres, 'pres@r3.test', 'Pres R3', 'prestataire', ent, s, 'z-p-pres', false),
    (pres2, 'pres2@r3.test', 'Pres2 R3', 'prestataire', ent, s, 'z-p-pres2', false),
    (mag, 'mag@r3.test', 'Mag R3', 'magasinier', ent, s, 'z-p-mag', false),
    (nouveau, 'nouveau@r3.test', 'nouveau', 'technicien', ent, s, 'z-p-auto', false);
  insert into profil_sites values (adm, s), (resp, s), (tech, s), (pres, s), (pres2, s), (mag, s), (nouveau, s);
  insert into fiches(id, type, data, entreprise_id, site_id, auteur) values
    ('z-p-adm', 'personnes', '{"nom":"Adm R3","role":"pilote","actif":true}', ent, null, adm),
    ('z-p-resp', 'personnes', '{"nom":"Resp R3","role":"responsable","actif":true}', ent, null, adm),
    ('z-p-tech', 'personnes', '{"nom":"Tech R3","role":"technicien","actif":true}', ent, null, adm),
    ('z-p-pres', 'personnes', '{"nom":"Pres R3","role":"prestataire","actif":true,"societeId":"z-soc"}', ent, null, adm),
    ('z-p-pres2', 'personnes', '{"nom":"Pres2 R3","role":"prestataire","actif":true,"societeId":"z-soc2"}', ent, null, adm),
    ('z-p-mag', 'personnes', '{"nom":"Mag R3","role":"magasinier","actif":true}', ent, null, adm),
    ('z-p-auto', 'personnes', '{"nom":"nouveau","role":"technicien","actif":true}', ent, null, adm),
    ('z-p-libre', 'personnes', '{"nom":"Sous-traitant","role":"prestataire","actif":true,"societe":"Froid Sérvice "}', ent, null, adm),
    ('z-soc', 'fournisseurs', '{"nom":"Froid service","prestataire":true}', ent, null, adm),
    ('z-soc2', 'fournisseurs', '{"nom":"Elec Plus","prestataire":true}', ent, null, adm),
    ('z-four', 'fournisseurs', '{"nom":"Roulements SA"}', ent, null, adm),
    ('z-eq', 'equipements', '{"code":"R3-EQ","designation":"Groupe froid"}', ent, s, adm);

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=1; test:='technicien crée un membre (refus)';
  r := push_fiches('[{"id":"z-m1","type":"personnes","patch":{"id":"z-m1","nom":"X","role":"technicien"}}]'); return next;
  n:=2; test:='technicien change son téléphone (ok)';
  r := push_fiches('[{"id":"z-p-tech","type":"personnes","patch":{"telephone":"0600000000"}}]'); return next;
  n:=3; test:='technicien change son rôle (refus)';
  r := push_fiches('[{"id":"z-p-tech","type":"personnes","patch":{"role":"responsable"}}]'); return next;
  n:=6; test:='technicien crée une équipe (refus)';
  r := push_fiches('[{"id":"z-eqp2","type":"equipes","patch":{"id":"z-eqp2","nom":"Nuit"}}]'); return next;
  perform push_fiches('[{"id":"z-ot2","type":"ots","patch":{"id":"z-ot2","equipementId":"z-eq","statut":"en_cours"}}]');
  n:=14; test:='technicien confie une intervention à une équipe (refus)';
  r := push_fiches('[{"id":"z-ot2","type":"ots","patch":{"equipeId":"z-eqp"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=4; test:='responsable non admin crée un membre sans accès (ok)';
  r := push_fiches('[{"id":"z-m2","type":"personnes","patch":{"id":"z-m2","nom":"Youssef","role":"technicien","societeId":"z-soc","actif":true}}]'); return next;
  n:=7; test:='responsable change le rôle d''un membre avec accès (refus)';
  r := push_fiches('[{"id":"z-p-tech","type":"personnes","patch":{"role":"magasinier"}}]'); return next;
  q := push_fiches('[{"id":"z-p-tech","type":"personnes","patch":{"nom":"Tech Renommé"}}]');
  n:=8; test:='responsable renomme un membre avec accès : le compte suit';
  r := jsonb_build_object('acceptes', q->'acceptes', 'compte', (select nom from profils where user_id = tech)); return next;
  n:=11; test:='responsable crée une société prestataire (ok)';
  r := push_fiches('[{"id":"z-soc3","type":"fournisseurs","patch":{"id":"z-soc3","nom":"Hydro Maroc","prestataire":true}}]'); return next;
  perform push_fiches('[{"id":"z-ot1","type":"ots","patch":{"id":"z-ot1","equipementId":"z-eq","statut":"planifiee","societeId":"z-soc"}}]');
  n:=16; test:='relier_membre par un responsable non admin (refus)';
  begin perform relier_membre(nouveau, 'z-m2'); r := '"accepté"'; exception when others then r := to_jsonb(sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  n:=5; test:='administrateur (direction) crée une équipe (ok)';
  r := push_fiches('[{"id":"z-eqp","type":"equipes","patch":{"id":"z-eqp","nom":"Mécanique","chefId":"z-p-tech","membreIds":["z-p-tech","z-m2"]}}]'); return next;
  perform relier_membre(nouveau, 'z-m2');
  n:=17; test:='relier_membre par l''administrateur';
  r := jsonb_build_object('lien', (select personne_id from profils where user_id = nouveau), 'role', (select data->'role' from fiches where id = 'z-m2'),
        'compte', (select nom from profils where user_id = nouveau), 'ancienne', (select data->'actif' from fiches where id = 'z-p-auto')); return next;
  perform definir_profil(nouveau, 'technicien', null, false);
  n:=18; test:='retirer l''accès : membre toujours actif';
  r := jsonb_build_object('compte', (select actif from profils where user_id = nouveau), 'membre', (select data->'actif' from fiches where id = 'z-m2')); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=9; test:='magasinier crée une société prestataire (refus)';
  r := push_fiches('[{"id":"z-soc4","type":"fournisseurs","patch":{"id":"z-soc4","nom":"Autre","prestataire":true}}]'); return next;
  n:=10; test:='magasinier crée un fournisseur (ok)';
  r := push_fiches('[{"id":"z-four2","type":"fournisseurs","patch":{"id":"z-four2","nom":"Visserie"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', pres, 'role', 'authenticated')::text, true);
  q := jsonb_build_object('pres', (select prestataire_voit(type, id, data, auteur) from fiches where id = 'z-ot1'));
  perform set_config('request.jwt.claims', json_build_object('sub', pres2, 'role', 'authenticated')::text, true);
  n:=12; test:='intervention confiée à la société : vue par son prestataire seulement';
  r := q || jsonb_build_object('pres2', (select prestataire_voit(type, id, data, auteur) from fiches where id = 'z-ot1')); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', pres, 'role', 'authenticated')::text, true);
  n:=13; test:='prestataire s''ajoute comme intervenant (ok)';
  r := push_fiches('[{"id":"z-ot1","type":"ots","patch":{"statut":"en_cours","intervenants":[{"id":"i1","personneId":"z-p-pres","role":"intervenant"}]}}]'); return next;
  n:=15; test:='prestataire : sa société oui, autre fournisseur non';
  r := jsonb_build_object('soc', (select prestataire_voit(type, id, data, auteur) from fiches where id = 'z-soc'),
        'four', (select prestataire_voit(type, id, data, auteur) from fiches where id = 'z-four'),
        'soc2', (select prestataire_voit(type, id, data, auteur) from fiches where id = 'z-soc2')); return next;

  perform set_config('request.jwt.claims', '', true);
  perform r3_reprise();
  n:=19; test:='reprise : texte « societe » relié à la société existante';
  r := jsonb_build_object('societeId', (select data->'societeId' from fiches where id = 'z-p-libre'),
        'societes', (select count(*) from fiches where entreprise_id = ent and type = 'fournisseurs')); return next;
  n:=20; test:='fonctions ouvertes sans compte';
  r := (select coalesce(jsonb_agg(p.proname), '[]') from pg_proc p join pg_namespace x on x.oid = p.pronamespace
        where x.nspname = 'public' and p.proname <> 'gmao_test_r3' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')); return next;

  delete from fiches where entreprise_id = ent;
  delete from pf_limites where cle like '%' || ent::text;
  delete from profil_sites where user_id in (adm, resp, tech, pres, pres2, mag, nouveau);
  delete from profils where user_id in (adm, resp, tech, pres, pres2, mag, nouveau);
  delete from sites where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=21; test:='nettoyage'; r := jsonb_build_object('reste', (select count(*) from entreprises where code = 'R3TEST')); return next;
end $$;
revoke all on function public.gmao_test_r3() from public, anon, authenticated;   -- jamais appelable par l'API
select jsonb_object_agg(lpad(n::text, 2, '0') || ' ' || test, r order by n)::text as resultats from public.gmao_test_r3();
-- Puis, OBLIGATOIREMENT : drop function if exists public.gmao_test_r3();
