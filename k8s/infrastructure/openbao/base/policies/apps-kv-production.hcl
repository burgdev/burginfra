# Application Secrets - Production Environment Only
# MANAGED BY GITOPS, DO NOT CHANGE MANUALLY!
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: production

path "kv/data/apps/*/production" {
  capabilities = ["read", "list"]
}

path "kv/metadata/apps/*/production" {
  capabilities = ["read", "list"]
}
