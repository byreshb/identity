output "user_pool_id" {
  description = "Shared Cognito User Pool id — every app references this"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Shared Cognito User Pool ARN (for API Gateway authorizers)"
  value       = aws_cognito_user_pool.main.arn
}

output "issuer_url" {
  description = "OIDC issuer URL — use as the JWT authorizer issuer in each app"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "hosted_ui_domain" {
  description = "Shared login domain (the SSO session lives here)"
  value       = "https://${var.auth_domain}"
}

output "app_client_ids" {
  description = "Per-app OAuth client ids — give each app its own"
  value       = { for k, c in aws_cognito_user_pool_client.app : k => c.id }
}

output "app_groups" {
  description = "Per-app access groups — add a user to one to grant access"
  value       = { for k, g in aws_cognito_user_group.app : k => g.name }
}

output "create_user_command" {
  description = "Invite a new user to the shared pool"
  value       = <<-EOT
    aws cognito-idp admin-create-user \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username YOUR_EMAIL \
      --temporary-password 'TempPass123!' \
      --user-attributes Name=email,Value=YOUR_EMAIL Name=email_verified,Value=true
  EOT
}

output "grant_app_access_command" {
  description = "Grant an existing user access to a specific app"
  value       = <<-EOT
    aws cognito-idp admin-add-user-to-group \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username YOUR_EMAIL \
      --group-name app:pulse   # or app:nudge, app:stowage
  EOT
}
