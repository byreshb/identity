# ─────────────────────────────────────────────────────────────────────────────
# Hosted UI domain.
#
# We use Cognito's FREE default domain (a prefix under amazoncognito.com) instead
# of a custom domain (auth.byresha.com). Reason: a Cognito *custom* domain
# requires an A record on the PARENT apex (byresha.com), and we intentionally do
# NOT modify the apex. SSO works identically on the default domain — only the
# login page URL differs.
#
# To move to auth.byresha.com later: add an apex A record for byresha.com, then
# restore an aws_acm_certificate (us-east-1) + DNS validation + custom-domain
# config here and point an auth.byresha.com alias at the distribution.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${local.name_prefix}-${random_id.suffix.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}
