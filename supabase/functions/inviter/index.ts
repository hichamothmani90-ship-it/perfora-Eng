// Fonction serveur « inviter » (Supabase Edge Function) — volet A3.
// Seul endroit qui utilise la clé secrète (SUPABASE_SERVICE_ROLE_KEY, fournie par Supabase,
// jamais présente dans l'appli). Étapes :
//  1. contrôle au nom du responsable connecté : rôle, sites, places libres (preparer_invitation)
//  2. envoi de l'e-mail d'invitation (sauf compte existant non rattaché)
//  3. rattachement du compte : entreprise, rôle, sites (finaliser_invitation ; quotas revérifiés
//     par les déclencheurs). En cas d'échec, le compte tout juste invité est supprimé.
// Déploiement : Supabase → Edge Functions → Deploy a new function → Via Editor → nom « inviter »,
// coller ce fichier, laisser « Verify JWT » activé.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const repondre = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return repondre({ erreur: 'Méthode non autorisée' }, 405);
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const secrete = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const { email, role, nom, sites, redirectTo } = await req.json();
    if (!email || !role || !Array.isArray(sites) || !sites.length) return repondre({ erreur: 'E-mail, rôle et au moins un site sont requis' }, 400);

    // 1. Contrôle au nom de l'appelant (son jeton : auth.uid() = le responsable).
    const appelant = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
    const { data: ctrl, error: e1 } = await appelant.rpc('preparer_invitation', { p_email: email, p_role: role, p_sites: sites });
    if (e1) return repondre({ erreur: e1.message }, 400);

    // 2. Invitation (clé secrète, côté serveur uniquement).
    const admin = createClient(url, secrete, { auth: { persistSession: false, autoRefreshToken: false } });
    let userId: string = ctrl.user_id_existant;
    const nouveau = !userId;
    if (nouveau) {
      const { data, error } = await admin.auth.admin.inviteUserByEmail(String(email).trim().toLowerCase(), redirectTo ? { redirectTo } : undefined);
      if (error) return repondre({ erreur: /rate limit/i.test(error.message) ? 'Trop d’e-mails envoyés : réessayez dans une heure' : error.message }, 400);
      userId = data.user.id;
    }

    // 3. Rattachement à l'entreprise et aux sites (quotas revérifiés par la base).
    const { error: e3 } = await admin.rpc('finaliser_invitation', { p_user: userId, p_entreprise: ctrl.entreprise_id, p_role: role, p_nom: nom ?? null, p_sites: sites });
    if (e3) {
      if (nouveau) await admin.auth.admin.deleteUser(userId);
      return repondre({ erreur: e3.message }, 400);
    }
    return repondre({ ok: true, userId, emailEnvoye: nouveau });
  } catch (e) {
    return repondre({ erreur: String((e as Error)?.message ?? e) }, 500);
  }
});
