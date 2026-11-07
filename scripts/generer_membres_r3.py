"""Génère supabase/membres_r3.sql (lot R3 : membres, équipes, sociétés prestataires, administrateur du client)
à partir des dernières versions de push_fiches (interventions_r2.sql) et des fonctions du R1 (roles_r1.sql).
Usage : python scripts/generer_membres_r3.py — ne pas modifier supabase/membres_r3.sql à la main."""
import os

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SQL = os.path.join(RACINE, "supabase")


def fonction(fichier, nom):
    s = open(os.path.join(SQL, fichier), encoding="utf-8").read().replace("\r\n", "\n")
    i = s.rindex(f"create or replace function public.{nom}(")
    j = s.index("end $$;", i) + len("end $$;")
    return s[i:j]


def remplacer(texte, avant, apres):
    assert avant in texte, avant[:80]
    return texte.replace(avant, apres, 1)


TYPES = "'localisations','equipements','personnes','demandes','ots','programmes','articles','mouvements','journal','photos','besoins','seuils','achats','valorisations','compteurs','releves','factures_energie','parametres','fournisseurs'"
TYPES_R3 = TYPES + ",'equipes'"

# ---------- périmètre du prestataire : + interventions confiées à sa société, + sa fiche société, + équipes ----------
voit = fonction("roles_r1.sql", "prestataire_voit")
voit = remplacer(voit, "if t in ('equipements', 'localisations', 'personnes', 'articles', 'compteurs', 'releves', 'parametres', 'journal') then return true; end if;",
                 "if t in ('equipements', 'localisations', 'personnes', 'articles', 'compteurs', 'releves', 'parametres', 'journal', 'equipes') then return true; end if;\n"
                 "  if t = 'fournisseurs' then return fid = public.ma_societe(); end if;   -- R3 : sa société seulement")
voit = remplacer(voit, """      and o.data->'demandeIds' ? fid and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));""",
                 """      and o.data->'demandeIds' ? fid and public.ot_a_moi(o.id));""")
voit = remplacer(voit, """and o.data->>'programmeId' = fid
      and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));""",
                 """and o.data->>'programmeId' = fid
      and public.ot_a_moi(o.id));""")

journal = fonction("roles_r1.sql", "journal_visible")
journal = remplacer(journal, """      and o.data->'demandeIds' ? x.id and o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne())));""",
                    """      and o.data->'demandeIds' ? x.id and public.ot_a_moi(o.id));""")

# ---------- definir_profil : le compte et la fiche du membre gardent le même nom et le même rôle ;
#            retirer l'accès (compte désactivé) ne rend plus le membre inactif ----------
profil = fonction("roles_r1.sql", "definir_profil")
profil = remplacer(profil, "update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'nom', p.nom, 'actif', p.actif),",
                   "update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'nom', p.nom),")

# ---------- push_fiches ----------
push = fonction("interventions_r2.sql", "push_fiches")
push = remplacer(push, "terrain boolean; mod text; u text;", "terrain boolean; mod text; u text; gere boolean; soi boolean; lie boolean;")
push = remplacer(push, "  terrain := r in ('technicien', 'prestataire');\n",
                 "  terrain := r in ('technicien', 'prestataire');\n"
                 "  gere := r = 'responsable' or public.est_admin_client();   -- R3 : membres, équipes, sociétés prestataires\n")
push = remplacer(push, """      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
""", """      if u = 'equipement' then mod := 'preventif'; end if;
    end if;
    -- R3 : une société prestataire relève du module de base (pas du magasin).
    if cible = 'fournisseurs' and (t = 'journal' or coalesce(p->>'prestataire', ex.data->>'prestataire', '') = 'true') then mod := 'base'; end if;
    -- R3 : sa propre fiche membre (nom, téléphone) ; fiche reliée à un compte (rôle par l'administrateur).
    soi := cible = 'personnes' and coalesce(case when t = 'journal' then p->>'entiteId' else f->>'id' end, '') = coalesce(public.ma_personne(), '-')
           and (t = 'journal' or (ex.id is not null and not exists (
             select 1 from jsonb_object_keys(p) k where k not in ('nom', 'telephone', 'modifieLe', 'modifiePar'))));
    lie := t = 'personnes' and exists (select 1 from profils x where x.personne_id = f->>'id' and x.entreprise_id = ent);
""")
push = remplacer(push, f"    if t not in ({TYPES}) then", f"    if t not in ({TYPES_R3}) then")
push = remplacer(push, """    elsif not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';""",
"""    elsif cible in ('personnes', 'equipes') and not gere and not soi then
      motif := 'membres et équipes : réservés au responsable et à l''administrateur';
    elsif cible not in ('personnes', 'equipes') and not (cible = 'fournisseurs' and gere) and not public.peut_ecrire(r, cible) then
      motif := 'droits insuffisants (' || r || ')';
    elsif t = 'fournisseurs' and not gere and (p->>'prestataire' = 'true' or ex.data->>'prestataire' = 'true') then
      motif := 'société prestataire : réservée au responsable et à l''administrateur';
    elsif lie and ex.id is not null and ((p ? 'role' and p->'role' is distinct from ex.data->'role')
          or (p ? 'actif' and p->'actif' is distinct from ex.data->'actif' and p->'actif' = 'false'::jsonb)) then
      motif := 'membre avec un accès : rôle et accès se changent par l''administrateur (Membres)';
    elsif t = 'ots' and terrain and ((p ? 'equipeId' and p->'equipeId' is distinct from coalesce(ex.data->'equipeId', 'null'::jsonb) and coalesce(p->>'equipeId', '') <> '')
          or (p ? 'societeId' and p->'societeId' is distinct from coalesce(ex.data->'societeId', 'null'::jsonb) and coalesce(p->>'societeId', '') <> '')) then
      motif := 'intervention confiée à une équipe ou une société : réservé au responsable';""")
push = remplacer(push, "if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs') then",
                 "if motif is null and t not in ('personnes', 'articles', 'parametres', 'fournisseurs', 'equipes') then")
push = remplacer(push, """    n := n + 1;
  end loop;""", """    -- R3 : le nom d'un membre avec accès est aussi celui de son compte.
    if t = 'personnes' and lie and coalesce(trim(p->>'nom'), '') <> '' then
      update profils set nom = trim(p->>'nom') where personne_id = f->>'id' and entreprise_id = ent;
    end if;
    n := n + 1;
  end loop;""")

ENTETE = """-- GMAO terrain — lot R3 « membres, équipes, sociétés prestataires » (docs/MAQUETTES_R3.md §1 à §9). APRÈS interventions_r2.sql.
-- Rejouable. FICHIER GÉNÉRÉ par scripts/generer_membres_r3.py : ne pas modifier à la main.
-- Membre = fiche « personnes » (avec ou sans compte) ; le compte (profils.personne_id) y est relié. Nom et rôle d'un membre
--   avec accès : une seule valeur (definir_profil écrit les deux ; le nom changé sur la fiche passe au compte) ; le rôle
--   et la désactivation d'un membre avec accès ne passent pas par la fiche. Retirer l'accès ne rend pas le membre inactif.
-- relier_membre : relie un compte (juste invité) à une fiche membre existante (pas de doublon).
-- Membres, équipes (nouveau type « equipes ») et sociétés prestataires (fiche « fournisseurs » avec prestataire = true,
--   module de base) : écrits par le responsable et l'administrateur ; chacun peut changer son nom et son téléphone.
-- Interventions : equipeId / societeId posés par le responsable (refusés au terrain).
-- Prestataire (Q3 élargi) : voit ses interventions ET celles confiées à sa société (societeId de sa fiche membre), la
--   fiche de sa société et les équipes.
-- Reprise : fiches des comptes alignées (nom, rôle) ; texte libre « societe » → société prestataire + societeId.

alter table public.fiches drop constraint if exists fiches_type_check;
alter table public.fiches add constraint fiches_type_check check (type in (""" + TYPES_R3 + """));

/** Société de l'appelant (fiche « fournisseurs » prestataire), lue sur sa fiche membre. */
create or replace function public.ma_societe()
returns text language sql stable security definer set search_path = public as $$
  select nullif(f.data->>'societeId', '') from fiches f
  where f.id = public.ma_personne() and f.type = 'personnes' and f.entreprise_id = public.mon_entreprise()
$$;
revoke all on function public.ma_societe() from public, anon, authenticated;

/** Intervention confiée à l'appelant : il en est intervenant, ou elle est confiée à sa société. */
create or replace function public.ot_a_moi(oid text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(oid, '') <> '' and exists (
    select 1 from fiches o where o.id = oid and o.type = 'ots' and o.entreprise_id = public.mon_entreprise()
      and (o.data->'intervenants' @> jsonb_build_array(jsonb_build_object('personneId', public.ma_personne()))
           or (public.ma_societe() is not null and o.data->>'societeId' = public.ma_societe())))
$$;
revoke all on function public.ot_a_moi(text) from public, anon, authenticated;

"""

RELIER = """
revoke all on function public.prestataire_voit(text, text, jsonb, uuid) from public, anon;
grant execute on function public.prestataire_voit(text, text, jsonb, uuid) to authenticated;   -- appelée par la règle de lecture
revoke all on function public.journal_visible(jsonb, uuid) from public, anon;
grant execute on function public.journal_visible(jsonb, uuid) to authenticated;
revoke all on function public.definir_profil(uuid, text, text, boolean) from public, anon;
grant execute on function public.definir_profil(uuid, text, text, boolean) to authenticated;

/** Relier un compte de l'entreprise à une fiche membre existante (après « Donner un accès »). La fiche prend le rôle
    du compte ; le compte prend le nom de la fiche ; l'ancienne fiche du compte, s'il en avait une autre, devient inactive. */
create or replace function public.relier_membre(cible uuid, personne text)
returns void language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); ancien text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  if not public.est_admin_client() then raise exception 'Réservé à l''administrateur de l''entreprise' using errcode = '42501'; end if;
  if not exists (select 1 from profils where user_id = cible and entreprise_id = ent) then
    raise exception 'Compte hors de votre entreprise' using errcode = '42501';
  end if;
  if not exists (select 1 from fiches where id = personne and type = 'personnes' and entreprise_id = ent) then
    raise exception 'Membre inconnu de l''entreprise';
  end if;
  if exists (select 1 from profils where personne_id = personne and user_id <> cible) then
    raise exception 'Ce membre a déjà un autre accès';
  end if;
  select personne_id into ancien from profils where user_id = cible;
  update profils set personne_id = personne,
    nom = coalesce(nullif(trim((select data->>'nom' from fiches where id = personne)), ''), nom) where user_id = cible;
  update fiches set data = fiches.data || jsonb_build_object('role', p.role, 'email', p.email, 'actif', true,
      'modifieLe', maintenant, 'modifiePar', 'serveur'), seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.user_id = cible and fiches.id = personne;
  if ancien is not null and ancien <> personne then
    update fiches set data = data || jsonb_build_object('actif', false, 'remplaceePar', personne, 'modifieLe', maintenant, 'modifiePar', 'serveur'),
      seq = nextval('public.fiches_seq'), recu_le = now()
    where id = ancien and type = 'personnes' and entreprise_id = ent;
  end if;
end $$;
revoke all on function public.relier_membre(uuid, text) from public, anon;
grant execute on function public.relier_membre(uuid, text) to authenticated;

-- ---------- Reprise de l'existant (rejouable : ne refait rien la deuxième fois) ----------
create or replace function public.r3_reprise()
returns void language plpgsql security definer set search_path = public as $$
declare x record; sid text; maintenant text := to_char(now() at time zone 'Africa/Casablanca', 'YYYY-MM-DD"T"HH24:MI');
begin
  -- 1) fiche d'un compte : même nom et même rôle que le compte
  update fiches f set data = f.data || jsonb_build_object('nom', coalesce(nullif(trim(p.nom), ''), f.data->>'nom'), 'role', p.role),
    seq = nextval('public.fiches_seq'), recu_le = now()
  from profils p where p.personne_id = f.id and f.type = 'personnes' and f.entreprise_id = p.entreprise_id
    and (f.data->>'role' is distinct from p.role or (coalesce(trim(p.nom), '') <> '' and f.data->>'nom' is distinct from trim(p.nom)));
  -- 2) texte libre « societe » → société prestataire (même nom sans casse ni accents) + societeId
  for x in select f.id, f.entreprise_id, trim(f.data->>'societe') as nom from fiches f
           where f.type = 'personnes' and coalesce(trim(f.data->>'societe'), '') <> '' and coalesce(f.data->>'societeId', '') = '' loop
    select s.id into sid from fiches s where s.type = 'fournisseurs' and s.entreprise_id = x.entreprise_id
      and lower(translate(trim(s.data->>'nom'), 'ÀÂÄÉÈÊËÎÏÔÖÙÛÜÇàâäéèêëîïôöùûüç', 'AAAEEEEIIOOUUUCaaaeeeeiioouuuc'))
        = lower(translate(x.nom, 'ÀÂÄÉÈÊËÎÏÔÖÙÛÜÇàâäéèêëîïôöùûüç', 'AAAEEEEIIOOUUUCaaaeeeeiioouuuc')) limit 1;
    if sid is null then
      sid := 'soc-' || substr(md5(x.entreprise_id::text || lower(x.nom)), 1, 16);
      insert into fiches (id, type, data, entreprise_id) values (sid, 'fournisseurs', jsonb_build_object('id', sid, 'nom', x.nom,
        'prestataire', true, 'actif', true, 'creeLe', maintenant, 'creePar', 'serveur', 'modifieLe', maintenant, 'modifiePar', 'serveur'), x.entreprise_id)
      on conflict (id) do nothing;
    else
      update fiches set data = data || '{"prestataire":true}'::jsonb, seq = nextval('public.fiches_seq'), recu_le = now()
      where id = sid and data->>'prestataire' is distinct from 'true';
    end if;
    update fiches set data = data || jsonb_build_object('societeId', sid), seq = nextval('public.fiches_seq'), recu_le = now() where id = x.id;
    sid := null;
  end loop;
end $$;
revoke all on function public.r3_reprise() from public, anon, authenticated;
select public.r3_reprise();

"""

FIN = """
revoke all on function public.push_fiches(jsonb) from public, anon;
grant execute on function public.push_fiches(jsonb) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
"""

sortie = ENTETE + voit + "\n\n" + journal + "\n\n" + profil + "\n" + RELIER + push + "\n" + FIN
open(os.path.join(SQL, "membres_r3.sql"), "w", encoding="utf-8", newline="\n").write(sortie)
print(f"supabase/membres_r3.sql : {len(sortie) // 1024} Ko")
