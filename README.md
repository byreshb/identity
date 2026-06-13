# byresha identity — shared login (Okta-lite) for all apps

One **shared Amazon Cognito User Pool** that every app signs into. Log in once, and all
your apps (pulse, nudge, stowage, …) recognise the session — that's the SSO. Per-app
access is controlled with **groups**, so a user only reaches the apps you've granted them.

> **✅ Deployed to dev.** Live values + the full wiring/SSO-setup guide are in
> [`SSO.md`](./SSO.md). Pool `us-east-1_b62r4VVXl`.
>
> **Login domain:** this stack uses Cognito's **free default login domain**
> (`https://byresha-id-dev-a3575f48.auth.us-east-1.amazoncognito.com`), **not**
> `auth.byresha.com`. A custom domain would require an A record on the apex `byresha.com`,
> which we intentionally leave untouched. To adopt `auth.byresha.com` later, add an apex A
> record then restore the ACM cert + custom-domain config in `terraform/domain.tf` (steps
> are documented inline there). SSO works identically — only the login page URL differs.

## Why this design

- **Long-term:** one source of truth for users. Adding a new app = add one entry to the
  `apps` variable (one client + one group). Never a new auth system.
- **Cheap *and* scalable:** Cognito is fully managed and scales to millions of users with
  no servers to run. Free tier = **10,000 monthly active users, forever** (Lite/Essentials).
  A shared pool counts a person as **1 MAU across all apps** — separate pools would bill per
  app. Serverless, scales to zero. https://aws.amazon.com/cognito/pricing/

## What this stack creates

| Resource | Purpose |
|---|---|
| `aws_cognito_user_pool.main` | the shared identity provider |
| `aws_cognito_user_pool_domain.main` | Hosted UI on the free `*.auth.us-east-1.amazoncognito.com` domain (where the SSO session lives) |
| `aws_cognito_user_pool_client.app["<app>"]` | one OAuth client per app (code flow, no secret) |
| `aws_cognito_user_group.app["<app>"]` | one access group per app (`app:pulse`, `app:nudge`, `app:stowage`) |
| `aws_cognito_identity_provider.google` | optional "Sign in with Google" (off until you set `google_client_id`) |

## App ↔ domain map

| App | Domain | Group | Client output key |
|---|---|---|---|
| pulse-tracker | pulse.byresha.com | `app:pulse` | `pulse` |
| reminder-tracker (nudge) | nudge.byresha.com | `app:nudge` | `nudge` |
| stowage | stowage.byresha.com | `app:stowage` | `stowage` |

## Authentication vs. authorization (the two halves)

- **Authentication (who you are):** the shared Hosted UI. Sign in once → SSO everywhere.
- **Authorization (what you can open):** Cognito **groups**. Each app checks the
  `cognito:groups` claim in the JWT and rejects users not in its `app:<name>` group. This is
  your "way to grant the right access to each app" — handed out per user, per app.

## Prerequisites

1. AWS creds via the **default** profile (`~/.aws/credentials`), region `us-east-1`.
2. The S3 state bucket `identity-terraform-state-byreshb` (already created: versioned +
   AES256-encrypted + public-access-blocked).
3. ~~Apex A record on byresha.com~~ — **not needed** with the default login domain. Only
   required if you later switch to a custom `auth.byresha.com` domain.

## Deploy

**Cloud platform:** 100% AWS (`us-east-1`), provisioned by Terraform. State in S3
(`identity-terraform-state-byreshb`). The only service is Amazon Cognito — no servers.

```bash
cd terraform
terraform init
terraform plan      # review — NOTHING in your apps changes; this only adds the shared pool
terraform apply
```

## Day-to-day admin

Easiest is the **AWS Cognito Console** (web UI) or the **`scripts/user.sh`** helper, which
wraps the raw CLI calls:

```bash
scripts/user.sh invite  you@email.com           # create user + email a temp password
scripts/user.sh grant   you@email.com stowage    # allow access to an app (pulse|nudge|stowage)
scripts/user.sh revoke  you@email.com stowage    # remove access to an app
scripts/user.sh apps    you@email.com            # list which apps a user can access
scripts/user.sh list                             # list all users
scripts/user.sh disable you@email.com            # block sign-in (reversible)
scripts/user.sh delete  you@email.com            # remove the user entirely
```

Equivalent raw CLI (what the script runs):

```bash
aws cognito-idp admin-create-user --user-pool-id <pool> --username you@email.com \
  --user-attributes Name=email,Value=you@email.com Name=email_verified,Value=true
aws cognito-idp admin-add-user-to-group    --user-pool-id <pool> --username you@email.com --group-name app:stowage
aws cognito-idp admin-remove-user-from-group --user-pool-id <pool> --username you@email.com --group-name app:stowage
```

> Self-signup is currently **disabled** (invite-only). Automating onboarding (self-serve
> signup + a Post-Confirmation Lambda that auto-assigns the `app:<name>` group, then
> Stripe-gated paid access) is the planned upgrade — see the per-app rollout plan in
> `../stowage/docs/ROLLOUT.md`.

## Wiring an app to this pool (done per app, after this stack is applied)

1. Point the app's API Gateway JWT authorizer at `issuer_url` + its own `app_client_ids[<app>]`.
2. Switch the frontend login from the custom form to the **Hosted UI redirect** on the
   shared login domain
   (`https://byresha-id-dev-a3575f48.auth.us-east-1.amazoncognito.com/login?client_id=...&response_type=code&scope=openid+email+profile&redirect_uri=...`).
3. In the app's Lambda, check the JWT's `cognito:groups` contains `app:<name>`; else 403.
4. Register the app's `/auth/callback` URL on its client (in `terraform/variables.tf` `apps`),
   then re-apply this stack.

## App wiring status

| App | On shared SSO? | Notes |
|---|---|---|
| **stowage** | ✅ Done | Fully cut over + deployed. Authorizer, Hosted-UI flow, `app:stowage` group all live. |
| **pulse** | ❌ Not yet | Live on pulse.byresha.com with its own pool (Amplify-hosted). Cutover forces user re-registration (sub = partition key) + a brief login break on rebuild — do it carefully. |
| **nudge** | ❌ Not yet | Same as pulse. |

## Roadmap / future

- [ ] **Self-serve signup** — enable Cognito self-registration + a **Post-Confirmation
      Lambda** that auto-assigns `app:<name>` based on the signup client (removes manual
      onboarding). See `../stowage/docs/ROLLOUT.md`.
- [ ] **Federation** — Google (already scaffolded in `terraform`, set
      `google_client_id`/`secret`) + Microsoft (Entra/OIDC, add an
      `aws_cognito_identity_provider` block). Needs app registration in Google/Azure.
- [ ] **Migrate pulse + nudge** onto the shared pool (the re-registration-sensitive part).
- [ ] **Custom domain** `auth.byresha.com` — optional; needs an apex A record first.

## Outputs

`terraform output` →
`user_pool_id`, `user_pool_arn`, `issuer_url`, `hosted_ui_domain`, `app_client_ids`,
`app_groups`, plus copy-paste `create_user_command` / `grant_app_access_command`.
