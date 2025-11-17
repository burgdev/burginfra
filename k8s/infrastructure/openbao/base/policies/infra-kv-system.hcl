# Infrastructure Secrets - System Environment Only
# MANAGED BY GITOPS, DO NOT CHANGE MANUALLY!
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: burginfra-system

path "kv/data/infrastructure/+/burginfra-system" {
  capabilities = ["read", "list"]
}

path "kv/metadata/infrastructure/+/burginfra-system" {
  capabilities = ["read", "list"]
}
