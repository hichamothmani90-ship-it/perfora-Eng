-- Tests du centre de contrôle (CC2). Supabase → SQL Editor, après centre_controle_cc2.sql.
-- Entreprises fictives KTEST et KAUTRE. Utilise le premier administrateur plateforme. Nettoie ses données.
-- Attendu : 1 non-admin pf_objets_lire : erreur ; 2 prospect enregistré (etape nouveau) ; 3 prospect perdu sans motif : erreur ;
--  4 échange sur le prospect ; 5 un échange ne se modifie pas : erreur ; 6 ticket créé par la console : ref SUP-… ;
--  7 ticket sans client : erreur ; 8 support_creer par un technicien : ref SUP-…, source appli ; 9 nature inconnue : erreur ;
--  10 annonce pour KTEST ; 11 annonce pour KAUTRE ; 12 mes_annonces du technicien KTEST : 1 (la sienne) — pas celle de
--  KAUTRE ; 13 le technicien lit pf_objets ou pf_annonces directement : 0 / 0 ; 14 suppression d'un prospect efface ses
--  échanges : 0 ; 15 ticket non supprimable : erreur ; 16 modèles par défaut ≥ 5 ; 17 nettoyage sans KTEST ni KAUTRE.
create or replace function public.gmao_test_cc2() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; ent2 uuid; site uuid; site2 uuid; adm uuid; tech uuid := '00000000-0000-0000-0000-0000000000f2';
  p jsonb; e jsonb; t jsonb; tk text;
begin
  select user_id into adm from admins_plateforme limit 1;
  if adm is null then raise exception 'Aucun administrateur plateforme'; end if;
  insert into entreprises(code, nom) values ('KTEST', 'CC2 test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'essentiel');
  insert into sites(entreprise_id, code, nom) values (ent, 'K1', 'Site K1') returning id into site;
  insert into entreprises(code, nom) values ('KAUTRE', 'CC2 autre') returning id into ent2;
  insert into abonnements(entreprise_id, pack) values (ent2, 'essentiel');
  insert into sites(entreprise_id, code, nom) values (ent2, 'K2', 'Site K2') returning id into site2;
  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values (tech, 'tech@k.test', 'Tech K', 'technicien', ent, site);
  insert into profil_sites values (tech, site);

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=1; test:='non-admin lit les prospects (erreur)';
  begin r := pf_objets_lire('prospect'); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  n:=2; test:='prospect'; p := pf_objet_enregistrer(null, 'prospect', null, '{"societe":"Laiterie test","nom":"Mme X","etape":"nouveau"}'::jsonb);
  r := jsonb_build_object('etape', p->>'etape', 'id_ok', (p->>'id') like 'prospect-%'); return next;
  n:=3; test:='prospect perdu sans motif (erreur)';
  begin r := pf_objet_enregistrer(p->>'id', 'prospect', null, (p - 'id') || '{"etape":"perdu"}'::jsonb); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=4; test:='echange sur le prospect'; e := pf_objet_enregistrer(null, 'echange', null, jsonb_build_object('canal', 'whatsapp', 'sens', 'sortant', 'resume', 'Proposition de demo', 'prospectId', p->>'id'));
  r := jsonb_build_object('canal', e->>'canal'); return next;
  n:=5; test:='un echange ne se modifie pas (erreur)';
  begin r := pf_objet_enregistrer(e->>'id', 'echange', null, jsonb_build_object('canal', 'email', 'resume', 'x', 'prospectId', p->>'id')); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=6; test:='ticket console'; t := pf_objet_enregistrer(null, 'ticket', ent, '{"sujet":"Question import","nature":"question","statut":"ouverte","priorite":"haute"}'::jsonb);
  r := jsonb_build_object('ref_ok', (t->>'ref') like 'SUP-%', 'entreprise_ok', (t->>'entrepriseId')::uuid = ent); return next;
  n:=7; test:='ticket sans client (erreur)';
  begin r := pf_objet_enregistrer(null, 'ticket', null, '{"sujet":"x"}'::jsonb); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=8; test:='support_creer par le technicien'; r := support_creer('anomalie', 'Photo bloquee', 'La photo reste en attente');
  tk := r->>'ref';
  r := r || jsonb_build_object('source', (select data->>'source' from pf_objets where data->>'ref' = tk), 'entreprise_ok', (select entreprise_id = ent from pf_objets where data->>'ref' = tk)); return next;
  n:=9; test:='nature inconnue (erreur)';
  begin r := support_creer('autre', 'x', 'y'); exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  n:=10; test:='annonce KTEST'; r := jsonb_build_object('id_ok', pf_annonce_enregistrer(null, 'Test KTEST', 'Pour KTEST', 'info', ent, now() - interval '1 hour', null, true) is not null); return next;
  n:=11; test:='annonce KAUTRE'; r := jsonb_build_object('id_ok', pf_annonce_enregistrer(null, 'Test KAUTRE', 'Pour KAUTRE', 'info', ent2, now() - interval '1 hour', null, true) is not null); return next;
  perform set_config('request.jwt.claims', json_build_object('sub', tech, 'role', 'authenticated')::text, true);
  n:=12; test:='mes_annonces du technicien KTEST';
  r := jsonb_build_object('siennes', (select count(*) from jsonb_array_elements(mes_annonces()) a where a->>'titre' = 'Test KTEST'),
    'autre_client', (select count(*) from jsonb_array_elements(mes_annonces()) a where a->>'titre' = 'Test KAUTRE')); return next;
  set local role authenticated;
  n:=13; test:='lecture directe des tables de plateforme'; r := jsonb_build_object('pf_objets', (select count(*) from pf_objets), 'pf_annonces', (select count(*) from pf_annonces)); return next;
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  n:=14; test:='suppression du prospect et de ses echanges'; perform pf_objet_supprimer(p->>'id');
  r := jsonb_build_object('echanges_restants', (select count(*) from pf_objets where data->>'prospectId' = p->>'id')); return next;
  n:=15; test:='ticket non supprimable (erreur)';
  begin perform pf_objet_supprimer(t->>'id'); r := '{"erreur":null}'; exception when others then r := jsonb_build_object('erreur', sqlerrm); end; return next;
  n:=16; test:='modeles par defaut'; r := jsonb_build_object('modeles', jsonb_array_length(pf_objets_lire('modele'))); return next;

  delete from pf_objets where entreprise_id in (ent, ent2);
  delete from pf_annonces where entreprise_id in (ent, ent2);
  delete from profil_sites where site_id in (site, site2);
  delete from profils where entreprise_id in (ent, ent2);
  delete from abonnements where entreprise_id in (ent, ent2);
  delete from sites where entreprise_id in (ent, ent2);
  delete from entreprises where id in (ent, ent2);
  n:=17; test:='nettoyage'; r := jsonb_build_object('entreprises', (select string_agg(code, ', ') from entreprises)); return next;
end $$;
revoke all on function public.gmao_test_cc2() from public, anon, authenticated;   -- jamais appelable par l'API, même si on oublie le « drop »
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_cc2();
-- Puis, OBLIGATOIREMENT (sinon la fonction reste appelable par l'API) : drop function if exists public.gmao_test_cc2();
