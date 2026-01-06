variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "zitadel_domain" {
  description = "Zitadel domain (e.g., iam.staging.burgdev.ch)"
  type        = string
}

variable "zitadel_jwt_profile" {
  description = "JWT profile JSON for Zitadel service account authentication"
  type        = string
  sensitive   = true
}

variable "podinfo_domain" {
  description = "Podinfo application domain (e.g., podinfo.staging.burgdev.ch)"
  type        = string
}
