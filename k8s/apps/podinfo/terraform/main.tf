terraform {
  required_version = ">= 1.0"
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.0"
    }
  }
}

provider "zitadel" {
  domain           = var.zitadel_domain
  insecure         = false
  jwt_profile_json = var.zitadel_jwt_profile
}

# Create a project for podinfo
resource "zitadel_project" "podinfo" {
  name                      = "Podinfo - ${var.environment}"
  project_role_assertion    = true
  project_role_check        = true
  has_project_check         = true
  private_labeling_setting  = "PRIVATE_LABELING_SETTING_UNSPECIFIED"
}

# Create project roles
resource "zitadel_project_role" "admin" {
  project_id   = zitadel_project.podinfo.id
  role_key     = "admin"
  display_name = "Administrator"
  group        = "admin"
}

resource "zitadel_project_role" "user" {
  project_id   = zitadel_project.podinfo.id
  role_key     = "user"
  display_name = "User"
  group        = "user"
}

# Create OIDC application
resource "zitadel_application_oidc" "podinfo" {
  org_id                      = zitadel_project.podinfo.org_id
  project_id                  = zitadel_project.podinfo.id
  name                        = "Podinfo Web - ${var.environment}"
  
  # Redirect URIs - using variable substitution from Flux
  redirect_uris               = [
    "https://${var.podinfo_domain}/oauth/callback",
    "https://${var.podinfo_domain}/auth/callback"
  ]
  post_logout_redirect_uris   = [
    "https://${var.podinfo_domain}/"
  ]
  
  # OIDC configuration
  response_types              = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                 = [
    "OIDC_GRANT_TYPE_AUTHORIZATION_CODE",
    "OIDC_GRANT_TYPE_REFRESH_TOKEN"
  ]
  app_type                    = "OIDC_APP_TYPE_WEB"
  auth_method_type            = "OIDC_AUTH_METHOD_TYPE_BASIC"
  version                     = "OIDC_VERSION_1_0"
  
  # Token settings
  clock_skew                  = "0s"
  dev_mode                    = false
  access_token_type           = "OIDC_TOKEN_TYPE_JWT"
  access_token_role_assertion = true
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true
  
  # Additional settings
  skip_native_app_success_page = false
}
