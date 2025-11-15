# Infrastructure Secrets - All Environments
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: *

path "kv/data/infrastructure/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/infrastructure/*" {
  capabilities = ["read", "list"]
}
