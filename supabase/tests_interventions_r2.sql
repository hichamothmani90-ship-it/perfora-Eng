-- Tests du lot R2 (qualification proposée / validée, arrêt non planifié). Supabase → SQL Editor, après
-- interventions_r2.sql. Entreprise fictive R2TEST, comptes fictifs. Nettoie ses données.
-- Attendu : 1 technicien crée une intervention « corrective · critique » : rangée en proposée (nature a_qualifier,
--  natureProposee corrective, qualificationValidee false) ; 2 technicien change la nature d'une intervention non validée :
--  proposée ; 3 technicien valide lui-même : refus ; 4 responsable valide : ok (nature corrective, validée) ;
--  5 technicien change ensuite la nature : refus ; 6 préventif lancé depuis un programme : nature gardée ;
--  7 terminer un arrêt non planifié sans fin : refus ; 8 avec « heures inconnues » : ok ; 9 avec fin d'arrêt : ok ;
--  10 arrêt planifié sans fin : ok ; 11 ancienne intervention (sans arretType) sans fin : acceptée (contrôle appli) ;
--  12 aucune fonction ouverte sans compte ; 13 nettoyage.
create or replace function public.gmao_test_r2() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; s uuid;
  resp uuid := '00000000-0000-0000-0000-0000000000e1'; tech uuid := '00000000-0000-0000-0000-0000000000e3';
  q jsonb;
begin
  insert into entreprises(code, nom) values ('R2TEST', 'R2 test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'entreprise');
  insert into sites(entreprise_id, code, nom) values (ent, 'R2', 'Site R2') returning id into s;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut, personne_id, admin_client) values
    (resp, 'resp@r2.test', 'Resp R2', 'responsable', ent, s, 'y-pers-resp', true),
    (tech, 'tech@r2.test', 'Tech R2', 'technicien', ent, s, 'y-pers-tech', false);
  insert into profil_sites values (resp, s), (tech, s);
  insert into fiches(id, type, data, entreprise_id, site_id, auteur) values
    ('y-eq1', 'equipements', '{"code":"R2-EQ","designation":"Presse R2"}', ent, s, resp),
    ('y-prog', 'programmes', '{"equipementId":"y-eq1","libelle":"Graissage"}', ent, s, resp),
    ('y-old', 'ots', '{"equipementId":"y-eq1","nature":"corrective","statut":"en_cours","avecArret":"oui","resultat":"resolu"}', ent, s, resp);

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  perform push_fiches('[{"id":"y-ot1","type":"ots","patch":{"id":"y-ot1","equipementId":"y-eq1","nature":"corrective","priorite":"critique_service","statut":"en_cours"}}]');
  n:=1; test:='technicien crée : qualification proposée';
  r := (select jsonb_build_object('nature', data->'nature', 'priorite', data->'priorite', 'natureProposee', data->'natureProposee',
        'prioriteProposee', data->'prioriteProposee', 'validee', data->'qualificationValidee') from fiches where id = 'y-ot1'); return next;
  perform push_fiches('[{"id":"y-ot1","type":"ots","patch":{"nature":"assistance_production"}}]');
  n:=2; test:='technicien change la nature (non validée) : proposée';
  r := (select jsonb_build_object('nature', data->'nature', 'natureProposee', data->'natureProposee') from fiches where id = 'y-ot1'); return next;
  n:=3; test:='technicien valide lui-même (refus)';
  r := push_fiches('[{"id":"y-ot1","type":"ots","patch":{"qualificationValidee":true,"qualifieePar":"Tech R2"}}]'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  q := push_fiches('[{"id":"y-ot1","type":"ots","patch":{"nature":"corrective","priorite":"critique_service","qualificationValidee":true,"qualifieePar":"Resp R2","qualifieeLe":"2026-11-07T10:00"}}]');
  n:=4; test:='responsable valide';
  r := (select jsonb_build_object('acceptes', q->'acceptes', 'nature', data->'nature', 'validee', data->'qualificationValidee') from fiches where id = 'y-ot1'); return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=5; test:='technicien change une qualification validée (refus)';
  r := push_fiches('[{"id":"y-ot1","type":"ots","patch":{"nature":"preventive"}}]'); return next;
  perform push_fiches('[{"id":"y-ot2","type":"ots","patch":{"id":"y-ot2","equipementId":"y-eq1","programmeId":"y-prog","nature":"preventive","priorite":"planifiable","statut":"a_planifier"}}]');
  n:=6; test:='préventif lancé depuis un programme : nature gardée';
  r := (select jsonb_build_object('nature', data->'nature', 'validee', data->'qualificationValidee') from fiches where id = 'y-ot2'); return next;

  perform push_fiches('[{"id":"y-ot3","type":"ots","patch":{"id":"y-ot3","equipementId":"y-eq1","nature":"corrective","statut":"en_cours","avecArret":"oui","arretType":"non_planifie","arretDebut":"2026-11-07T08:00","resultat":"resolu"}}]');
  n:=7; test:='terminer un arrêt non planifié sans fin (refus)';
  r := push_fiches('[{"id":"y-ot3","type":"ots","patch":{"statut":"cloturee"}}]'); return next;
  n:=8; test:='avec « heures inconnues » (ok)';
  r := push_fiches('[{"id":"y-ot3","type":"ots","patch":{"statut":"travail_termine","arretHeuresInconnues":true}}]'); return next;
  perform push_fiches('[{"id":"y-ot4","type":"ots","patch":{"id":"y-ot4","equipementId":"y-eq1","nature":"corrective","statut":"en_cours","avecArret":"oui","arretType":"non_planifie","arretDebut":"2026-11-07T08:00","resultat":"resolu"}}]');
  n:=9; test:='avec fin d''arrêt (ok)';
  r := push_fiches('[{"id":"y-ot4","type":"ots","patch":{"statut":"cloturee","arretFin":"2026-11-07T09:30"}}]'); return next;
  perform push_fiches('[{"id":"y-ot5","type":"ots","patch":{"id":"y-ot5","equipementId":"y-eq1","nature":"corrective","statut":"en_cours","avecArret":"oui","arretType":"planifie","resultat":"resolu"}}]');
  n:=10; test:='arrêt planifié sans fin (ok)';
  r := push_fiches('[{"id":"y-ot5","type":"ots","patch":{"statut":"cloturee"}}]'); return next;
  n:=11; test:='ancienne intervention sans arretType (acceptée, contrôle appli)';
  r := push_fiches('[{"id":"y-old","type":"ots","patch":{"statut":"cloturee"}}]'); return next;

  perform set_config('request.jwt.claims', '', true);
  n:=12; test:='fonctions ouvertes sans compte';
  r := (select coalesce(jsonb_agg(p.proname), '[]') from pg_proc p join pg_namespace x on x.oid = p.pronamespace
        where x.nspname = 'public' and p.proname <> 'gmao_test_r2' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')); return next;

  delete from fiches where entreprise_id = ent;
  delete from pf_limites where cle like '%' || ent::text;
  delete from profil_sites where user_id in (resp, tech);
  delete from profils where user_id in (resp, tech);
  delete from sites where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=13; test:='nettoyage'; r := jsonb_build_object('reste', (select count(*) from entreprises where code = 'R2TEST')); return next;
end $$;
revoke all on function public.gmao_test_r2() from public, anon, authenticated;   -- jamais appelable par l'API
select jsonb_object_agg(n::text || ' ' || test, r order by n)::text as resultats from public.gmao_test_r2();
-- Puis, OBLIGATOIREMENT : drop function if exists public.gmao_test_r2();
