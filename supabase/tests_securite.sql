-- Tests de l'étape 6 « sécurité ». Supabase → SQL Editor, après securite.sql. Ne touche pas aux vrais comptes :
-- entreprise fictive STEST, administrateur fictif (MFA obligatoire), technicien fictif. Nettoie ses données (les lignes
-- du journal restent : il ne s'efface pas, c'est voulu ; elles portent l'entreprise STEST).
-- Attendu : 1 admin MFA en session simple : est_admin false, pf_clients refusé ; 2 même admin en session aal2 : true,
--  pf_clients lisible ; 3 mon_profil en session simple : adminPlateforme false, adminMfa obligatoire / aal1 ;
--  4 pf_mfa_activer sans code (aal1) : erreur ; 5 avec code (aal2) : obligatoire true ;
--  6 journal : création d'entreprise par pf_creer_entreprise → ligne avec fonction, acteur, niveau aal2 ;
--  7 journal non modifiable : erreur ; 8 journal non effaçable : erreur ; 9 technicien lit le journal : erreur ;
--  10 support : 5 demandes acceptées, la 6e refusée (limite horaire) ; 11 erreurs : même message deux fois → 1 ligne, nb 2,
--  message tronqué à 300 ; 12 technicien lit les erreurs : erreur ; lecture directe des tables : 0 ligne ;
--  13 aucune fonction ouverte sans compte ; 14 nettoyage sans STEST.
create or replace function public.gmao_test_securite() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; site uuid; adm uuid := '00000000-0000-0000-0000-0000000000a6'; tech uuid := '00000000-0000-0000-0000-0000000000f6';
  x jsonb; i int; nouv jsonb; jid bigint;
begin
  insert into entreprises(code, nom) values ('STEST', 'Sécurité test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'essentiel');
  insert into sites(entreprise_id, code, nom) values (ent, 'S6', 'Site S6') returning id into site;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values
    (adm, 'admin@s.test', 'Admin S', 'responsable', ent, site), (tech, 'tech@s.test', 'Tech S', 'technicien', ent, site);
  insert into profil_sites values (tech, site), (adm, site);
  insert into admins_plateforme(user_id, mfa_obligatoire) values (adm, true);

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  n:=1; test:='admin MFA, session simple';
  begin x := pf_clients(); r := jsonb_build_object('est_admin', est_admin_plateforme(), 'pf_clients', 'lisible (ANOMALIE)');
  exception when others then r := jsonb_build_object('est_admin', est_admin_plateforme(), 'pf_clients', sqlerrm); end; return next;
  n:=3; test:='mon_profil en session simple'; x := mon_profil();
  r := jsonb_build_object('adminPlateforme', x->'adminPlateforme', 'adminMfa', x->'adminMfa'); return next;
  n:=4; test:='pf_mfa_activer sans code (erreur)';
  begin r := pf_mfa_activer(); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  n:=2; test:='admin MFA, session aal2'; x := pf_clients();
  r := jsonb_build_object('est_admin', est_admin_plateforme(), 'pf_clients', jsonb_typeof(x)); return next;
  n:=5; test:='pf_mfa_activer avec code'; r := pf_mfa_activer(); return next;
  n:=6; test:='journal : creation d''entreprise';
  select max(id) into jid from pf_journal_admin;
  nouv := pf_creer_entreprise('STEST2', 'Sécurité test 2', 'essentiel', 'essai', 'S7', 'Site S7', false);
  r := (select jsonb_build_object('lignes', count(*), 'fonction', min(fonction), 'acteur_ok', bool_and(acteur = adm), 'niveau', min(niveau),
          'tables', jsonb_agg(distinct table_nom)) from pf_journal_admin where id > jid and table_nom in ('entreprises', 'abonnements', 'sites')); return next;
  n:=7; test:='journal non modifiable (erreur)';
  begin update pf_journal_admin set operation = 'X' where id = (select max(id) from pf_journal_admin); r := '{"modifie":"ANOMALIE"}';
  exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=8; test:='journal non effaçable (erreur)';
  begin delete from pf_journal_admin where id = (select max(id) from pf_journal_admin); r := '{"efface":"ANOMALIE"}';
  exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=9; test:='technicien lit le journal (erreur)';
  begin r := pf_journal_admin_lire(10, null, null); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=10; test:='support : limite horaire';
  for i in 1..5 loop x := support_creer('question', 'Test limite ' || i, 'Message ' || i); end loop;
  begin x := support_creer('question', 'Test limite 6', 'Message 6'); r := jsonb_build_object('sixieme', 'acceptée (ANOMALIE)');
  exception when others then r := jsonb_build_object('sixieme', sqlerrm); end;
  r := r || jsonb_build_object('acceptees', (select count(*) from pf_objets where entreprise_id = ent and type = 'ticket')); return next;
  n:=11; test:='erreurs regroupées';
  perform erreurs_signaler(jsonb_build_array(jsonb_build_object('nature', 'erreur', 'message', 'Échec test ' || repeat('x', 400), 'page', '#/ot/1', 'version', 'v35')));
  perform erreurs_signaler(jsonb_build_array(jsonb_build_object('nature', 'erreur', 'message', 'Échec test ' || repeat('x', 400), 'page', '#/ot/2', 'version', 'v35')));
  r := (select jsonb_build_object('lignes', count(*), 'nb', max(nb), 'longueur', max(length(message)), 'page', max(page))
        from pf_erreurs where user_id = tech); return next;
  n:=12; test:='technicien lit les erreurs (erreur) ; tables directes';
  begin x := pf_erreurs_lire(7); r := '{"lu":"ANOMALIE"}'; exception when others then r := jsonb_build_object('erreur', sqlerrm); end;
  r := r || jsonb_build_object('droit_select_tables', has_table_privilege('authenticated', 'public.pf_erreurs', 'select') or has_table_privilege('authenticated', 'public.pf_journal_admin', 'select')
          or has_table_privilege('authenticated', 'public.pf_limites', 'select'));
  return next;

  perform set_config('request.jwt.claims', '', true);
  n:=13; test:='fonctions ouvertes sans compte';
  r := (select coalesce(jsonb_agg(p.proname), '[]') from pg_proc p join pg_namespace s on s.oid = p.pronamespace
        where s.nspname = 'public' and p.proname <> 'gmao_test_securite' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')); return next;

  -- nettoyage (le journal garde la trace des tests)
  delete from pf_objets where entreprise_id = ent;
  delete from fiches where entreprise_id in (select id from entreprises where code in ('STEST', 'STEST2'));
  delete from pf_erreurs where user_id = tech;
  delete from pf_limites where cle like '%' || tech::text or cle like '%' || ent::text;
  delete from admins_plateforme where user_id = adm;
  delete from profil_sites where user_id in (adm, tech);
  delete from profils where user_id in (adm, tech);
  delete from sites where entreprise_id in (select id from entreprises where code in ('STEST', 'STEST2'));
  delete from abonnements where entreprise_id in (select id from entreprises where code in ('STEST', 'STEST2'));
  delete from entreprises where code in ('STEST', 'STEST2');
  n:=14; test:='nettoyage'; r := jsonb_build_object('reste', (select count(*) from entreprises where code like 'STEST%')); return next;
end $$;
revoke all on function public.gmao_test_securite() from public, anon, authenticated;
select jsonb_object_agg(n::text || ' ' || test, r order by n)::text as resultats from public.gmao_test_securite();
-- Puis, OBLIGATOIREMENT : drop function if exists public.gmao_test_securite();
