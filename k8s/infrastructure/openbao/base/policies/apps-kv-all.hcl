# Application Secrets - All Environments
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: staging,production

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

