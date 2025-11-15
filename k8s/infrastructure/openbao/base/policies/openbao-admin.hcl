# OpenBao Admin Policy
# Used by configuration jobs to manage OpenBao
#
# !! make sure it is added to 'kustomization.yaml' !!
#
# OPENBAO_NAMESPACES: *
# OPENBAO_ROLE: openbao-admin
# OPENBAO_SERVICE_ACCOUNTS: openbao-config-manager

# Allow managing policies
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow managing auth methods
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# Allow managing kubernetes auth roles
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
