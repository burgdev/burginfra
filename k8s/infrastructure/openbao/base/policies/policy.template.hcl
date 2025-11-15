# OpenBao Policy Template
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_NAMESPACES: production
# OPENBAO_ROLE: optional-different-name
# OPENBAO_SERVICE_ACCOUNTS: optional-different-sa

path "kv/data/apps/*/staging" {
  capabilities = ["read", "list"]
}

path "kv/metadata/apps/*/staging" {
  capabilities = ["read", "list"]
}

path "kv/data/apps/*/production" {
  capabilities = ["read", "list"]
}

path "kv/metadata/apps/*/production" {
  capabilities = ["read", "list"]
}
