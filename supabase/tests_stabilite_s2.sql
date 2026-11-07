-- Tests du lot S2 de stabilisation (contenu, liens, code appareil). Supabase → SQL Editor, après push_fiches.sql.
-- Entreprise fictive S2TEST, comptes fictifs. Nettoie ses données. (L'import renuméroté est éprouvé par
-- scripts/sauvegarde/tester_curseur.sh et tests_mise_en_service.sql.)
-- Attendu : 1 statut d'intervention inconnu : refus ; 2 nature inconnue : refus ; 3 quantité en texte : refus ;
--  4 date mal formée : refus ; 5 pièce vers une intervention inconnue : refus ; 6 mouvement vers un article inconnu :
--  refus ; 7 intervention confiée à une équipe inconnue : refus ; 8 intervention et sa pièce dans le même envoi : ok ;
--  9 appareil A garde « K3 » ; 10 appareil B qui demande « K3 » reçoit un autre code ; 11 A et B redemandent : mêmes
--  codes ; 12 rapport des fiches anormales hors administrateur plateforme : refus ; 13 aucune fonction ouverte sans
--  compte ; 14 nettoyage.
create or replace function public.gmao_test_s2() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; s uuid; cb text;
  resp uuid := '00000000-0000-0000-0000-0000000000c1'; tech uuid := '00000000-0000-0000-0000-0000000000c2';
begin
  insert into entreprises(code, nom) values ('S2TEST', 'S2 test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'S2', 'Site S2') returning id into s;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut, personne_id, admin_client) values
    (resp, 'resp@s2.test', 'Resp S2', 'responsable', ent, s, 'u-p-resp', true),
    (tech, 'tech@s2.test', 'Tech S2', 'technicien', ent, s, 'u-p-tech', false);
  insert into profil_sites values (resp, s), (tech, s);
  insert into fiches(id, type, data, entreprise_id, site_id, auteur) values
    ('u-eq', 'equipements', '{"code":"S2-EQ","designation":"Presse S2"}', ent, s, resp),
    ('u-art', 'articles', '{"ref":"6205","designation":"Roulement","unite":"u"}', ent, null, resp),
    ('u-ot', 'ots', '{"equipementId":"u-eq","nature":"corrective","priorite":"rapide","statut":"en_cours"}', ent, s, resp);

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=1; test:='statut d''intervention inconnu (refus)';
  r := push_fiches('[{"id":"u-ot","type":"ots","patch":{"statut":"terminee_bis"}}]'); return next;
  n:=2; test:='nature inconnue (refus)';
  r := push_fiches('[{"id":"u-ot","type":"ots","patch":{"nature":"curative"}}]'); return next;
  n:=3; test:='quantité en texte (refus)';
  r := push_fiches('[{"id":"u-b1","type":"besoins","patch":{"id":"u-b1","otId":"u-ot","articleId":"u-art","qte":"deux"}}]'); return next;
  n:=4; test:='date mal formée (refus)';
  r := push_fiches('[{"id":"u-ot","type":"ots","patch":{"arretDebut":"07/11/2026 08:00"}}]'); return next;
  n:=5; test:='pièce vers une intervention inconnue (refus)';
  r := push_fiches('[{"id":"u-b2","type":"besoins","patch":{"id":"u-b2","otId":"u-inconnue","articleId":"u-art","qte":1}}]'); return next;
  n:=6; test:='mouvement vers un article inconnu (refus)';
  r := push_fiches('[{"id":"u-m1","type":"mouvements","patch":{"id":"u-m1","type":"entree","articleId":"u-fantome","qte":2}}]'); return next;
  n:=7; test:='intervention confiée à une équipe inconnue (refus)';
  r := push_fiches('[{"id":"u-ot","type":"ots","patch":{"equipeId":"u-equipe-fantome"}}]'); return next;
  n:=8; test:='intervention et sa pièce dans le même envoi (ok)';
  r := push_fiches('[{"id":"u-ot2","type":"ots","patch":{"id":"u-ot2","equipementId":"u-eq","statut":"en_cours","nature":"corrective"}},{"id":"u-b3","type":"besoins","patch":{"id":"u-b3","otId":"u-ot2","articleId":"u-art","qte":1,"statut":"demande"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=9; test:='appareil A garde K3'; r := to_jsonb(appareil_code('K3', 'app-A')); return next;
  cb := appareil_code('K3', 'app-B');
  n:=10; test:='appareil B qui demande K3 reçoit un autre code'; r := jsonb_build_object('different', cb <> 'K3', 'forme', cb ~ '^[A-Z0-9]{2,3}$'); return next;
  n:=11; test:='A et B redemandent : mêmes codes';
  r := jsonb_build_object('A', appareil_code('ZZ', 'app-A'), 'B_identique', appareil_code(null, 'app-B') = cb); return next;
  n:=12; test:='rapport des fiches anormales hors administrateur plateforme (refus)';
  begin r := pf_fiches_anormales(); exception when others then r := to_jsonb(sqlerrm); end; return next;

  perform set_config('request.jwt.claims', '', true);
  n:=13; test:='fonctions ouvertes sans compte';
  r := (select coalesce(jsonb_agg(p.proname), '[]') from pg_proc p join pg_namespace x on x.oid = p.pronamespace
        where x.nspname = 'public' and p.proname <> 'gmao_test_s2' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')); return next;

  delete from fiches where entreprise_id = ent;
  delete from pf_appareils where entreprise_id = ent;
  delete from pf_limites where cle like '%' || ent::text;
  delete from profil_sites where user_id in (resp, tech);
  delete from profils where user_id in (resp, tech);
  delete from sites where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=14; test:='nettoyage'; r := jsonb_build_object('reste', (select count(*) from entreprises where code = 'S2TEST')); return next;
end $$;
revoke all on function public.gmao_test_s2() from public, anon, authenticated;   -- jamais appelable par l'API
select jsonb_object_agg(lpad(n::text, 2, '0') || ' ' || test, r order by n)::text as resultats from public.gmao_test_s2();
-- Puis, OBLIGATOIREMENT : drop function if exists public.gmao_test_s2();
