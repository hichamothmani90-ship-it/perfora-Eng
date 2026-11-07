"""Lot S2 de stabilisation (docs/AUDIT_STABILITE_MODELE.md §4 E, F, G, H, K).
Génère supabase/stabilite_s2.sql (import renuméroté, code appareil unique, contrôle du contenu et des liens, rapport des
fiches anormales) et, UNE SEULE FOIS, supabase/push_fiches.sql : depuis S2, push_fiches vit dans ce fichier, modifié à la
main (fin de la chaîne de scripts qui réécrivaient la fonction lot après lot).
Usage : python scripts/generer_stabilite_s2.py [--push]   (--push : regénère push_fiches.sql depuis magasin_r5.sql en
écrasant les modifications faites à la main ; à ne plus utiliser une fois push_fiches.sql modifié)."""
import os, sys

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


# ---------- E : l'import renumérote ses fiches juste avant de valider ----------
imp = fonction("mise_en_service.sql", "pf_importer")
imp = remplacer(imp, """  if not p_essai and jsonb_array_length(refus) = 0 then
    insert into pf_lots_import""", """  if not p_essai and jsonb_array_length(refus) = 0 then
    -- S2 (risque E) : une longue transaction prend ses numéros au début ; les téléphones qui lisent pendant l'import
    -- avancent leur curseur au-delà et ne reçoivent jamais une partie des fiches. Renumérotées à la fin, elles passent
    -- après tout ce qui a été lu entre-temps (essai du 7 nov. : 101 fiches sur 300 perdues sans ce correctif, 0 avec).
    update fiches set seq = nextval('public.fiches_seq') where entreprise_id = p_entreprise and data->>'lotImport' = p_lot;
    insert into pf_lots_import""")

ENTETE = """-- GMAO terrain — lot S2 de stabilisation (docs/AUDIT_STABILITE_MODELE.md §4 E, F, G, K). APRÈS magasin_r5.sql,
-- AVANT push_fiches.sql. Rejouable. FICHIER GÉNÉRÉ par scripts/generer_stabilite_s2.py : ne pas modifier à la main.
-- E : pf_importer renumérote ses fiches avant de valider (curseur des téléphones sûr pendant un import).
-- F : code appareil unique dans l'entreprise (références lisibles OT-K3-0007 sans doublon) : appareil_code.
-- G : contrôle léger du contenu (statuts, natures, priorités, types, quantités, dates) : s2_controle.
-- K : liens vérifiés à la création (intervention, article, besoin, équipe, société) : s2_lien.
-- Rapport des fiches anormales pour la console : pf_fiches_anormales.

-- ---------- F : code appareil ----------
create table if not exists public.pf_appareils (
  entreprise_id uuid not null references public.entreprises(id) on delete cascade,
  code text not null, appareil text not null, user_id uuid, cree_le timestamptz not null default now(),
  primary key (entreprise_id, code));
alter table public.pf_appareils enable row level security;
revoke all on public.pf_appareils from public, anon, authenticated;

/** Code de l'appareil, unique dans l'entreprise : le sien s'il est libre (ou déjà à lui), sinon un nouveau.
    Un code n'est jamais redonné à un autre appareil (même après « Effacer cet appareil »). */
create or replace function public.appareil_code(p_code text, p_appareil text)
returns text language plpgsql security definer set search_path = public as $$
declare ent uuid := public.mon_entreprise(); c text; a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i integer;
begin
  if ent is null then raise exception 'Compte sans entreprise' using errcode = '42501'; end if;
  if coalesce(p_appareil, '') = '' or length(p_appareil) > 64 then raise exception 'Appareil inconnu'; end if;
  select code into c from pf_appareils where entreprise_id = ent and appareil = p_appareil order by cree_le limit 1;
  if c is not null then return c; end if;   -- appareil déjà inscrit : il garde son code
  perform public.limiter('appareil:' || ent::text, 60, interval '1 hour', 'Trop de nouveaux appareils en une heure : réessayez plus tard');
  if p_code ~ '^[A-Z0-9]{2,4}$' and not exists (select 1 from pf_appareils where entreprise_id = ent and code = p_code) then
    insert into pf_appareils (entreprise_id, code, appareil, user_id) values (ent, p_code, p_appareil, auth.uid());
    return p_code;
  end if;
  for i in 1 .. 200 loop
    c := substr(a, 1 + floor(random() * 32)::int, 1) || substr(a, 1 + floor(random() * 32)::int, 1)
         || case when i > 100 then substr(a, 1 + floor(random() * 32)::int, 1) else '' end;
    if not exists (select 1 from pf_appareils where entreprise_id = ent and code = c) then
      insert into pf_appareils (entreprise_id, code, appareil, user_id) values (ent, c, p_appareil, auth.uid());
      return c;
    end if;
  end loop;
  raise exception 'Aucun code appareil libre';
end $$;
revoke all on function public.appareil_code(text, text) from public, anon;
grant execute on function public.appareil_code(text, text) to authenticated;

-- ---------- G : contrôle léger du contenu ----------
/** Motif si une valeur du patch n'est pas reconnue (null = accepté). Seuls les champs présents sont contrôlés ;
    une valeur vide (null) est toujours acceptée. */
create or replace function public.s2_controle(t text, p jsonb)
returns text language plpgsql immutable set search_path = public as $$
declare k text; v jsonb; permis text[];
begin
  for k, v in select key, value from jsonb_each(p) loop
    continue when v is null or jsonb_typeof(v) = 'null';
    permis := case
      when t = 'ots' and k = 'statut' then array['a_preparer','a_planifier','planifiee','prete','en_cours','suspendue','travail_termine','cloturee','annulee']
      when t = 'ots' and k in ('nature', 'natureProposee') then array['a_qualifier','corrective','preventive','assistance_production','travaux_techniques']
      when t = 'ots' and k in ('priorite', 'prioriteProposee') then array['urgence_securite','critique_service','rapide','planifiable','a_qualifier']
      when t = 'ots' and k = 'avecArret' then array['oui','non','inconnu']
      when t = 'ots' and k = 'arretType' then array['planifie','non_planifie']
      when t = 'demandes' and k = 'statut' then array['a_examiner','prise_en_charge','traitement_organise','close_sans_travail','annulee']
      when t = 'besoins' and k = 'statut' then array['demande','reserve','indisponible','annule','partiellement_remis','remis']
      when t = 'mouvements' and k = 'type' then array['entree','sortie','remise','retour','rebut','ajustement','isolement','liberation','disposition']
      when t = 'achats' and k = 'statut' then array['brouillon','soumise','a_completer','validee','refusee','transmise','commandee','partiellement_recue','recue','close','annulee']
      else null end;
    if permis is not null and (jsonb_typeof(v) <> 'string' or not (v #>> '{}') = any (permis)) then
      return 'valeur non reconnue pour « ' || k || ' » : ' || left(v::text, 40) || ' (mettez l''appli à jour)';
    end if;
    if ((t in ('besoins', 'mouvements') and k in ('qte', 'qteReservee', 'quantite')) or (t = 'releves' and k = 'valeur'))
       and jsonb_typeof(v) <> 'number' then
      return 'quantité non numérique pour « ' || k || ' »';
    end if;
    if k in ('creeLe','modifieLe','le','demandeLe','depuis','fin','arretDebut','arretFin','arretPrevuDebut','arretPrevuFin','creneau',
             'echeance','clotureLe','dateCommande','livraisonPrevue','valideLe','soumiseLe','redigeLe','delai','reserveLe','contratFin')
       and jsonb_typeof(v) = 'string' and v #>> '{}' <> ''
       and v #>> '{}' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2}([.][0-9]+)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$' then
      return 'date mal formée pour « ' || k || ' » : ' || left(v #>> '{}', 30);
    end if;
  end loop;
  return null;
end $$;
revoke all on function public.s2_controle(text, jsonb) from public, anon, authenticated;

-- ---------- K : liens vérifiés ----------
/** Motif si un lien du patch pointe vers une fiche absente de l'entreprise (null = accepté). À la création pour les
    liens de rattachement ; à chaque écriture pour l'équipe et la société d'une intervention. */
create or replace function public.s2_lien(t text, p jsonb, ent uuid, nouvelle boolean)
returns text language plpgsql stable security definer set search_path = public as $$
declare k text; cible text;
begin
  for k, cible in select x.champ, x.ct from (values
      ('besoins', 'otId', 'ots', true), ('besoins', 'articleId', 'articles', true),
      ('mouvements', 'articleId', 'articles', true), ('mouvements', 'besoinId', 'besoins', true), ('mouvements', 'otId', 'ots', true),
      ('ots', 'equipeId', 'equipes', false), ('ots', 'societeId', 'fournisseurs', false)) x(ty, champ, ct, creation)
    where x.ty = t and (nouvelle or not x.creation) and coalesce(p->>x.champ, '') <> ''
    loop
    if not exists (select 1 from fiches y where y.id = p->>k and y.type = cible and y.entreprise_id = ent) then
      return 'lien vers une fiche inconnue de l''entreprise (' || k || ')';
    end if;
  end loop;
  return null;
end $$;
revoke all on function public.s2_lien(text, jsonb, uuid, boolean) from public, anon, authenticated;

-- ---------- Rapport des fiches anormales (console) ----------
/** Par entreprise : fiches dont le contenu n'est pas reconnu, liens cassés, fiches sans date de création. */
create or replace function public.pf_fiches_anormales()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.exiger_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('code', e.code, 'nom', e.nom, 'fiches', r.n, 'contenu', r.contenu, 'liens', r.liens,
      'sansCreeLe', r.sans_cree, 'exemples', r.exemples) order by e.code)
    from entreprises e cross join lateral (
      select count(*) n,
        count(*) filter (where x.type <> 'journal' and public.s2_controle(x.type, x.data) is not null) contenu,
        count(*) filter (where public.s2_lien(x.type, x.data, e.id, true) is not null) liens,
        count(*) filter (where x.type not in ('journal', 'mouvements', 'photos') and coalesce(x.data->>'creeLe', '') = '') sans_cree,
        (select jsonb_agg(z) from (select jsonb_build_object('id', y.id, 'type', y.type,
            'motif', coalesce(public.s2_controle(y.type, y.data), public.s2_lien(y.type, y.data, e.id, true))) z
          from fiches y where y.entreprise_id = e.id and y.type <> 'journal'
            and (public.s2_controle(y.type, y.data) is not null or public.s2_lien(y.type, y.data, e.id, true) is not null) limit 5) w) exemples
      from fiches x where x.entreprise_id = e.id) r), '[]'::jsonb);
end $$;
revoke all on function public.pf_fiches_anormales() from public, anon;
grant execute on function public.pf_fiches_anormales() to authenticated;

"""

FIN = """
-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
"""

grants_imp = """
revoke all on function public.pf_importer(uuid, text, text, jsonb, boolean) from public, anon;
grant execute on function public.pf_importer(uuid, text, text, jsonb, boolean) to authenticated;
"""
sortie = ENTETE + imp + "\n" + grants_imp + FIN
open(os.path.join(SQL, "stabilite_s2.sql"), "w", encoding="utf-8", newline="\n").write(sortie)
print(f"supabase/stabilite_s2.sql : {len(sortie) // 1024} Ko")

# ---------- push_fiches.sql : source unique, à la main ensuite ----------
cible = os.path.join(SQL, "push_fiches.sql")
if os.path.exists(cible) and "--push" not in sys.argv:
    print("supabase/push_fiches.sql existe : non regénéré (source maintenue à la main)")
    sys.exit(0)
push = fonction("magasin_r5.sql", "push_fiches")
push = remplacer(push, """    elsif t = 'ots' and terrain and (p->'qualificationValidee' = 'true'::jsonb or p ? 'qualifieePar' or p ? 'qualifieeLe') then""",
"""    -- S2 (G, K) : contenu reconnu et liens existants.
    elsif t <> 'journal' and public.s2_controle(t, p) is not null then
      motif := public.s2_controle(t, p);
    elsif t <> 'journal' and public.s2_lien(t, p, ent, ex.id is null) is not null then
      motif := public.s2_lien(t, p, ent, ex.id is null);
    elsif t = 'ots' and terrain and (p->'qualificationValidee' = 'true'::jsonb or p ? 'qualifieePar' or p ? 'qualifieeLe') then""")
TETE = """-- GMAO terrain — push_fiches : réception des envois des appareils (contrôle, fusion, écriture). APRÈS stabilite_s2.sql.
-- SOURCE UNIQUE depuis le lot S2 (7 nov. 2026) : modifier CE fichier à la main. Les fichiers précédents (schema.sql …
-- magasin_r5.sql) gardent des versions antérieures de la fonction pour l'historique ; la séquence de construction
-- les rejoue dans l'ordre et celle-ci, jouée en dernier, est la seule active. Rejouable.
-- Chaque règle porte le lot qui l'a introduite (R1, R2, R3, S1, R5, S2…). Après une modification : tests SQL
-- (scripts/sauvegarde/tester_sql.sh), même règle dans tests/serveur_factice.py, tests/coherence_modele_test.py.

"""
FINP = """
revoke all on function public.push_fiches(jsonb, text) from public, anon;
grant execute on function public.push_fiches(jsonb, text) to authenticated;
"""
open(cible, "w", encoding="utf-8", newline="\n").write(TETE + push + "\n" + FINP)
print("supabase/push_fiches.sql : écrit (source unique désormais)")
