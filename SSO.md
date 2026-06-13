# byresha SSO — how it works & how to wire an app

Canonical guide for the **shared identity** (one Cognito pool, all apps). This is the
authoritative "how to set up SSO" doc; per-app folders have a short `SSO.md` that points
here with their specific values.

## Deployed values (dev) — 2026-06-12

| Thing | Value |
|---|---|
| User pool id | `us-east-1_b62r4VVXl` |
| Issuer URL (JWT authorizer) | `https://cognito-idp.us-east-1.amazonaws.com/us-east-1_b62r4VVXl` |
| Login / Hosted-UI domain | `https://byresha-id-dev-a3575f48.auth.us-east-1.amazoncognito.com` |
| stowage client id | `6kua8n7l0p8863t7idbfrf19j5` — group `app:stowage` |
| pulse client id | `5dgp113uvv7o3qj3ptl028udse` — group `app:pulse` |
| nudge client id | `40u4bhd3t6h0ncfj217mm6q164` — group `app:nudge` |
| State | bucket `identity-terraform-state-byreshb`, key `identity/terraform.tfstate` |

> Always read live values from `terraform -chdir=identity/terraform output` rather than
> copying — ids change if the pool is recreated.

## Why a default (amazoncognito.com) login domain, not auth.byresha.com

A Cognito **custom** domain (`auth.byresha.com`) requires an **A record on the apex
`byresha.com`**, which we deliberately do **not** touch (nor `pulse.`/`nudge.` records).
So we use Cognito's free default domain. SSO is identical — only the login page URL
differs. To adopt `auth.byresha.com` later: add an apex A record, then restore an ACM
cert (us-east-1) + custom-domain config in `terraform/domain.tf`.

## The two halves

- **Authentication (who you are):** the shared Hosted UI. Sign in once → the browser
  holds a session at the login domain → other apps sign in silently. That's the SSO.
- **Authorization (what you can open):** Cognito **groups**. Each app's Lambda checks the
  `cognito:groups` claim contains `app:<name>`; if not → **403**. Membership is granted
  per user, per app.

## Wiring an app to the shared pool (4 steps)

1. **API Gateway JWT authorizer** → point at the shared issuer + that app's client id:
   ```hcl
   jwt_configuration {
     audience = ["<app client id>"]
     issuer   = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_b62r4VVXl"
   }
   ```
   Cleanest: read these from the identity stack via `terraform_remote_state` instead of
   hardcoding (see stowage's `infra/envs/dev/main.tf`).

2. **Frontend login** → switch from a custom email/password form to the **Hosted-UI
   redirect** (the shared pool has self-signup disabled — users are invited, see below):
   ```
   https://byresha-id-dev-a3575f48.auth.us-east-1.amazoncognito.com/login
     ?client_id=<app client id>
     &response_type=code
     &scope=openid+email+profile
     &redirect_uri=<app-url>/auth/callback
   ```
   On `/auth/callback?code=...`, exchange the code at `/oauth2/token` for id/access/refresh
   tokens; send the **id token** as `Authorization: Bearer` on API calls. Sign-out →
   redirect to the Hosted-UI `/logout`.

3. **Callback/logout URLs** → the app's served URL must be listed on its client in the
   identity stack's `apps` variable (`terraform/variables.tf`). Add the real URL (e.g. a
   CloudFront URL) if the app isn't on its `*.byresha.com` subdomain yet.

4. **Lambda group check** → enforce `cognito:groups` contains `app:<name>`, else 403.

## Add a social / enterprise IdP (Google, Microsoft)

The pool federates standard IdPs; users get "Sign in with …" buttons on the shared login.

- **Google:** already scaffolded in `terraform/cognito.tf`. Register an OAuth app in Google
  Cloud, then set `google_client_id` / `google_client_secret` and `terraform apply`.
- **Microsoft (Entra ID):** add an `aws_cognito_identity_provider` of type `OIDC` pointing
  at your tenant (`https://login.microsoftonline.com/<tenant>/v2.0`), with client id/secret
  from an Azure app registration, scopes `openid email profile`. Add `"Microsoft"` to each
  client's `supported_identity_providers`. Restrict to a specific email domain by mapping
  and validating the `email` claim.

## Admin: invite users & grant access

```bash
POOL=us-east-1_b62r4VVXl
# Invite a user (they get a temp password by email)
aws cognito-idp admin-create-user --user-pool-id $POOL --username you@email.com \
  --temporary-password 'TempPass123!' \
  --user-attributes Name=email,Value=you@email.com Name=email_verified,Value=true
# Grant access to specific apps
aws cognito-idp admin-add-user-to-group --user-pool-id $POOL --username you@email.com --group-name app:stowage
# Revoke
aws cognito-idp admin-remove-user-from-group --user-pool-id $POOL --username you@email.com --group-name app:stowage
```
(`identity/scripts/user.sh` wraps these.)

## ⚠️ Migrating a LIVE app (pulse, nudge)

pulse and nudge currently run on their **own** Cognito pools. Switching an app to the
shared pool changes every user's Cognito `sub`, which several apps use as the DynamoDB
partition key — so **existing users must re-register** (or you run a user-migration).
Plan this per app; do not cut over a live app's auth blindly. stowage is safe to switch
now only because its database is empty.
