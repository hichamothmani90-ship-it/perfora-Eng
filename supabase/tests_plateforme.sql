-- Tests de la console plateforme (volet A4). Supabase → SQL Editor. Nettoie ses données.
-- Résultats du 6 nov. 2026 : 1 refus (non-admin) · 2 créée · 3 refus code · 4 refus quota site ·
-- 5 ok · 6 démo rechargée (27 fiches) · 7 refus (DEMO non démo) · 8 ok · 10 DEMO intacte · 11 nettoyage.
create or replace function public.gmao_test_pf() returns table(n int, test text, r jsonb) language plpgsql as $$
declare admin uuid; ent uuid; demo uuid; res jsonb;
begin
  select user_id into admin from admins_plateforme limit 1;
  select id into demo from entreprises where code = 'DEMO';
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000ee', 'role', 'authenticated')::text, true);
  n:=1; test:='non-admin liste les clients (refus)'; begin r:=jsonb_build_object('ok', jsonb_array_length(pf_entreprises())); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;
  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  n:=2; test:='admin cree une entreprise demo Essentiel'; res:=pf_creer_entreprise('TEST-PF', 'Test plateforme', 'essentiel', 'essai', 'S1', 'Site test', true); ent:=(res->>'entrepriseId')::uuid; r:=res; return next;
  n:=3; test:='meme code (refus)'; begin r:=pf_creer_entreprise('TEST-PF', 'x', 'pro', 'essai', 'S1', 'x', false); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;
  n:=4; test:='2e site en Essentiel (refus quota)'; begin r:=jsonb_build_object('ok', pf_ajouter_site(ent, 'S2', 'Site 2')); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;
  perform pf_modifier_abonnement(ent, 'pro', 'actif', null, null, null, null);
  n:=5; test:='passage en Pro puis 2e site (ok)'; begin r:=jsonb_build_object('ok', pf_ajouter_site(ent, 'S2', 'Site 2') is not null); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;
  n:=6; test:='reinitialiser la demo (ok)'; r:=pf_reinitialiser_demo(ent); return next;
  n:=7; test:='reinitialiser une entreprise non demo (refus)'; begin r:=pf_reinitialiser_demo(demo); exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;
  n:=8; test:='preparer invitation responsable (ok)'; begin r:=pf_preparer_invitation(ent, 'resp@test-pf.test', 'responsable', array[(select id from sites where entreprise_id = ent and code = 'S1')]) - 'invite_par'; exception when others then r:=jsonb_build_object('refus', sqlerrm); end; return next;
  n:=9; test:='liste admin'; r:=(select jsonb_agg(jsonb_build_object('code', x->>'code', 'pack', x->'abonnement'->>'pack', 'sites', jsonb_array_length(x->'sites'), 'fiches', x->'fiches', 'actifs', x->'actifs')) from jsonb_array_elements(pf_entreprises()) x); return next;
  n:=10; test:='DEMO intacte'; r:=jsonb_build_object('fiches_DEMO', (select count(*) from fiches where entreprise_id = demo)); return next;
  delete from fiches where entreprise_id = ent; delete from abonnements where entreprise_id = ent; delete from sites where entreprise_id = ent; delete from entreprises where id = ent;
  n:=11; test:='nettoyage'; r:=jsonb_build_object('entreprises', (select count(*) from entreprises)); return next;
end $$;
revoke all on function public.gmao_test_pf() from public, anon, authenticated;   -- jamais appelable par l'API, même si on oublie le « drop »
select jsonb_object_agg(n::text || ' ' || test, r)::text from public.gmao_test_pf();
-- Puis : drop function if exists public.gmao_test_pf();
