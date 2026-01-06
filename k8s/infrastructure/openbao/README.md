# OpenBao Scripts

This directory contains scripts for managing OpenBao.

## Scripts

### `init-openbao`

Initializes OpenBao when setting up a new cluster. This should be run ONCE.

**What it does:**
- Initializes OpenBao if not already initialized
- Enables Kubernetes authentication
- Creates the admin role for configuration management

**Usage:**
```bash
./init-openbao -c <cluster-name> [-n namespace]

# Examples:
./init-openbao -c local
./init-openbao -c burginfra-system -n burginfra-staging
```

### `bao`

Wrapper script to execute OpenBao commands using Kubernetes authentication.

**What it does:**
- Authenticates to OpenBao using a Kubernetes service account token
- Executes `bao` commands inside the OpenBao pod
- No need for root token - uses the `openbao-secrets-manager` role

**Usage:**
```bash
./bao -c <cluster-name> [-n namespace] -- <bao-command> [args...]

# Examples:

# List secrets in infrastructure path
./bao -c local -- kv list kv/infrastructure

# Get a specific secret
./bao -c local -- kv get kv/infrastructure/zitadel/burginfra-staging

# Create/update a secret
./bao -c local -- kv put kv/infrastructure/example/staging \
  key1=value1 \
  key2=value2

# Delete a secret
./bao -c local -- kv delete kv/infrastructure/example/staging

# Use production namespace
./bao -c production -n burginfra-production -- kv list kv/infrastructure
```

**Requirements:**
- The `openbao-secrets-manager` service account must exist in the OpenBao namespace
- The `openbao-secrets-manager` policy and role must be configured in OpenBao

**Permissions:**
The `openbao-secrets-manager` role has access to:
- `kv/infrastructure/*` - Full access (create, read, update, delete)
- `kv/apps/*` - Full access (create, read, update, delete)

### `apply-config`

Applies OpenBao policies and roles from the `base/policies/` directory.

**What it does:**
- Creates/updates policies from `.hcl` files
- Creates Kubernetes auth roles based on policy metadata
- Removes obsolete policies and roles

**Usage:**
```bash
./apply-config -c <cluster-name> [-n namespace]
```

### `set-unseal-keys`

Stores unseal keys as Kubernetes secrets for automated unsealing.

**Usage:**
```bash
./set-unseal-keys -c <cluster-name> -k <key1> [-k <key2>...] [-n namespace]
```

## Service Accounts

### `openbao-config-manager`

Used by the `apply-config` script to manage policies and roles.

**Policy:** `openbao-admin`

**Permissions:**
- Manage policies
- Manage auth methods
- Manage Kubernetes auth roles

### `openbao-secrets-manager`

Used by init scripts (like `init-zitadel`) to create and manage secrets.

**Policy:** `openbao-secrets-manager`

**Permissions:**
- Full access to `kv/infrastructure/*`
- Full access to `kv/apps/*`

## Policies

All policies are stored in `base/policies/` and managed through GitOps.

### Policy Metadata

Policies include metadata in comments to configure access:

```hcl
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: burginfra-staging,burginfra-production
# KUBERNETES_SERVICE_ACCOUNT: my-service-account
```

This metadata is used by `apply-config` to automatically create Kubernetes auth roles.

## Creating New Init Scripts

When creating new init scripts for other infrastructure components, follow this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR=$(realpath "$SCRIPT_DIR/../../../")
. "$ROOT_DIR/scripts/_base.sh"

# Use the OpenBao wrapper
BAO_WRAPPER="$SCRIPT_DIR/../openbao/bao"

# Generate secrets
MY_SECRET=$(openssl rand -base64 32)

# Store in OpenBao
"$BAO_WRAPPER" -c "$CLUSTER" -n "$OPENBAO_NAMESPACE" -- kv put "kv/infrastructure/myapp/$NAMESPACE" \
  "MY_SECRET=$MY_SECRET"
```

This approach:
- Uses Kubernetes authentication (no root token needed)
- Follows the principle of least privilege
- Can be run by anyone with access to the cluster
- Doesn't require manual token management
