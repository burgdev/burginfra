# Application Secrets - Staging Environment Only
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_NAMESPACES: production

path "kv/data/apps/*/production" {
  capabilities = ["read", "list"]
}

path "kv/metadata/apps/*/production" {
  capabilities = ["read", "list"]
}
