# OpenBao Admin Policy
# Used by configuration jobs to manage OpenBao
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: *
# KUBERNETES_SERVICE_ACCOUNT: openbao-config-manager

# Allow listing all policies
path "sys/policies/acl" {
  capabilities = ["list"]
}

# Allow managing individual policies
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow managing auth methods
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# Allow listing all kubernetes auth roles
path "auth/kubernetes/role" {
  capabilities = ["list"]
}

# Allow managing individual kubernetes auth roles
path "auth/kubernetes/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow reading/updating kubernetes auth config
path "auth/kubernetes/config" {
  capabilities = ["read", "update"]
}

# Allow reading auth methods
path "sys/auth" {
  capabilities = ["read"]
}


