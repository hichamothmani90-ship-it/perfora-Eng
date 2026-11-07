-- Tests du lot R1 (droits par rôle). Supabase → SQL Editor, après roles_r1.sql. Entreprise fictive R1TEST, comptes
-- fictifs ; vraie règle de lecture (set local role authenticated). Nettoie ses données (le journal des actions de la
-- plateforme garde la trace, c'est voulu).
-- Attendu : 1 prestataire lit : interventions [x-ot1], demande liée 1, pièces 0, équipements 1, articles 1, achats 0 ;
--  2 prestataire modifie une intervention qui ne lui est pas confiée : refus ; 3 la sienne : ok ; 4 crée une intervention :
--  refus ; 5 signale (demande) : ok ; 6 pièce sur une intervention d'un autre : refus ; 7 journal lu par le technicien :
--  [x-j1] ; 8 par le prestataire : [x-j2] ; 9 par le responsable : 3 lignes ; 10 responsable sans droit admin invite :
--  refus ; 11 administrateur invite : ok ; 12 mon_profil.adminClient : true ; 13 l'admin donne le droit à resp2 : ok ;
--  14 retirer le dernier administrateur : refus ; 15 aucune fonction ouverte sans compte ; 16 nettoyage.
create or replace function public.gmao_test_r1() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; s uuid;
  resp uuid := '00000000-0000-0000-0000-0000000000d1'; resp2 uuid := '00000000-0000-0000-0000-0000000000d2';
  tech uuid := '00000000-0000-0000-0000-0000000000d3'; presta uuid := '00000000-0000-0000-0000-0000000000d4';
begin
  insert into entreprises(code, nom) values ('R1TEST', 'R1 test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'R1', 'Site R1') returning id into s;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut, personne_id, admin_client) values
    (resp, 'resp@r1.test', 'Resp R1', 'responsable', ent, s, 'x-pers-resp', true),
    (resp2, 'resp2@r1.test', 'Resp2 R1', 'responsable', ent, s, 'x-pers-resp2', false),
    (tech, 'tech@r1.test', 'Tech R1', 'technicien', ent, s, 'x-pers-tech', false),
    (presta, 'presta@r1.test', 'Presta R1', 'prestataire', ent, s, 'x-pers-presta', false);
  insert into profil_sites values (resp, s), (resp2, s), (tech, s), (presta, s);
  insert into fiches(id, type, data, entreprise_id, site_id, auteur) values
    ('x-pers-tech', 'personnes', '{"nom":"Tech R1"}', ent, null, resp),
    ('x-pers-presta', 'personnes', '{"nom":"Presta R1"}', ent, null, resp),
    ('x-eq1', 'equipements', '{"code":"R1-EQ","designation":"Pompe R1"}', ent, s, resp),
    ('x-d1', 'demandes', '{"equipementId":"x-eq1","constat":"fuite"}', ent, s, tech),
    ('x-ot1', 'ots', '{"equipementId":"x-eq1","demandeIds":["x-d1"],"statut":"planifiee","intervenants":[{"id":"i1","personneId":"x-pers-presta","role":"prestataire","fin":null}]}', ent, s, resp),
    ('x-ot2', 'ots', '{"equipementId":"x-eq1","statut":"en_cours","intervenants":[{"id":"i2","personneId":"x-pers-tech","role":"intervenant","fin":null}]}', ent, s, resp),
    ('x-b1', 'besoins', '{"otId":"x-ot2","qte":1,"statut":"demande"}', ent, s, tech),
    ('x-a1', 'articles', '{"ref":"R1-ART","designation":"Joint"}', ent, null, resp),
    ('x-da1', 'achats', '{"ref":"DA-R1","statut":"brouillon"}', ent, s, resp),
    ('x-j1', 'journal', '{"entite":"ots","entiteId":"x-ot2","champ":"travaux"}', ent, s, resp),
    ('x-j2', 'journal', '{"entite":"ots","entiteId":"x-ot1","champ":"creneau"}', ent, s, resp),
    ('x-j3', 'journal', '{"entite":"personnes","entiteId":"x-pers-tech","champ":"role"}', ent, null, resp);

  -- prestataire : lecture
  perform set_config('request.jwt.claims', json_build_object('sub', presta, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=1; test:='prestataire lit'; r := jsonb_build_object(
    'interventions', (select coalesce(jsonb_agg(id order by id), '[]') from fiches where type = 'ots' and id like 'x-%'),
    'demandes', (select count(*) from fiches where type = 'demandes' and id like 'x-%'),
    'pieces', (select count(*) from fiches where type = 'besoins' and id like 'x-%'),
    'equipements', (select count(*) from fiches where type = 'equipements' and id like 'x-%'),
    'articles', (select count(*) from fiches where type = 'articles' and id like 'x-%'),
    'achats', (select count(*) from fiches where type = 'achats' and id like 'x-%')); return next;
  n:=8; test:='journal lu par le prestataire'; r := (select coalesce(jsonb_agg(id order by id), '[]') from fiches where type = 'journal' and id like 'x-j%'); return next;
  reset role;
  -- prestataire : écriture
  n:=2; test:='prestataire modifie l''intervention d''un autre (refus)'; r := push_fiches('[{"id":"x-ot2","type":"ots","patch":{"travaux":"pirate"}}]'); return next;
  n:=3; test:='prestataire modifie la sienne (ok)'; r := push_fiches('[{"id":"x-ot1","type":"ots","patch":{"travaux":"vidange faite"}}]'); return next;
  n:=4; test:='prestataire crée une intervention (refus)'; r := push_fiches('[{"id":"x-ot3","type":"ots","patch":{"id":"x-ot3","equipementId":"x-eq1","statut":"en_cours"}}]'); return next;
  n:=5; test:='prestataire signale (ok)'; r := push_fiches('[{"id":"x-d2","type":"demandes","patch":{"id":"x-d2","equipementId":"x-eq1","constat":"bruit"}}]'); return next;
  n:=6; test:='prestataire demande une pièce pour l''intervention d''un autre (refus)'; r := push_fiches('[{"id":"x-b2","type":"besoins","patch":{"id":"x-b2","otId":"x-ot2","qte":1,"statut":"demande"}}]'); return next;

  -- journal par rôle
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=7; test:='journal lu par le technicien'; r := (select coalesce(jsonb_agg(id order by id), '[]') from fiches where type = 'journal' and id like 'x-j%'); return next;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  set local role authenticated;
  n:=9; test:='journal lu par le responsable'; r := jsonb_build_object('lignes', (select count(*) from fiches where type = 'journal' and id like 'x-j%')); return next;
  reset role;

  -- administrateur de l'entreprise
  perform set_config('request.jwt.claims', json_build_object('sub', resp2, 'role', 'authenticated')::text, true);
  n:=10; test:='responsable sans droit admin invite (refus)';
  begin r := preparer_invitation('nouveau@r1.test', 'technicien', array[s]); exception when others then r := jsonb_build_object('refus', sqlerrm); end; return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=11; test:='administrateur invite (ok)';
  begin r := preparer_invitation('nouveau@r1.test', 'technicien', array[s]); r := jsonb_build_object('ok', r ? 'entreprise_id'); exception when others then r := jsonb_build_object('refus', sqlerrm); end; return next;
  n:=12; test:='mon_profil.adminClient'; r := jsonb_build_object('adminClient', mon_profil()->'adminClient'); return next;
  n:=13; test:='l''admin donne le droit à resp2'; perform definir_admin_client(resp2, true);
  r := jsonb_build_object('resp2_admin', (select admin_client from profils where user_id = resp2)); return next;
  perform definir_admin_client(resp2, false);
  n:=14; test:='retirer le dernier administrateur (refus)';
  begin perform definir_admin_client(resp, false); r := '{"retire":"ANOMALIE"}'; exception when others then r := jsonb_build_object('refus', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', '', true);
  n:=15; test:='fonctions ouvertes sans compte';
  r := (select coalesce(jsonb_agg(p.proname), '[]') from pg_proc p join pg_namespace x on x.oid = p.pronamespace
        where x.nspname = 'public' and p.proname <> 'gmao_test_r1' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')); return next;

  delete from fiches where entreprise_id = ent;
  delete from pf_limites where cle like '%' || ent::text;
  delete from profil_sites where user_id in (resp, resp2, tech, presta);
  delete from profils where user_id in (resp, resp2, tech, presta);
  delete from sites where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=16; test:='nettoyage'; r := jsonb_build_object('reste', (select count(*) from entreprises where code = 'R1TEST')); return next;
end $$;
revoke all on function public.gmao_test_r1() from public, anon, authenticated;   -- jamais appelable par l'API
select jsonb_object_agg(n::text || ' ' || test, r order by n)::text as resultats from public.gmao_test_r1();
-- Puis, OBLIGATOIREMENT : drop function if exists public.gmao_test_r1();
