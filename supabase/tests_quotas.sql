-- Tests des quotas et de l'invitation (volet A3). Supabase → SQL Editor. Nettoie ses données.
-- Entreprise fictive QTEST en pack Essentiel : 1 site, 5 utilisateurs (par site et au total).
-- Résultat : une ligne JSON ; « ok » = accepté, « refus » = message d'erreur attendu.
create or replace function public.gmao_test_quotas() returns table(n int, test text, r jsonb) language plpgsql as $$
declare ent uuid; s1 uuid; s2 uuid; autre_site uuid; resp uuid := '00000000-0000-0000-0000-00000000c001'; u uuid; i int;
begin
  insert into entreprises(code, nom) values ('QTEST', 'Quota test') returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'essentiel');
  insert into sites(entreprise_id, code, nom) values (ent, 'Q1', 'Site Q1') returning id into s1;
  select id into autre_site from sites where code = 'TNG' limit 1;

  n:=1; test:='2e site en pack Essentiel (refus)';
  begin insert into sites(entreprise_id, code, nom) values (ent, 'Q2', 'Site Q2') returning id into s2; r:=jsonb_build_object('ok', true);
  exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values (resp, 'resp@q.test', 'Resp Q', 'responsable', ent, s1);
  insert into profil_sites values (resp, s1);
  for i in 2..5 loop
    u := ('00000000-0000-0000-0000-00000000c00' || i)::uuid;
    insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values (u, 'u' || i || '@q.test', 'U' || i, 'technicien', ent, s1);
    insert into profil_sites values (u, s1);
  end loop;
  n:=2; test:='5 comptes actifs crees (ok)'; r:=jsonb_build_object('actifs', nb_actifs_entreprise(ent, null), 'sur_Q1', nb_actifs_site(s1, null)); return next;

  n:=3; test:='6e compte actif (refus quota total)';
  begin insert into profils(user_id, email, nom, role, entreprise_id) values ('00000000-0000-0000-0000-00000000c006', 'u6@q.test', 'U6', 'technicien', ent); r:=jsonb_build_object('ok', true);
  exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', resp, 'role', 'authenticated')::text, true);
  n:=4; test:='Invitation quand tout est plein (refus)';
  begin r:=jsonb_build_object('ok', preparer_invitation('nouveau@q.test', 'technicien', array[s1])); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  update profils set actif = false where user_id = '00000000-0000-0000-0000-00000000c005';
  n:=5; test:='Apres desactivation d un compte : invitation possible (ok)';
  begin r:=jsonb_build_object('ok', preparer_invitation('nouveau@q.test', 'technicien', array[s1]) ? 'entreprise_id'); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  insert into profils(user_id, email, nom, role, entreprise_id, site_defaut) values ('00000000-0000-0000-0000-00000000c007', 'u7@q.test', 'U7', 'technicien', ent, s1);
  insert into profil_sites values ('00000000-0000-0000-0000-00000000c007', s1);
  n:=6; test:='Reactiver l ancien compte alors que la place est reprise (refus)';
  begin update profils set actif = true where user_id = '00000000-0000-0000-0000-00000000c005'; r:=jsonb_build_object('ok', true);
  exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  n:=7; test:='Affecter un membre a un site d une autre entreprise (refus)';
  begin perform affecter_sites('00000000-0000-0000-0000-00000000c002', array[autre_site]); r:=jsonb_build_object('ok', true);
  exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  n:=8; test:='Inviter un compte deja dans une autre entreprise (refus)';
  begin r:=jsonb_build_object('ok', preparer_invitation((select email from profils where entreprise_id <> ent and role = 'responsable' limit 1), 'technicien', array[s1]));
  exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  n:=9; test:='E-mail invalide (refus)';
  begin r:=jsonb_build_object('ok', preparer_invitation('pas-un-email', 'technicien', array[s1])); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  n:=10; test:='Utilisation vue par le responsable';
  begin r:=utilisation() - 'affectations'; exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-00000000c002', 'role', 'authenticated')::text, true);
  n:=11; test:='Un technicien tente d inviter (refus)';
  begin r:=jsonb_build_object('ok', preparer_invitation('x@q.test', 'technicien', array[s1])); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;

  delete from profil_sites where site_id = s1;
  delete from profils where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from sites where entreprise_id = ent;
  delete from entreprises where id = ent;
  n:=12; test:='nettoyage'; r:=jsonb_build_object('entreprises', (select count(*) from entreprises), 'profils_test', (select count(*) from profils where email like '%@q.test')); return next;
end $$;
select jsonb_object_agg(n::text || ' ' || test, r)::text as resultats from public.gmao_test_quotas();
-- Puis : drop function if exists public.gmao_test_quotas();
