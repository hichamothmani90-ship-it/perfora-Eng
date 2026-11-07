-- Test de la démo commerciale (pf_reinitialiser_demo, avec les données du volet B). Supabase → SQL Editor.
-- Crée une entreprise de démonstration temporaire TDEMO, la réinitialise au nom de l'administrateur
-- plateforme, contrôle le contenu, puis supprime tout. Résultat attendu (6 nov. 2026) :
-- Avec demo_energie.sql (7 nov. 2026) : 110 fiches dont 71 d'énergie (compteurs 6, releves 61, factures_energie 3, programmes +1).
-- Avant : 39 fiches (ots 2, besoins 2, articles 4, demandes 4, personnes 4, mouvements 6, programmes 2,
-- equipements 4, localisations 4, valorisations 4, seuils 2, achats 1) · attente_liee_au_besoin 1 · piece_huile 2 ·
-- retrait_a_verifier 1 · stock_rouleau 2 · besoins_sur_site true · volet_c : seuil_valide 1, seuil_propose 1,
-- achat_commande 1, valorisations_liees 4, couts_sur_site true · nettoyage « DEMO, VITRINE ».
-- (version de la fonction : supabase/demo.sql)
create or replace function public.gmao_test_demo() returns jsonb language plpgsql as $$
declare ent uuid; site uuid; adm uuid; r jsonb; ot jsonb; res jsonb;
begin
  select user_id into adm from admins_plateforme limit 1;
  insert into entreprises(code, nom, demo) values ('TDEMO', 'Test démo', true) returning id into ent;
  insert into abonnements(entreprise_id, pack) values (ent, 'pro');
  insert into sites(entreprise_id, code, nom) values (ent, 'TD', 'Site démo test') returning id into site;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := pf_reinitialiser_demo(ent);
  select data into ot from fiches where entreprise_id = ent and type = 'ots' and data->>'ref' = 'OT-DEMO-0003';
  res := jsonb_build_object('reinit', r,
    'par_type', (select jsonb_object_agg(type, c) from (select type, count(*) c from fiches where entreprise_id = ent group by type) x),
    'attente_liee_au_besoin', (select count(*) from fiches where entreprise_id = ent and type = 'besoins' and id = ot->'attentes'->0->>'besoinId' and data->>'articleId' is not null),
    'piece_huile', ot->'pieces'->0->'qte',
    'retrait_a_verifier', (select count(*) from fiches where entreprise_id = ent and type = 'mouvements' and (data->>'urgent')::boolean and data->>'verifieLe' is null),
    'stock_rouleau', (select sum((m.data->>'qte')::numeric) from fiches m join fiches a on a.id = m.data->>'articleId' where m.entreprise_id = ent and m.type = 'mouvements' and a.data->>'ref' = 'ROUL-TD-50'),
    'besoins_sur_site', (select bool_and(site_id = site) from fiches where entreprise_id = ent and type = 'besoins'),
    'volet_c', jsonb_build_object(
      'seuil_valide', (select count(*) from fiches where entreprise_id = ent and type = 'seuils' and data->>'statut' = 'valide'),
      'seuil_propose', (select count(*) from fiches where entreprise_id = ent and type = 'seuils' and data->>'statut' = 'propose'),
      'achat_commande', (select count(*) from fiches where entreprise_id = ent and type = 'achats' and data->>'statut' = 'commandee'),
      'valorisations_liees', (select count(*) from fiches v join fiches m on m.id = v.data->>'mouvementId' where v.entreprise_id = ent and v.type = 'valorisations'),
      'couts_sur_site', (select bool_and(site_id = site) from fiches where entreprise_id = ent and type in ('achats', 'valorisations', 'seuils'))));
  delete from fiches where entreprise_id = ent;
  delete from sites where entreprise_id = ent;
  delete from abonnements where entreprise_id = ent;
  delete from entreprises where id = ent;
  return res || jsonb_build_object('nettoyage', (select string_agg(code, ', ') from entreprises));
end $$;
revoke all on function public.gmao_test_demo() from public, anon, authenticated;   -- jamais appelable par l'API, même si on oublie le « drop »
select public.gmao_test_demo()::text as resultat;
-- Puis : drop function if exists public.gmao_test_demo();
