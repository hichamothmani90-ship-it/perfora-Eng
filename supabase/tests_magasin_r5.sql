-- Tests du lot R5 (achat urgent, qui commande). Supabase → SQL Editor, après magasin_r5.sql.
-- Entreprise fictive R5TEST, comptes fictifs. Nettoie ses données.
-- Attendu : 1 magasinier crée une demande urgente sans motif : refus ; 2 avec motif, liée à une pièce : ok ;
--  3 Achats commande la demande urgente encore soumise : ok ; 4 Achats commande une demande normale soumise : refus ;
--  5 magasinier commande une demande validée (réglage Achats) : refus ; 6 réglage « magasinier » : ok ;
--  7 magasinier glisse une validation dans la commande : refus ; 8 responsable valide après coup : ok ;
--  9 magasinier lie la pièce à la demande et la réserve : ok ; 10 aucune fonction ouverte sans compte ; 12 la pièce
--  reçoit le résumé de la commande (sans prix) ; 13 nettoyage.
create or replace function public.gmao_test_r5() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; s uuid;
  resp uuid := '00000000-0000-0000-0000-0000000000b1'; mag uuid := '00000000-0000-0000-0000-0000000000b2';
  ach uuid := '00000000-0000-0000-0000-0000000000b3';
begin
  insert into entreprises(code, nom) values ('R5TEST', 'R5 test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'R5', 'Site R5') returning id into s;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut, personne_id, admin_client) values
    (resp, 'resp@r5.test', 'Resp R5', 'responsable', ent, s, 'v-p-resp', true),
    (mag, 'mag@r5.test', 'Mag R5', 'magasinier', ent, s, 'v-p-mag', false),
    (ach, 'ach@r5.test', 'Ach R5', 'achats', ent, s, 'v-p-ach', false);
  insert into profil_sites values (resp, s), (mag, s), (ach, s);
  insert into fiches(id, type, data, entreprise_id, site_id, auteur) values
    ('v-eq', 'equipements', '{"code":"R5-EQ","designation":"Presse R5"}', ent, s, resp),
    ('v-art', 'articles', '{"ref":"6205","designation":"Roulement 6205","unite":"u"}', ent, null, resp),
    ('v-ot', 'ots', '{"equipementId":"v-eq","nature":"corrective","priorite":"critique_service","statut":"suspendue"}', ent, s, resp),
    ('v-b', 'besoins', '{"otId":"v-ot","articleId":"v-art","qte":2,"statut":"indisponible","urgent":true}', ent, s, resp),
    ('v-da2', 'achats', '{"ref":"DA-2","statut":"soumise","lignes":[{"id":"l2","articleId":"v-art","qte":1}]}', ent, s, mag),
    ('v-da3', 'achats', '{"ref":"DA-3","statut":"validee","valideLe":"2026-11-07","lignes":[{"id":"l3","articleId":"v-art","qte":1}]}', ent, s, mag);

  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=1; test:='demande urgente sans motif (refus)';
  r := push_fiches('[{"id":"v-da1","type":"achats","patch":{"id":"v-da1","ref":"DA-1","statut":"soumise","urgent":true,"lignes":[{"id":"l1","articleId":"v-art","qte":2,"besoinId":"v-b","otId":"v-ot"}]}}]'); return next;
  n:=2; test:='demande urgente avec motif, liée à la pièce (ok)';
  r := push_fiches('[{"id":"v-da1","type":"achats","patch":{"id":"v-da1","ref":"DA-1","statut":"soumise","urgent":true,"motifUrgence":"presse à l''arrêt","lignes":[{"id":"l1","articleId":"v-art","qte":2,"besoinId":"v-b","otId":"v-ot"}]}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', ach, 'role', 'authenticated')::text, true);
  n:=3; test:='Achats commande la demande urgente soumise (ok)';
  r := push_fiches('[{"id":"v-da1","type":"achats","patch":{"statut":"commandee","fournisseur":"Roulements SA","refCommande":"C-1","dateCommande":"2026-11-07","livraisonPrevue":"2026-11-09","commandeLe":"2026-11-07T09:00","commandePar":"Ach R5"}}]'); return next;
  n:=12; test:='la pièce reçoit le résumé de la commande, sans prix';
  r := (select data->'suiviAchat' from fiches where id = 'v-b'); return next;
  n:=4; test:='Achats commande une demande normale soumise (refus)';
  r := push_fiches('[{"id":"v-da2","type":"achats","patch":{"statut":"commandee","fournisseur":"X","refCommande":"C-2"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=5; test:='magasinier commande (réglage Achats) (refus)';
  r := push_fiches('[{"id":"v-da3","type":"achats","patch":{"statut":"commandee","fournisseur":"X","refCommande":"C-3"}}]'); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  perform push_fiches(('[{"id":"parametres-' || ent || '","type":"parametres","patch":{"id":"parametres-' || ent || '","quiCommande":"magasinier"}}]')::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=6; test:='magasinier commande (réglage magasinier) (ok)';
  r := push_fiches('[{"id":"v-da3","type":"achats","patch":{"statut":"commandee","fournisseur":"X","refCommande":"C-3","dateCommande":"2026-11-07"}}]'); return next;
  n:=7; test:='magasinier glisse une validation dans la commande (refus)';
  r := push_fiches('[{"id":"v-da2","type":"achats","patch":{"statut":"commandee","refCommande":"C-2","valideLe":"2026-11-07"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=8; test:='responsable valide après coup (ok)';
  r := push_fiches('[{"id":"v-da1","type":"achats","patch":{"valideLe":"2026-11-07T10:00","validePar":"Resp R5","valideApresCoup":true}}]')
       || jsonb_build_object('statut', (select data->>'statut' from fiches where id = 'v-da1')); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', mag, 'role', 'authenticated')::text, true);
  n:=9; test:='magasinier lie la pièce et la réserve (ok)';
  r := push_fiches('[{"id":"v-b","type":"besoins","patch":{"achatId":"v-da1","ligneId":"l1","qteReservee":2,"statut":"reserve"}}]'); return next;

  perform set_config('request.jwt.claims', '', true);
  n:=10; test:='fonctions ouvertes sans compte';
  r := (select coalesce(jsonb_agg(p.proname), '[]') from pg_proc p join pg_namespace x on x.oid = p.pronamespace
        where x.nspname = 'public' and p.proname <> 'gmao_test_r5' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')); return next;

  delete from fiches where entreprise_id = ent;
  delete from pf_limites where cle like '%' || ent::text;
  delete from profil_sites where user_id in (resp, mag, ach);
  delete from profils where user_id in (resp, mag, ach);
  delete from sites where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=13; test:='nettoyage'; r := jsonb_build_object('reste', (select count(*) from entreprises where code = 'R5TEST')); return next;
end $$;
revoke all on function public.gmao_test_r5() from public, anon, authenticated;   -- jamais appelable par l'API
select jsonb_object_agg(lpad(n::text, 2, '0') || ' ' || test, r order by n)::text as resultats from public.gmao_test_r5();
-- Puis, OBLIGATOIREMENT : drop function if exists public.gmao_test_r5();
