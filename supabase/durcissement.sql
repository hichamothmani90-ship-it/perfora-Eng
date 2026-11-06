-- GMAO terrain — durcissement (recette A5, 6 nov. 2026). Rejouable.
-- Les fonctions internes ne sont appelées que depuis d'autres fonctions SECURITY DEFINER
-- (exécutées avec les droits du propriétaire) : aucune raison de les exposer à l'API.
-- Constat : nb_actifs_entreprise / nb_actifs_site (SECURITY DEFINER) étaient appelables sans compte
-- et révélaient le nombre d'utilisateurs actifs d'une entreprise dont on connaîtrait l'identifiant.
revoke execute on function public.nb_actifs_entreprise(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.nb_actifs_site(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.exiger_admin() from public, anon, authenticated;
revoke execute on function public.peut_ecrire(text, text) from public, anon, authenticated;
revoke execute on function public.module_de(text) from public, anon, authenticated;
revoke execute on function public.uuid_ou_null(text) from public, anon, authenticated;
revoke execute on function public.pf_j(integer, text) from public, anon, authenticated;

-- Contrôle : aucune fonction du schéma public ne doit rester appelable sans compte.
select p.proname as encore_ouverte_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');

-- Conseiller sécurité Supabase (recette A5) :
-- 1) chemin de recherche fixé pour les fonctions utilitaires
alter function public.peut_ecrire(text, text) set search_path = public;
alter function public.module_de(text) set search_path = public;
alter function public.uuid_ou_null(text) set search_path = public;
alter function public.pf_j(integer, text) set search_path = public;
-- 2) fonctions de déclencheurs : jamais appelées directement (les déclencheurs fonctionnent sans ce droit)
revoke execute on function public.creer_profil() from public, anon, authenticated;
revoke execute on function public.quota_profils() from public, anon, authenticated;
revoke execute on function public.quota_profil_sites() from public, anon, authenticated;
revoke execute on function public.quota_sites() from public, anon, authenticated;
-- 3) droits_entreprise(ent) : utilisée seulement par d'autres fonctions ; pas d'appel direct
--    (sinon un compte connecté pourrait lire le pack d'une autre entreprise dont il connaîtrait l'id).
revoke execute on function public.droits_entreprise(uuid) from public, anon, authenticated;
-- Restent appelables par un compte connecté (avertissements acceptés : chaque fonction vérifie
-- elle-même rôle, entreprise et site) : push_fiches, mon_profil, definir_profil, affecter_sites,
-- utilisation, preparer_invitation, pf_* (administrateur plateforme), et mon_role / mon_entreprise /
-- mes_sites / est_admin_plateforme, nécessaires aux règles de lecture (RLS).
