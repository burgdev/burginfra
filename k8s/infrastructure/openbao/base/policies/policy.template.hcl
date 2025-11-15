# OpenBao Policy Template
#
# Copy this file to create a new policy, then customize the paths and metadata.
# See README.md for detailed documentation.
#
# !! make sure to add it to 'kustomization.yaml' under configMapGenerator !!
#
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: staging,production
# KUBERNETES_SERVICE_ACCOUNT: optional-custom-service-account

# Example: Read access to application secrets
path "kv/data/apps/myapp/+/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/apps/myapp/+/*" {
  capabilities = ["read", "list"]
}

# Example: Write access to specific paths
path "kv/data/apps/myapp/+/config" {
  capabilities = ["create", "update", "read", "delete"]
}

path "kv/metadata/apps/myapp/+/config" {
  capabilities = ["create", "update", "read", "delete", "list"]
}

# Common capability patterns:
#
# Read-only:
#   capabilities = ["read", "list"]
#
# Read-write:
#   capabilities = ["create", "read", "update", "delete", "list"]
#
# Admin (with sudo):
#   capabilities = ["create", "read", "update", "delete", "list", "sudo"]
