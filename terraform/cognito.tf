# ─────────────────────────────────────────────────────────────────────────────
# Shared user pool — the single identity provider for ALL apps (Okta-lite).
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-users"

  # Admin-only user creation (no open self-signup). You invite users.
  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Your byresha account"
      email_message = "Your username is {username}. Temporary password: {####}. Sign in and change it."
      sms_message   = "byresha username {username}. Temp password: {####}"
    }
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"

  tags = {
    Name        = "${var.app_name}-users"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-app access control (authorization).
# One group per app. A user can sign in (authentication) with one account, but
# only reaches an app if they are in that app's group. Apps enforce this by
# checking the `cognito:groups` claim in the JWT. Grant access with:
#   aws cognito-idp admin-add-user-to-group \
#     --user-pool-id <pool> --username <email> --group-name app:pulse
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cognito_user_group" "app" {
  for_each = var.apps

  name         = "app:${each.key}"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Access to the ${each.key} app"
}

# ─────────────────────────────────────────────────────────────────────────────
# One OAuth app client per app (no secret — these are public SPAs).
# `code` flow + Hosted UI is what gives cross-app SSO: signing into one app
# creates a session at the shared domain, so the others sign in silently.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool_client" "app" {
  for_each = var.apps

  name         = "${local.name_prefix}-${each.key}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = each.value.callback_urls
  logout_urls                          = each.value.logout_urls

  supported_identity_providers = compact([
    "COGNITO",
    var.google_client_id != "" ? "Google" : "",
  ])

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  access_token_validity  = 1  # hours
  id_token_validity      = 1  # hours
  refresh_token_validity = 30 # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"

  depends_on = [aws_cognito_identity_provider.google]
}

# ─────────────────────────────────────────────────────────────────────────────
# Optional Google federation — only created when google_client_id is set.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cognito_identity_provider" "google" {
  count = var.google_client_id != "" ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}
