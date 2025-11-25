# Configs Secrets - All Environments
# MANAGED BY GITOPS, DO NOT CHANGE MANUALLY!
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: *

path "kv/data/configs/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/configs/*" {
  capabilities = ["read", "list"]
}
