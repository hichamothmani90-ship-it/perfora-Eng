-- ===== 18_demo_energie.sql — copie générée de supabase/demo_energie.sql (empreinte 7d45dd219704c0d0) : ne pas modifier ici =====
-- GMAO terrain — démo : énergie et eau (volet D, étape D5). APRÈS fichiers.sql (et demo.sql).
-- FICHIER GÉNÉRÉ par scripts/generer_demo_energie.py depuis Calculs.demoEnergie (js/calculs.js) : ne pas modifier à la main.
-- Scénario : arrivée générale + 3 sous-compteurs (résidu ≈ 7 % « à expliquer »), compteur de la ligne remplacé il y a
-- 30 jours, eau avec une lecture erronée (à examiner), heures du compresseur (vidange 2 000 h en alerte), factures ONEE
-- concordante puis en écart (+6 %), facture d'eau. Les écrans n'apparaissent que si l'abonnement inclut le module energie.

create or replace function public.pf_demo_energie(p_ent uuid, p_site uuid, k text, comp text)
returns integer language plpgsql security definer set search_path = public as $$
declare
  maint text := public.pf_j(0, to_char(now() at time zone 'Africa/Casablanca', 'HH24:MI'));
  n integer;
begin
  insert into fiches (id, type, entreprise_id, site_id, data)
  select v.id, v.type, p_ent, p_site,
         v.data || jsonb_build_object('id', v.id, 'siteId', p_site, 'creeLe', coalesce(v.data->>'creeLe', maint), 'creePar', coalesce(v.data->>'creePar', 'Démo'), 'modifieLe', maint, 'modifiePar', 'Démo')
  from (values
    (k || '-ncg', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'ELEC-GEN', 'libelle', 'Électricité — arrivée générale', 'usage', 'ressource', 'ressource', 'electricite', 'unite', 'kWh')),
    (k || '-ncc', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'ELEC-COMP', 'libelle', 'Électricité — compresseur', 'usage', 'ressource', 'ressource', 'electricite', 'unite', 'kWh', 'parentId', k || '-ncg', 'equipementId', comp)),
    (k || '-nca', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'ELEC-AT', 'libelle', 'Électricité — atelier presses', 'usage', 'ressource', 'ressource', 'electricite', 'unite', 'kWh', 'parentId', k || '-ncg')),
    (k || '-ncl', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'ELEC-LG', 'libelle', 'Électricité — ligne conditionnement', 'usage', 'ressource', 'ressource', 'electricite', 'unite', 'kWh', 'parentId', k || '-ncg')),
    (k || '-nce', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 7, 'mode', 'cumulatif', 'actif', true, 'code', 'EAU-GEN', 'libelle', 'Eau de ville', 'usage', 'ressource', 'ressource', 'eau', 'unite', 'm³')),
    (k || '-nch', 'compteurs', jsonb_build_object('coefficient', 1, 'frequenceJours', 1, 'mode', 'cumulatif', 'actif', true, 'code', 'HRS-COMP01', 'libelle', 'Heures de marche compresseur', 'usage', 'equipement', 'unite', 'h', 'equipementId', comp)),
    (k || '-nr1', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-64, '08:00'), 'creeLe', public.pf_j(-64, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 120000, 'unite', 'kWh')),
    (k || '-nr2', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-57, '08:00'), 'creeLe', public.pf_j(-57, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 126100, 'unite', 'kWh')),
    (k || '-nr3', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-50, '08:00'), 'creeLe', public.pf_j(-50, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 132000, 'unite', 'kWh')),
    (k || '-nr4', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-43, '08:00'), 'creeLe', public.pf_j(-43, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 138300, 'unite', 'kWh')),
    (k || '-nr5', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-36, '08:00'), 'creeLe', public.pf_j(-36, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 144350, 'unite', 'kWh')),
    (k || '-nr6', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-29, '08:00'), 'creeLe', public.pf_j(-29, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 150550, 'unite', 'kWh')),
    (k || '-nr7', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-22, '08:00'), 'creeLe', public.pf_j(-22, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 156350, 'unite', 'kWh')),
    (k || '-nr8', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-15, '08:00'), 'creeLe', public.pf_j(-15, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 162750, 'unite', 'kWh')),
    (k || '-nr9', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-8, '08:00'), 'creeLe', public.pf_j(-8, '08:00'), 'creePar', 'Technicien B (automatisme)', 'valeur', 168900, 'unite', 'kWh')),
    (k || '-nr10', 'releves', jsonb_build_object('compteurId', k || '-ncg', 'le', public.pf_j(-1, '08:00'), 'creeLe', public.pf_j(-1, '08:00'), 'creePar', 'Technicien A (mécanique)', 'valeur', 174900, 'unite', 'kWh')),
    (k || '-nr11', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-64, '08:04'), 'creeLe', public.pf_j(-64, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 45000, 'unite', 'kWh')),
    (k || '-nr12', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-57, '08:04'), 'creeLe', public.pf_j(-57, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 47350, 'unite', 'kWh')),
    (k || '-nr13', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-50, '08:04'), 'creeLe', public.pf_j(-50, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 49630, 'unite', 'kWh')),
    (k || '-nr14', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-43, '08:04'), 'creeLe', public.pf_j(-43, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 52050, 'unite', 'kWh')),
    (k || '-nr15', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-36, '08:04'), 'creeLe', public.pf_j(-36, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 54350, 'unite', 'kWh')),
    (k || '-nr16', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-29, '08:04'), 'creeLe', public.pf_j(-29, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 56740, 'unite', 'kWh')),
    (k || '-nr17', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-22, '08:04'), 'creeLe', public.pf_j(-22, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 58990, 'unite', 'kWh')),
    (k || '-nr18', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-15, '08:04'), 'creeLe', public.pf_j(-15, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 61450, 'unite', 'kWh')),
    (k || '-nr19', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-8, '08:04'), 'creeLe', public.pf_j(-8, '08:04'), 'creePar', 'Technicien B (automatisme)', 'valeur', 63820, 'unite', 'kWh')),
    (k || '-nr20', 'releves', jsonb_build_object('compteurId', k || '-ncc', 'le', public.pf_j(-1, '08:04'), 'creeLe', public.pf_j(-1, '08:04'), 'creePar', 'Technicien A (mécanique)', 'valeur', 66130, 'unite', 'kWh')),
    (k || '-nr21', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-64, '08:07'), 'creeLe', public.pf_j(-64, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 80000, 'unite', 'kWh')),
    (k || '-nr22', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-57, '08:07'), 'creeLe', public.pf_j(-57, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 82100, 'unite', 'kWh')),
    (k || '-nr23', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-50, '08:07'), 'creeLe', public.pf_j(-50, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 84150, 'unite', 'kWh')),
    (k || '-nr24', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-43, '08:07'), 'creeLe', public.pf_j(-43, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 86330, 'unite', 'kWh')),
    (k || '-nr25', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-36, '08:07'), 'creeLe', public.pf_j(-36, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 88450, 'unite', 'kWh')),
    (k || '-nr26', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-29, '08:07'), 'creeLe', public.pf_j(-29, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 90600, 'unite', 'kWh')),
    (k || '-nr27', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-22, '08:07'), 'creeLe', public.pf_j(-22, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 92600, 'unite', 'kWh')),
    (k || '-nr28', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-15, '08:07'), 'creeLe', public.pf_j(-15, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 94830, 'unite', 'kWh')),
    (k || '-nr29', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-8, '08:07'), 'creeLe', public.pf_j(-8, '08:07'), 'creePar', 'Technicien B (automatisme)', 'valeur', 96970, 'unite', 'kWh')),
    (k || '-nr30', 'releves', jsonb_build_object('compteurId', k || '-nca', 'le', public.pf_j(-1, '08:07'), 'creeLe', public.pf_j(-1, '08:07'), 'creePar', 'Technicien A (mécanique)', 'valeur', 99060, 'unite', 'kWh')),
    (k || '-nr31', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-64, '08:10'), 'creeLe', public.pf_j(-64, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 30500, 'unite', 'kWh')),
    (k || '-nr32', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-57, '08:10'), 'creeLe', public.pf_j(-57, '08:10'), 'creePar', 'Technicien A (mécanique)', 'valeur', 31720, 'unite', 'kWh')),
    (k || '-nr33', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-50, '08:10'), 'creeLe', public.pf_j(-50, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 32880, 'unite', 'kWh')),
    (k || '-nr34', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-43, '08:10'), 'creeLe', public.pf_j(-43, '08:10'), 'creePar', 'Technicien A (mécanique)', 'valeur', 34140, 'unite', 'kWh')),
    (k || '-nr35', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-36, '08:10'), 'creeLe', public.pf_j(-36, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 35340, 'unite', 'kWh')),
    (k || '-nr36', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'nature', 'rupture', 'typeRupture', 'remplacement', 'le', public.pf_j(-31, '10:00'), 'creeLe', public.pf_j(-31, '10:00'), 'creePar', 'Responsable maintenance', 'indexFinal', 36240, 'indexInitial', 0, 'motif', 'Compteur défectueux remplacé par l’électricien')),
    (k || '-nr37', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-29, '08:10'), 'creeLe', public.pf_j(-29, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 330, 'unite', 'kWh')),
    (k || '-nr38', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-22, '08:10'), 'creeLe', public.pf_j(-22, '08:10'), 'creePar', 'Technicien A (mécanique)', 'valeur', 1480, 'unite', 'kWh')),
    (k || '-nr39', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-15, '08:10'), 'creeLe', public.pf_j(-15, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 2750, 'unite', 'kWh')),
    (k || '-nr40', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-8, '08:10'), 'creeLe', public.pf_j(-8, '08:10'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3960, 'unite', 'kWh')),
    (k || '-nr41', 'releves', jsonb_build_object('compteurId', k || '-ncl', 'le', public.pf_j(-1, '08:10'), 'creeLe', public.pf_j(-1, '08:10'), 'creePar', 'Technicien B (automatisme)', 'valeur', 5140, 'unite', 'kWh')),
    (k || '-nr42', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-64, '08:15'), 'creeLe', public.pf_j(-64, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3400, 'unite', 'm³')),
    (k || '-nr43', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-57, '08:15'), 'creeLe', public.pf_j(-57, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 3444, 'unite', 'm³')),
    (k || '-nr44', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-50, '08:15'), 'creeLe', public.pf_j(-50, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3491, 'unite', 'm³')),
    (k || '-nr45', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-43, '08:15'), 'creeLe', public.pf_j(-43, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 3534, 'unite', 'm³')),
    (k || '-nr46', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-36, '08:15'), 'creeLe', public.pf_j(-36, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3580, 'unite', 'm³')),
    (k || '-nr47', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-29, '08:15'), 'creeLe', public.pf_j(-29, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 3625, 'unite', 'm³')),
    (k || '-nr48', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-22, '08:15'), 'creeLe', public.pf_j(-22, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3673, 'unite', 'm³')),
    (k || '-nr49', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-15, '08:15'), 'creeLe', public.pf_j(-15, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 4718, 'unite', 'm³')),
    (k || '-nr50', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-8, '08:15'), 'creeLe', public.pf_j(-8, '08:15'), 'creePar', 'Technicien A (mécanique)', 'valeur', 3762, 'unite', 'm³')),
    (k || '-nr51', 'releves', jsonb_build_object('compteurId', k || '-nce', 'le', public.pf_j(-1, '08:15'), 'creeLe', public.pf_j(-1, '08:15'), 'creePar', 'Technicien B (automatisme)', 'valeur', 3808, 'unite', 'm³')),
    (k || '-nr52', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-64, '08:20'), 'creeLe', public.pf_j(-64, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 11800, 'unite', 'h')),
    (k || '-nr53', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-57, '08:20'), 'creeLe', public.pf_j(-57, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 11912, 'unite', 'h')),
    (k || '-nr54', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-50, '08:20'), 'creeLe', public.pf_j(-50, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 12020, 'unite', 'h')),
    (k || '-nr55', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-43, '08:20'), 'creeLe', public.pf_j(-43, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 12135, 'unite', 'h')),
    (k || '-nr56', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-36, '08:20'), 'creeLe', public.pf_j(-36, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 12245, 'unite', 'h')),
    (k || '-nr57', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-29, '08:20'), 'creeLe', public.pf_j(-29, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 12350, 'unite', 'h')),
    (k || '-nr58', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-22, '08:20'), 'creeLe', public.pf_j(-22, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 12468, 'unite', 'h')),
    (k || '-nr59', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-15, '08:20'), 'creeLe', public.pf_j(-15, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 12579, 'unite', 'h')),
    (k || '-nr60', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-8, '08:20'), 'creeLe', public.pf_j(-8, '08:20'), 'creePar', 'Technicien A (mécanique)', 'valeur', 12688, 'unite', 'h')),
    (k || '-nr61', 'releves', jsonb_build_object('compteurId', k || '-nch', 'le', public.pf_j(-1, '08:20'), 'creeLe', public.pf_j(-1, '08:20'), 'creePar', 'Technicien B (automatisme)', 'valeur', 12802, 'unite', 'h')),
    (k || '-npg3', 'programmes', jsonb_build_object('equipementId', comp, 'compteurId', k || '-nch', 'libelle', 'Vidange compresseur selon les heures', 'modele', 'entretien', 'intervalleCompteur', 2000, 'margeCompteur', 200, 'dernierIndex', 10850, 'derniereRealisation', public.pf_j(-120, '10:00'), 'regle', 'apres_realisation', 'instruction', 'Vidange, filtre à huile et séparateur, toutes les 2 000 h de marche.', 'actif', true)),
    (k || '-nf1', 'factures_energie', jsonb_build_object('devise', 'MAD', 'creePar', 'Responsable maintenance', 'ressource', 'electricite', 'fournisseur', 'ONEE', 'reference', 'FAC-ONEE-0001', 'du', public.pf_j(-64), 'au', public.pf_j(-36), 'quantite', 24540, 'unite', 'kWh', 'montantHT', 28957.2, 'compteurIds', jsonb_build_array(k || '-ncg'), 'creeLe', public.pf_j(-34, '11:00'))),
    (k || '-nf2', 'factures_energie', jsonb_build_object('devise', 'MAD', 'creePar', 'Responsable maintenance', 'ressource', 'electricite', 'fournisseur', 'ONEE', 'reference', 'FAC-ONEE-0002', 'du', public.pf_j(-36), 'au', public.pf_j(-8), 'quantite', 26100, 'unite', 'kWh', 'montantHT', 30798, 'compteurIds', jsonb_build_array(k || '-ncg'), 'creeLe', public.pf_j(-6, '11:00'))),
    (k || '-nf3', 'factures_energie', jsonb_build_object('devise', 'MAD', 'creePar', 'Responsable maintenance', 'ressource', 'eau', 'fournisseur', 'Régie de distribution', 'reference', 'FAC-EAU-0001', 'du', public.pf_j(-64), 'au', public.pf_j(-8), 'quantite', 362, 'unite', 'm³', 'montantHT', 3439, 'compteurIds', jsonb_build_array(k || '-nce'), 'creeLe', public.pf_j(-6, '11:30')))
  ) as v(id, type, data);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.pf_demo_energie(uuid, uuid, text, text) from public, anon, authenticated;

-- Version de supabase/demo.sql + appel de pf_demo_energie.
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

  perform public.pf_demo_energie(e.id, site, k, comp);   -- volet D : énergie et eau
  update entreprises set reinit_le = now() where id = e.id;
  return jsonb_build_object('fiches', (select count(*) from fiches where entreprise_id = e.id), 'reinitLe', now());
end $$;
revoke all on function public.pf_reinitialiser_demo(uuid) from public, anon;
grant execute on function public.pf_reinitialiser_demo(uuid) to authenticated;
