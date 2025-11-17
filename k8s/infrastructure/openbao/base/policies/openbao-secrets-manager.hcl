# OpenBao Secrets Manager Policy
# MANAGED BY GITOPS, DO NOT CHANGE MANUALLY!
# Used by init scripts to create and manage secrets in OpenBao
#
# This policy allows:
# - Creating, reading, updating, and deleting secrets in kv/infrastructure/*
# - Creating, reading, updating, and deleting secrets in kv/apps/*
# - Listing secrets in both paths
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: burginfra-staging,burginfra-system,production,staging
# KUBERNETES_SERVICE_ACCOUNT: openbao-secrets-manager

# Allow full access to infrastructure secrets
path "kv/data/infrastructure/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/metadata/infrastructure/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow listing infrastructure secrets
path "kv/metadata/infrastructure" {
  capabilities = ["list"]
}

# Allow full access to apps secrets
path "kv/data/apps/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/metadata/apps/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow listing apps secrets
path "kv/metadata/apps" {
  capabilities = ["list"]
}
