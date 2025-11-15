# Infrastructure Secrets - System Environment Only
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: burginfra-system

path "kv/data/infrastructure/*/system" {
  capabilities = ["read", "list"]
}

path "kv/metadata/infrastructure/*/system" {
  capabilities = ["read", "list"]
}
