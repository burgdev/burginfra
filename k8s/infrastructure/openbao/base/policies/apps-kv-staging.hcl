# Application Secrets - Staging Environment Only
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_NAMESPACES: staging

path "kv/data/apps/*/staging" {
  capabilities = ["read", "list"]
}

path "kv/metadata/apps/*/staging" {
  capabilities = ["read", "list"]
}
