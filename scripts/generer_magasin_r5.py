"""Génère supabase/magasin_r5.sql (lot R5 : magasin ↔ achats relié — achat urgent, qui commande) à partir de la dernière
version de push_fiches (stabilite_s1.sql).
Usage : python scripts/generer_magasin_r5.py — ne pas modifier supabase/magasin_r5.sql à la main."""
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


push = fonction("stabilite_s1.sql", "push_fiches")
push = remplacer(push, """    elsif t = 'achats' and r = 'achats' and ex.id is null then""",
"""    -- R5 : une demande urgente porte son motif ; la commande d'une demande validée (ou urgente, avant validation) est
    -- renseignée par la personne qui commande (Achats, ou le magasinier si le réglage le désigne).
    elsif t = 'achats' and coalesce(p->'urgent', ex.data->'urgent') = 'true'::jsonb
          and coalesce(nullif(trim(coalesce(p->>'motifUrgence', ex.data->>'motifUrgence')), ''), '') = '' then
      motif := 'achat urgent : indiquer le motif (ex. machine à l''arrêt)';
    elsif t = 'achats' and ex.id is not null and r in ('achats', 'magasinier') and public.r5_commande_acceptee(r, ex.data, p, ent) then
      motif := null;
    elsif t = 'achats' and r = 'achats' and ex.id is null then""")

push = remplacer(push, """    -- R3 : le nom d'un membre avec accès est aussi celui de son compte.
""", """    -- R5 : les pièces liées à une demande d'achat reçoivent son résumé sans prix (les techniciens ne lisent pas les achats).
    if t = 'achats' then perform public.r5_suivi_besoins(f->>'id', ent); end if;
    -- R3 : le nom d'un membre avec accès est aussi celui de son compte.
""")

ENTETE = """-- GMAO terrain — lot R5 « magasin ↔ achats relié » (docs/MAQUETTES_R5.md §4, §5, §9). APRÈS stabilite_s1.sql. Rejouable.
-- FICHIER GÉNÉRÉ par scripts/generer_magasin_r5.py : ne pas modifier à la main.
-- Achat urgent (R5-b) : motif obligatoire ; la commande peut être renseignée avant la validation, le responsable valide
--   ensuite (validation après coup : droits du responsable, inchangés).
-- Qui commande (R5-c, Q2 bis) : réglage de l'entreprise parametres.quiCommande = achats (défaut) | responsable |
--   magasinier ; le rôle Achats et le responsable peuvent toujours ; le magasinier seulement si le réglage le désigne.
-- Les liens pièce ↔ demande d'achat (besoins.achatId, lignes.besoinId) et la réservation à la réception restent
-- dans les droits actuels du magasin.

/** Réglage « qui commande » de l'entreprise (achats par défaut). */
create or replace function public.r5_qui_commande(ent uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select nullif(data->>'quiCommande', '') from fiches
                   where id = 'parametres-' || ent::text and type = 'parametres' and entreprise_id = ent), 'achats')
$$;
revoke all on function public.r5_qui_commande(uuid) from public, anon, authenticated;

/** Résumé d'une demande d'achat recopié sur les pièces (besoins) de ses lignes : référence, étape, urgence, fournisseur,
    dates — jamais de prix. Les techniciens suivent ainsi leur pièce sans lire les achats (lecture restreinte). */
create or replace function public.r5_suivi_besoins(daid text, ent uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d jsonb; l jsonb; resume jsonb;
begin
  select data into d from fiches where id = daid and type = 'achats' and entreprise_id = ent;
  if d is null then return; end if;
  for l in select value from jsonb_array_elements(case when jsonb_typeof(d->'lignes') = 'array' then d->'lignes' else '[]'::jsonb end) loop
    continue when coalesce(l->>'besoinId', '') = '';
    resume := jsonb_strip_nulls(jsonb_build_object('achatId', daid, 'ligneId', l->>'id', 'ref', d->>'ref', 'statut', d->>'statut',
      'urgent', d->'urgent', 'fournisseur', d->>'fournisseur', 'dateCommande', d->>'dateCommande',
      'livraisonPrevue', d->>'livraisonPrevue', 'valideLe', d->>'valideLe', 'qte', coalesce(l->'qteCommandee', l->'qte')));
    update fiches set data = data || jsonb_build_object('suiviAchat', resume), seq = nextval('public.fiches_seq'), recu_le = now()
    where id = l->>'besoinId' and type = 'besoins' and entreprise_id = ent and data->'suiviAchat' is distinct from resume;
  end loop;
end $$;
revoke all on function public.r5_suivi_besoins(text, uuid) from public, anon, authenticated;

/** Écriture de la commande acceptée : seulement les champs de la commande, par une personne qui commande, sur une
    demande validée ou urgente (soumise). */
create or replace function public.r5_commande_acceptee(r text, d jsonb, p jsonb, ent uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (r = 'achats' or (r = 'magasinier' and public.r5_qui_commande(ent) = 'magasinier'))
     and coalesce(p->>'statut', 'commandee') in ('transmise', 'commandee')
     and (coalesce(d->>'statut', '') in ('validee', 'transmise', 'commandee', 'partiellement_recue', 'recue')
          or (d->'urgent' = 'true'::jsonb and coalesce(d->>'statut', '') = 'soumise'))
     and not exists (select 1 from jsonb_object_keys(p) k where k not in ('statut', 'fournisseur', 'fournisseurId', 'refCommande',
           'dateCommande', 'livraisonPrevue', 'devise', 'taux', 'lignes', 'commandeLe', 'commandePar', 'modifieLe', 'modifiePar'))
$$;
revoke all on function public.r5_commande_acceptee(text, jsonb, jsonb, uuid) from public, anon, authenticated;

"""

FIN = """
revoke all on function public.push_fiches(jsonb, text) from public, anon;
grant execute on function public.push_fiches(jsonb, text) to authenticated;

-- Contrôle : aucune fonction du schéma public appelable sans compte.
select coalesce(json_agg(p.proname), '[]')::text as encore_ouvertes_sans_compte
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute');
"""

sortie = ENTETE + push + "\n" + FIN
open(os.path.join(SQL, "magasin_r5.sql"), "w", encoding="utf-8", newline="\n").write(sortie)
print(f"supabase/magasin_r5.sql : {len(sortie) // 1024} Ko")
