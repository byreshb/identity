variable "aws_region" {
  description = "AWS region for resources (Cognito custom domain cert MUST be us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Name of this shared identity stack"
  type        = string
  default     = "byresha-id"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "route53_zone_name" {
  description = "Existing Route 53 hosted zone (no trailing dot)"
  type        = string
  default     = "byresha.com"
}

variable "auth_domain" {
  description = "Custom domain for the shared Hosted UI / login screen"
  type        = string
  default     = "auth.byresha.com"
}

variable "super_admin_email" {
  description = "Super admin email address"
  type        = string
  default     = "byreshb@gmail.com"
}

# One entry per app behind the shared login. Adding an app later = add one entry.
# `group` is the Cognito group that gates access to that app (authorization).
variable "apps" {
  description = "Apps that use the shared pool, with their OAuth callback/logout URLs"
  type = map(object({
    callback_urls = list(string)
    logout_urls   = list(string)
  }))
  default = {
    pulse = {
      callback_urls = ["https://pulse.byresha.com/auth/callback", "http://localhost:5173/auth/callback"]
      logout_urls   = ["https://pulse.byresha.com/", "http://localhost:5173/"]
    }
    nudge = {
      callback_urls = ["https://nudge.byresha.com/auth/callback", "http://localhost:5174/auth/callback"]
      logout_urls   = ["https://nudge.byresha.com/", "http://localhost:5174/"]
    }
    stowage = {
      callback_urls = ["https://stowage.byresha.com/auth/callback", "http://localhost:5175/auth/callback"]
      logout_urls   = ["https://stowage.byresha.com/", "http://localhost:5175/"]
    }
  }
}

# Optional "Sign in with Google" — leave blank to disable. When set, a Google
# identity provider is created and offered on every app's login screen.
variable "google_client_id" {
  description = "Google OAuth client id (optional; blank disables Google login)"
  type        = string
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth client secret (optional)"
  type        = string
  default     = ""
  sensitive   = true
}
