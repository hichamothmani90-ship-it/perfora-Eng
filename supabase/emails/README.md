# E-mails d'authentification Perfora (Supabase)

Supabase → Authentication → Emails → Templates. Copier le **sujet** et le contenu HTML du fichier.
Le lien `{{ .ConfirmationURL }}` est conservé tel quel : l'appli lit la session dans l'adresse au retour
(`Sync.lireLienEmail`), rien d'autre ne change. Envoi : Resend, expéditeur « Perfora » <no-reply@perfora.ma>.

| Modèle Supabase | Fichier | Sujet |
|---|---|---|
| Invite user | `invitation.html` | Votre accès à Perfora |
| Reset password | `mot_de_passe.html` | Réinitialiser votre mot de passe Perfora |
| Magic link | `lien_connexion.html` | Votre lien de connexion Perfora |
| Confirm signup | `confirmation.html` | Confirmez votre adresse e-mail — Perfora |
| Change email address | `changement_email.html` | Confirmez votre nouvelle adresse e-mail — Perfora |
| Reauthentication | `code_verification.html` | Votre code de confirmation Perfora |
