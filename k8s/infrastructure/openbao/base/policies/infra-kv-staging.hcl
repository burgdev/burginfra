# Infrastructure Secrets - Staging Environment Only
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: burginfra-staging

path "kv/data/infrastructure/*/staging" {
  capabilities = ["read", "list"]
}

path "kv/metadata/infrastructure/*/staging" {
  capabilities = ["read", "list"]
}
