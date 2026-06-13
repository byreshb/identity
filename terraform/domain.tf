# ─────────────────────────────────────────────────────────────────────────────
# Custom domain for the Hosted UI (auth.byresha.com).
# PREREQUISITE: the parent zone (byresha.com) must already have an A record at
# its apex — Cognito requires this before it will attach a custom auth domain.
# (You already serve pulse.byresha.com, so the zone exists.)
# ─────────────────────────────────────────────────────────────────────────────
data "aws_route53_zone" "main" {
  name = "${var.route53_zone_name}."
}

# ACM cert for the auth subdomain. MUST be in us-east-1 for a Cognito custom domain.
resource "aws_acm_certificate" "auth" {
  domain_name       = var.auth_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.auth.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "auth" {
  certificate_arn         = aws_acm_certificate.auth.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain          = var.auth_domain
  user_pool_id    = aws_cognito_user_pool.main.id
  certificate_arn = aws_acm_certificate_validation.auth.certificate_arn
}

# Point auth.byresha.com at the CloudFront distribution Cognito provisions.
# Z2FDTNDATAQYW2 is the fixed CloudFront hosted-zone id (constant for all CF aliases).
resource "aws_route53_record" "auth_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.auth_domain
  type    = "A"

  alias {
    name                   = aws_cognito_user_pool_domain.main.cloudfront_distribution
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}
