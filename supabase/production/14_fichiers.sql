-- ===== 14_fichiers.sql — copie générée de supabase/fichiers.sql (empreinte 6a2a3f29721b1996) : ne pas modifier ici =====
-- GMAO terrain — fichiers joints (photos et PDF) dans Supabase Storage (rejouable). APRÈS references.sql.
-- Voir docs/PLANNING_ACTUALISE.md (1.2). Les fichiers ne sont plus dans la base : la fiche « photos » garde seulement
-- la description (chemin, type, taille, nom) et l'appli envoie le fichier lui-même dans l'espace « fichiers ».
--
-- Chemin d'un fichier : <entreprise>/<site ou « commun »>/<catégorie>/<identifiant>.<extension>
--   catégorie : photos | documents | couts (pièces jointes de factures et d'achats : lecture restreinte comme les prix)
-- Règles : on ne lit et n'écrit que dans son entreprise et ses sites ; « couts » réservé aux rôles qui voient les coûts ;
-- écriture refusée au pilote et si l'abonnement est en lecture seule ; un fichier déposé ne se remplace ni ne s'efface
-- (aucune règle de modification ni de suppression).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fichiers', 'fichiers', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.fichier_autorise(p_nom text, p_ecrire boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare d text[] := string_to_array(p_nom, '/'); r text := public.mon_role(); ent uuid := public.mon_entreprise(); site uuid;
begin
  if r is null or ent is null or array_length(d, 1) <> 4 then return false; end if;
  if d[1] <> ent::text then return false; end if;
  if d[3] not in ('photos', 'documents', 'couts') then return false; end if;
  if d[3] = 'couts' and not public.voit_couts() then return false; end if;
  if d[2] <> 'commun' then
    site := public.uuid_ou_null(d[2]);
    if site is null or not (site in (select public.mes_sites())) then return false; end if;
  end if;
  if p_ecrire then
    if r = 'pilote' then return false; end if;
    if not coalesce((public.droits_entreprise(ent)->>'ecriture')::boolean, false) then return false; end if;
    if d[4] !~ '^[A-Za-z0-9_-]{6,80}\.(jpg|jpeg|png|webp|pdf)$' then return false; end if;
  end if;
  return true;
end $$;
revoke all on function public.fichier_autorise(text, boolean) from public, anon;
grant execute on function public.fichier_autorise(text, boolean) to authenticated;

drop policy if exists "fichiers lecture" on storage.objects;
create policy "fichiers lecture" on storage.objects for select to authenticated
  using (bucket_id = 'fichiers' and public.fichier_autorise(name, false));
drop policy if exists "fichiers depot" on storage.objects;
create policy "fichiers depot" on storage.objects for insert to authenticated
  with check (bucket_id = 'fichiers' and public.fichier_autorise(name, true));

-- Occupation par entreprise (centre de contrôle : limite de l'offre gratuite = 1 Go au total).
create or replace function public.pf_stockage()
returns jsonb language plpgsql stable security definer set search_path = public, storage as $$
begin
  perform public.exiger_admin();
  return jsonb_build_object(
    'total', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'fichiers'),
    'parEntreprise', (select coalesce(jsonb_object_agg(e, o), '{}'::jsonb) from (
      select split_part(name, '/', 1) e, sum((metadata->>'size')::bigint) o from storage.objects where bucket_id = 'fichiers' group by 1) z),
    'base', pg_database_size(current_database()));
end $$;
revoke all on function public.pf_stockage() from public, anon;
grant execute on function public.pf_stockage() to authenticated;
