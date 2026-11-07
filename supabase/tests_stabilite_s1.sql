-- Tests du lot S1 de stabilisation (fusion des listes, version minimale). Supabase → SQL Editor, après stabilite_s1.sql.
-- Entreprise fictive S1TEST, comptes fictifs. Nettoie ses données et remet la version minimale à sa valeur d'origine.
-- Attendu : 1 deux appareils ajoutent chacun un intervenant : les deux restent ; 2 même élément modifié des deux côtés :
--  le dernier gagne, l'autre élément reste ; 3 retrait d'un élément par un appareil pendant qu'un autre en ajoute un :
--  retiré, l'ajout reste ; 4 liste de valeurs (activités) : ajouts des deux côtés, retrait appliqué ; 5 liste sans
--  identifiant : remplacée comme avant ; 6 « $listes » jamais enregistré ; 7 ancienne appli (liste complète sans
--  description) : ajout, rien de perdu ; 8 appel API d'une version trop ancienne : refusé ; 9 sans version : refusé ;
--  10 version à jour : accepté ; 11 appel hors API (SQL Editor) : accepté ; 12 aucune fonction ouverte sans compte ;
--  13 nettoyage.
create or replace function public.gmao_test_s1() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; s uuid; mini text := (select valeur from pf_reglages where cle = 'version_minimale');
  resp uuid := '00000000-0000-0000-0000-0000000000a1'; tech uuid := '00000000-0000-0000-0000-0000000000a2';
  q jsonb;
begin
  insert into entreprises(code, nom) values ('S1TEST', 'S1 test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'S1', 'Site S1') returning id into s;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut, personne_id, admin_client) values
    (resp, 'resp@s1.test', 'Resp S1', 'responsable', ent, s, 'w-p-resp', true),
    (tech, 'tech@s1.test', 'Tech S1', 'technicien', ent, s, 'w-p-tech', false);
  insert into profil_sites values (resp, s), (tech, s);
  insert into fiches(id, type, data, entreprise_id, site_id, auteur) values
    ('w-eq', 'equipements', '{"code":"S1-EQ","designation":"Presse S1"}', ent, s, resp),
    ('w-ot', 'ots', '{"equipementId":"w-eq","nature":"corrective","priorite":"rapide","statut":"en_cours","intervenants":[],"activites":["diagnostic"],"mesures":[{"v":1}]}', ent, s, resp);

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"w-ot","type":"ots","patch":{"intervenants":[{"id":"i1","personneId":"w-p-tech"}],"activites":["diagnostic","reglage"],"$listes":{"intervenants":{"modifies":["i1"]},"activites":{"modifies":["reglage"]}}}}]');
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"w-ot","type":"ots","patch":{"intervenants":[{"id":"i2","personneId":"w-p-resp"}],"activites":["diagnostic","essai"],"$listes":{"intervenants":{"modifies":["i2"]},"activites":{"modifies":["essai"]}}}}]');
  n:=1; test:='deux ajouts simultanés : les deux restent';
  r := (select jsonb_build_object('intervenants', (select jsonb_agg(x->>'id') from jsonb_array_elements(data->'intervenants') x), 'activites', data->'activites') from fiches where id = 'w-ot'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"w-ot","type":"ots","patch":{"intervenants":[{"id":"i1","personneId":"w-p-tech","fin":"2026-11-07T10:00"}],"$listes":{"intervenants":{"modifies":["i1"]}}}}]');
  n:=2; test:='même élément modifié : le dernier gagne, l''autre reste';
  r := (select jsonb_agg(jsonb_build_object('id', x->>'id', 'fin', x->'fin')) from fiches, jsonb_array_elements(data->'intervenants') x where id = 'w-ot'); return next;

  perform push_fiches('[{"id":"w-ot","type":"ots","patch":{"intervenants":[{"id":"i2","personneId":"w-p-resp"}],"$listes":{"intervenants":{"modifies":[],"retraits":["i1"]}}}}]');
  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"w-ot","type":"ots","patch":{"intervenants":[{"id":"i1","personneId":"w-p-tech","fin":"2026-11-07T10:00"},{"id":"i2","personneId":"w-p-resp"},{"id":"i3","personneId":"w-p-resp"}],"$listes":{"intervenants":{"modifies":["i3"]}}}}]');
  n:=3; test:='retrait par un appareil, ajout par l''autre';
  r := (select jsonb_agg(x->>'id') from fiches, jsonb_array_elements(data->'intervenants') x where id = 'w-ot'); return next;

  perform push_fiches('[{"id":"w-ot","type":"ots","patch":{"activites":["reglage","essai","nettoyage"],"$listes":{"activites":{"modifies":["nettoyage"],"retraits":["diagnostic"]}}}}]');
  n:=4; test:='liste de valeurs : ajouts gardés, retrait appliqué';
  r := (select data->'activites' from fiches where id = 'w-ot'); return next;

  perform push_fiches('[{"id":"w-ot","type":"ots","patch":{"mesures":[{"v":2}]}}]');
  n:=5; test:='liste sans identifiant : remplacée';
  r := (select data->'mesures' from fiches where id = 'w-ot'); return next;
  perform push_fiches('[{"id":"w-ot2","type":"ots","patch":{"id":"w-ot2","equipementId":"w-eq","statut":"en_cours","intervenants":[],"$listes":{"intervenants":{"retraits":["x"]}}}}]');
  n:=6; test:='« $listes » jamais enregistré';
  r := (select jsonb_build_object('ot', data ? '$listes', 'ot2', (select data ? '$listes' from fiches where id = 'w-ot2')) from fiches where id = 'w-ot'); return next;
  perform push_fiches('[{"id":"w-ot","type":"ots","patch":{"intervenants":[{"id":"i9","personneId":"w-p-resp"}]}}]');
  n:=7; test:='ancienne appli (liste complète, sans description) : ajout sans rien perdre';
  r := (select jsonb_agg(x->>'id') from fiches, jsonb_array_elements(data->'intervenants') x where id = 'w-ot'); return next;

  update pf_reglages set valeur = 'v39' where cle = 'version_minimale';
  perform set_config('request.method', 'POST', true);
  n:=8; test:='appel API, version trop ancienne (refus)';
  begin q := push_fiches('[{"id":"w-ot","type":"ots","patch":{"travaux":"a"}}]', 'v38'); r := q; exception when others then r := to_jsonb(sqlerrm); end; return next;
  n:=9; test:='appel API sans version (refus)';
  begin q := push_fiches('[{"id":"w-ot","type":"ots","patch":{"travaux":"b"}}]'); r := q; exception when others then r := to_jsonb(left(sqlerrm, 60)); end; return next;
  n:=10; test:='appel API, version à jour (ok)';
  r := push_fiches('[{"id":"w-ot","type":"ots","patch":{"travaux":"c"}}]', 'v39'); return next;
  perform set_config('request.method', '', true);
  n:=11; test:='appel hors API (ok)';
  r := push_fiches('[{"id":"w-ot","type":"ots","patch":{"travaux":"d"}}]'); return next;
  update pf_reglages set valeur = mini where cle = 'version_minimale';

  perform set_config('request.jwt.claims', '', true);
  n:=12; test:='fonctions ouvertes sans compte';
  r := (select coalesce(jsonb_agg(p.proname), '[]') from pg_proc p join pg_namespace x on x.oid = p.pronamespace
        where x.nspname = 'public' and p.proname <> 'gmao_test_s1' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')); return next;

  delete from fiches where entreprise_id = ent;
  delete from pf_limites where cle like '%' || ent::text;
  delete from profil_sites where user_id in (resp, tech);
  delete from profils where user_id in (resp, tech);
  delete from sites where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=13; test:='nettoyage';
  r := jsonb_build_object('reste', (select count(*) from entreprises where code = 'S1TEST'), 'version_minimale', (select valeur from pf_reglages where cle = 'version_minimale')); return next;
end $$;
revoke all on function public.gmao_test_s1() from public, anon, authenticated;   -- jamais appelable par l'API
select jsonb_object_agg(lpad(n::text, 2, '0') || ' ' || test, r order by n)::text as resultats from public.gmao_test_s1();
-- Puis, OBLIGATOIREMENT : drop function if exists public.gmao_test_s1();
