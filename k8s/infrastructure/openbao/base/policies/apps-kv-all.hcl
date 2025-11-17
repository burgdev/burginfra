# Application Secrets - All Environments
# MANAGED BY GITOPS, DO NOT CHANGE MANUALLY!
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: staging,production

path "kv/data/apps/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/apps/*" {
  capabilities = ["read", "list"]
}

