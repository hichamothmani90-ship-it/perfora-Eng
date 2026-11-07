-- ===== 19_demo.sql — copie générée de supabase/demo.sql (empreinte 8e724fa0fbc29b27) : ne pas modifier ici =====
-- GMAO terrain — démo commerciale (rejouable). APRÈS achats.sql.
-- Remplace pf_reinitialiser_demo de plateforme.sql (ne pas rejouer plateforme.sql en entier après achats.sql :
-- controle_invitation y est dans sa version d'avant le rôle « achats »).
-- Contenu : volets A et B (équipements, demandes, interventions, préventif, besoins de pièces, retrait urgent)
-- + volet C : prix des entrées de stock (un provisoire), seuil validé du joint (déclenche « À réapprovisionner »),
-- seuil proposé du filtre (à valider), demande d'achat DA-DEMO-0001 commandée (3 filtres, livraison demain).
-- Les écrans Achats et Valeur du stock n'apparaissent que si l'abonnement de la démo inclut le module achats.

create or replace function public.pf_reinitialiser_demo(p_entreprise uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  e entreprises; site uuid; k text; maint text := public.pf_j(0, to_char(now() at time zone 'Africa/Casablanca', 'HH24:MI'));
  l_site text; l_at text; l_li text; l_ut text; presse text; emb text; conv text; comp text;
  resp text; ta text; tb text; mag text; a1 text; a2 text; a3 text; a4 text; b3 text; b4 text; da1 text; d1 text; d3 text; o1 text; o3 text; m1 text;
begin
  perform public.exiger_admin();
  select * into e from entreprises where id = p_entreprise;
  if not found or not e.demo then raise exception 'Seule une entreprise de démonstration peut être réinitialisée'; end if;
  select id into site from sites where entreprise_id = e.id and actif order by cree_le limit 1;
  if site is null then raise exception 'La démo n''a aucun site actif'; end if;

  delete from fiches where entreprise_id = e.id;   -- démo uniquement : rien d'autre n'est jamais supprimé
  k := substr(md5(e.id::text || clock_timestamp()::text), 1, 8);
  l_site := k || '-loc0'; l_at := k || '-loc1'; l_li := k || '-loc2'; l_ut := k || '-loc3';
  presse := k || '-eq1'; emb := k || '-eq2'; conv := k || '-eq3'; comp := k || '-eq4';
  resp := k || '-p1'; ta := k || '-p2'; tb := k || '-p3'; mag := k || '-p4';
  a1 := k || '-a1'; a2 := k || '-a2'; a3 := k || '-a3'; d1 := k || '-d1'; d3 := k || '-d3'; o1 := k || '-o1'; m1 := k || '-m1';
  a4 := k || '-a4'; b3 := k || '-b3'; b4 := k || '-b4'; o3 := k || '-o3'; da1 := k || '-da1';

  insert into fiches (id, type, entreprise_id, site_id, data)
  select v.id, v.type, e.id, case when v.type in ('personnes','articles') then null else site end,
         v.data || jsonb_build_object('id', v.id, 'creeLe', coalesce(v.data->>'creeLe', maint), 'creePar', coalesce(v.data->>'creePar', 'Démo'), 'modifieLe', maint, 'modifiePar', 'Démo')
                || case when v.type in ('personnes','articles') then '{}'::jsonb else jsonb_build_object('siteId', site) end
  from (values
    (l_site, 'localisations', jsonb_build_object('code', 'SITE', 'nom', 'Usine', 'parentId', null)),
    (l_at, 'localisations', jsonb_build_object('code', 'AT-PR', 'nom', 'Atelier presses', 'parentId', l_site)),
    (l_li, 'localisations', jsonb_build_object('code', 'LG-CD', 'nom', 'Ligne conditionnement', 'parentId', l_site)),
    (l_ut, 'localisations', jsonb_build_object('code', 'UT', 'nom', 'Utilités', 'parentId', l_site)),
    (presse, 'equipements', jsonb_build_object('code', 'PRESSE-01', 'designation', 'Presse hydraulique 200 t', 'localisationId', l_at, 'famille', 'presse', 'criticite', '4', 'actif', true)),
    (emb, 'equipements', jsonb_build_object('code', 'EMB-02', 'designation', 'Emballeuse ligne 2', 'localisationId', l_li, 'famille', 'emballage', 'criticite', '3', 'actif', true)),
    (conv, 'equipements', jsonb_build_object('code', 'CONV-03', 'designation', 'Convoyeur sortie ligne 2', 'localisationId', l_li, 'famille', 'convoyage', 'criticite', '2', 'actif', true)),
    (comp, 'equipements', jsonb_build_object('code', 'COMP-01', 'designation', 'Compresseur d’air 55 kW', 'localisationId', l_ut, 'famille', 'utilité', 'criticite', '4', 'actif', true)),
    (resp, 'personnes', jsonb_build_object('nom', 'Responsable maintenance', 'role', 'responsable', 'actif', true)),
    (ta, 'personnes', jsonb_build_object('nom', 'Technicien A (mécanique)', 'role', 'technicien', 'actif', true)),
    (tb, 'personnes', jsonb_build_object('nom', 'Technicien B (automatisme)', 'role', 'technicien', 'actif', true)),
    (mag, 'personnes', jsonb_build_object('nom', 'Magasinier', 'role', 'magasinier', 'actif', true)),
    (a1, 'articles', jsonb_build_object('ref', 'J-VER-80', 'designation', 'Joint de vérin Ø80', 'unite', 'u', 'stockMin', 2, 'actif', true)),
    (a2, 'articles', jsonb_build_object('ref', 'HUI-HV46', 'designation', 'Huile hydraulique HV46', 'unite', 'L', 'stockMin', 20, 'actif', true)),
    (a3, 'articles', jsonb_build_object('ref', 'FIL-AIR', 'designation', 'Filtre à air compresseur', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (a4, 'articles', jsonb_build_object('ref', 'ROUL-TD-50', 'designation', 'Rouleau tendeur convoyeur Ø50', 'unite', 'u', 'stockMin', 1, 'actif', true)),
    (k || '-m0d', 'mouvements', jsonb_build_object('articleId', a4, 'type', 'entree', 'qte', 2, 'otId', null, 'le', public.pf_j(0, '09:15'), 'motif', 'Livraison fournisseur')),
    -- volet B : le convoyeur attend un rouleau (demande urgente, en stock) ; 2 L d'huile pris en urgence, à vérifier
    (b3, 'besoins', jsonb_build_object('ref', 'BES-DEMO-0001', 'otId', o3, 'equipementId', conv, 'articleId', a4, 'qte', 1, 'unite', 'u', 'urgent', true, 'statut', 'demande', 'note', 'Arrêt ligne 2', 'demandeur', 'Technicien B (automatisme)', 'demandeLe', public.pf_j(0, '08:30'), 'creeLe', public.pf_j(0, '08:30'))),
    (b4, 'besoins', jsonb_build_object('ref', 'BES-DEMO-0002', 'otId', o3, 'equipementId', conv, 'articleId', a2, 'qte', 2, 'unite', 'L', 'urgent', true, 'statut', 'demande', 'note', 'Retrait urgent', 'demandeur', 'Technicien B (automatisme)', 'demandeLe', public.pf_j(0, '08:10'), 'creeLe', public.pf_j(0, '08:10'))),
    (k || '-m4', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'remise', 'qte', -2, 'urgent', true, 'aVerifier', true, 'besoinId', b4, 'otId', o3, 'le', public.pf_j(0, '08:10'), 'motif', 'Retrait urgent OT-DEMO-0003', 'creePar', 'Technicien B (automatisme)')),
    -- volet C : prix des entrées (valorisation, lecture restreinte), seuils, commande en cours
    (k || '-v0a', 'valorisations', jsonb_build_object('mouvementId', k || '-m0a', 'prixUnitaire', 85, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0b', 'valorisations', jsonb_build_object('mouvementId', k || '-m0b', 'prixUnitaire', 42, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0c', 'valorisations', jsonb_build_object('mouvementId', k || '-m0c', 'prixUnitaire', 310, 'devise', 'MAD', 'statut', 'connu')),
    (k || '-v0d', 'valorisations', jsonb_build_object('mouvementId', k || '-m0d', 'prixUnitaire', 260, 'devise', 'MAD', 'statut', 'provisoire')),
    (k || '-s1', 'seuils', jsonb_build_object('articleId', a1, 'securite', 1, 'pointCommande', 4, 'cible', 8, 'delaiJours', 21, 'critique', true, 'statut', 'valide',
        'justification', 'Presse critique, délai fournisseur 3 semaines', 'proposePar', 'Magasinier', 'proposeLe', public.pf_j(-10, '10:00'), 'valideLe', public.pf_j(-9, '09:00'), 'validePar', 'Responsable maintenance')),
    (k || '-s2', 'seuils', jsonb_build_object('articleId', a3, 'securite', 1, 'pointCommande', 2, 'cible', 4, 'delaiJours', 10, 'critique', false, 'statut', 'propose',
        'justification', 'Compresseur sans secours : garder un filtre d’avance', 'proposePar', 'Magasinier', 'proposeLe', public.pf_j(-1, '16:00'))),
    (da1, 'achats', jsonb_build_object('ref', 'DA-DEMO-0001', 'statut', 'commandee', 'origine', 'reapprovisionnement', 'redigePar', 'Magasinier', 'redigeLe', public.pf_j(-6, '10:00'),
        'soumiseLe', public.pf_j(-6, '10:05'), 'soumisePar', 'Magasinier', 'valideLe', public.pf_j(-5, '08:30'), 'validePar', 'Responsable maintenance',
        'fournisseur', 'Atlas Compresseurs', 'refCommande', 'BC-DEMO-0042', 'dateCommande', public.pf_j(-4), 'livraisonPrevue', public.pf_j(1), 'devise', 'MAD',
        'commandeLe', public.pf_j(-4, '11:00'), 'commandePar', 'Responsable maintenance',
        'lignes', jsonb_build_array(jsonb_build_object('id', k || '-dl1', 'articleId', a3, 'qte', 3, 'qteCommandee', 3, 'unite', 'u', 'prixUnitaire', 310, 'devise', 'MAD', 'motif', 'Stock sous le seuil')))),
    (k || '-m0a', 'mouvements', jsonb_build_object('articleId', a1, 'type', 'entree', 'qte', 3, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0b', 'mouvements', jsonb_build_object('articleId', a2, 'type', 'entree', 'qte', 60, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (k || '-m0c', 'mouvements', jsonb_build_object('articleId', a3, 'type', 'entree', 'qte', 1, 'otId', null, 'le', public.pf_j(-20, '09:00'), 'motif', 'Stock initial')),
    (m1, 'mouvements', jsonb_build_object('articleId', a1, 'type', 'sortie', 'qte', -1, 'otId', o1, 'le', public.pf_j(-3, '09:00'), 'motif', null)),
    (d1, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0001', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Opérateur presse', 'service', 'Production'), 'equipementId', presse, 'besoin', 'corriger', 'constat', 'Le vérin ne tient plus la position', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(-3, '08:00'), 'precisionHeure', 'exacte', 'statut', 'traitement_organise', 'priseEnChargePar', ta, 'priseEnChargeLe', public.pf_j(-3, '08:05'), 'creeLe', public.pf_j(-3, '08:03'))),
    (k || '-d2', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0002', 'origine', 'tiers', 'tiers', jsonb_build_object('nom', 'Chef de ligne', 'service', 'Conditionnement'), 'equipementId', emb, 'besoin', 'verifier', 'constat', 'Bruit anormal au niveau du convoyeur d’entrée', 'etat', 'degrade', 'impact', 'aucun_constate', 'heureFait', public.pf_j(-1, '14:20'), 'precisionHeure', 'estimee', 'statut', 'a_examiner', 'creeLe', public.pf_j(-1, '14:35'))),
    (d3, 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0003', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie, frottement côté moteur', 'etat', 'indisponible', 'impact', 'interrompu', 'heureFait', public.pf_j(0, '07:40'), 'precisionHeure', 'estimee', 'statut', 'traitement_organise', 'priseEnChargePar', tb, 'priseEnChargeLe', public.pf_j(0, '07:50'), 'creeLe', public.pf_j(0, '07:45'))),
    (k || '-d4', 'demandes', jsonb_build_object('ref', 'DEM-DEMO-0004', 'origine', 'observation', 'equipementId', conv, 'besoin', 'corriger', 'constat', 'Bande qui dévie', 'etat', 'degrade', 'impact', 'reduit', 'precisionHeure', 'inconnue', 'statut', 'close_sans_travail', 'motifClassement', 'Recentrage par l’opérateur', 'creeLe', public.pf_j(-12, '10:00'))),
    (o1, 'ots', jsonb_build_object('ref', 'OT-DEMO-0001', 'demandeIds', jsonb_build_array(d1), 'equipementId', presse, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'cloturee',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i1', 'personneId', ta, 'role', 'intervenant', 'depuis', public.pf_j(-3, '08:10'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic', 'remplacement'), 'travaux', 'Remplacement du joint de vérin, purge du circuit.', 'resultat', 'resolu', 'cause', 'Joint de vérin usé', 'certitudeCause', 'probable', 'familleDefaut', 'hydraulique',
        'avecArret', 'oui', 'arretDebut', public.pf_j(-3, '08:00'), 'arretFin', public.pf_j(-3, '10:30'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc1', 'articleId', a1, 'qte', 1, 'mouvementId', m1, 'annulee', false)), 'reserves', '[]'::jsonb, 'attentes', '[]'::jsonb,
        'clotureLe', public.pf_j(-3, '11:20'), 'cloturePar', 'Responsable maintenance', 'creeLe', public.pf_j(-3, '08:05'))),
    (o3, 'ots', jsonb_build_object('ref', 'OT-DEMO-0003', 'demandeIds', jsonb_build_array(d3), 'equipementId', conv, 'nature', 'corrective', 'priorite', 'critique_service', 'statut', 'suspendue',
        'intervenants', jsonb_build_array(jsonb_build_object('id', k || '-i3', 'personneId', tb, 'role', 'intervenant', 'depuis', public.pf_j(0, '07:50'), 'fin', null)),
        'activites', jsonb_build_array('diagnostic'), 'travaux', 'Rouleau tendeur grippé.', 'familleDefaut', 'mecanique', 'avecArret', 'oui', 'arretDebut', public.pf_j(0, '07:40'),
        'pieces', jsonb_build_array(jsonb_build_object('id', k || '-pc3', 'besoinId', b4, 'articleId', a2, 'qte', 2, 'mouvementId', null, 'annulee', false)), 'reserves', '[]'::jsonb,
        'attentes', jsonb_build_array(jsonb_build_object('id', k || '-at3', 'motif', 'piece', 'besoinId', b3, 'detail', 'Rouleau tendeur convoyeur Ø50', 'depuis', public.pf_j(0, '08:30'), 'fin', null, 'responsableId', mag)),
        'creeLe', public.pf_j(0, '07:50'))),
    (k || '-pg1', 'programmes', jsonb_build_object('equipementId', comp, 'libelle', 'Vidange et filtre compresseur', 'modele', 'entretien', 'periodiciteJours', 90, 'prochaineEcheance', public.pf_j(-2), 'regle', 'fixe', 'instruction', 'Consigner selon procédure site, vidanger, remplacer le filtre à air, essai à vide puis en charge.', 'actif', true)),
    (k || '-pg2', 'programmes', jsonb_build_object('equipementId', presse, 'libelle', 'Contrôle niveau et fuites hydrauliques', 'modele', 'inspection', 'periodiciteJours', 30, 'prochaineEcheance', public.pf_j(5), 'regle', 'apres_realisation', 'instruction', 'Niveau bâche, état flexibles, traces de fuite.', 'actif', true))
  ) as v(id, type, data);

  update entreprises set reinit_le = now() where id = e.id;
  return jsonb_build_object('fiches', (select count(*) from fiches where entreprise_id = e.id), 'reinitLe', now());
end $$;
revoke all on function public.pf_reinitialiser_demo(uuid) from public, anon;
grant execute on function public.pf_reinitialiser_demo(uuid) to authenticated;
