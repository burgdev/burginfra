output "client_id" {
  value       = zitadel_application_oidc.podinfo.client_id
  description = "OIDC client ID for podinfo"
}

output "client_secret" {
  value       = zitadel_application_oidc.podinfo.client_secret
  description = "OIDC client secret for podinfo"
  sensitive   = true
}

output "project_id" {
  value       = zitadel_project.podinfo.id
  description = "Zitadel project ID"
}

output "issuer_url" {
  value       = "https://${var.zitadel_domain}"
  description = "OIDC issuer URL"
}

output "authorization_endpoint" {
  value       = "https://${var.zitadel_domain}/oauth/v2/authorize"
  description = "OIDC authorization endpoint"
}

output "token_endpoint" {
  value       = "https://${var.zitadel_domain}/oauth/v2/token"
  description = "OIDC token endpoint"
}

output "userinfo_endpoint" {
  value       = "https://${var.zitadel_domain}/oidc/v1/userinfo"
  description = "OIDC userinfo endpoint"
}

output "jwks_uri" {
  value       = "https://${var.zitadel_domain}/oauth/v2/keys"
  description = "OIDC JWKS URI"
}
