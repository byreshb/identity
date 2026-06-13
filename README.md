# byresha identity — shared login (Okta-lite) for all apps

One **shared Amazon Cognito User Pool** that every app signs into. Log in once at
`auth.byresha.com`, and all your apps (pulse, nudge, stowage, …) recognise the session —
that's the SSO. Per-app access is controlled with **groups**, so a user only reaches the
apps you've granted them.

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
| `aws_cognito_user_pool_domain.main` | Hosted UI at `auth.byresha.com` (where the SSO session lives) |
| `aws_cognito_user_pool_client.app["<app>"]` | one OAuth client per app (code flow, no secret) |
| `aws_cognito_user_group.app["<app>"]` | one access group per app (`app:pulse`, `app:nudge`, `app:stowage`) |
| `aws_cognito_identity_provider.google` | optional "Sign in with Google" (off until you set `google_client_id`) |
| ACM cert + Route 53 records | TLS + DNS for the custom auth domain |

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
2. An S3 bucket for state: `identity-terraform-state-byreshb` (create once):
   ```bash
   aws s3 mb s3://identity-terraform-state-byreshb --region us-east-1
   ```
3. The `byresha.com` Route 53 zone must have an apex A record (it does — you serve
   pulse.byresha.com). Cognito requires it before attaching the custom auth domain.

## Deploy

```bash
cd terraform
terraform init
terraform plan      # review — NOTHING in your apps changes; this only adds the shared pool
terraform apply
```

> Terraform isn't installed in this sandbox — run `terraform validate` / `fmt` on a machine
> that has it before the first apply.

## Day-to-day admin

```bash
# Invite a user (see `terraform output create_user_command` for the filled-in version)
aws cognito-idp admin-create-user --user-pool-id <pool> --username you@email.com \
  --temporary-password 'TempPass123!' \
  --user-attributes Name=email,Value=you@email.com Name=email_verified,Value=true

# Grant that user access to specific apps
aws cognito-idp admin-add-user-to-group --user-pool-id <pool> --username you@email.com --group-name app:pulse
aws cognito-idp admin-add-user-to-group --user-pool-id <pool> --username you@email.com --group-name app:nudge

# Revoke access to an app
aws cognito-idp admin-remove-user-from-group --user-pool-id <pool> --username you@email.com --group-name app:pulse
```

## Wiring an app to this pool (done per app, after this stack is applied)

1. Point the app's API Gateway JWT authorizer at `issuer_url` + its own `app_client_ids[<app>]`.
2. Switch the frontend login from the custom form to the **Hosted UI redirect**
   (`https://auth.byresha.com/login?client_id=...&response_type=code&scope=openid+email+profile&redirect_uri=...`).
3. In the app's Lambda, check the JWT's `cognito:groups` contains `app:<name>`; else 403.

## Outputs

`terraform output` →
`user_pool_id`, `user_pool_arn`, `issuer_url`, `hosted_ui_domain`, `app_client_ids`,
`app_groups`, plus copy-paste `create_user_command` / `grant_app_access_command`.
