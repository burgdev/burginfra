# Zitadel Configuration Template

This document describes the required secrets that need to be created in OpenBao before deploying Zitadel.

## Automated Setup

Use the `init-zitadel` script to automatically generate and store all required secrets:

```bash
cd k8s/infrastructure/zitadel
./init-zitadel -c <cluster-name> [-n namespace] [-e environment]

# Examples:
./init-zitadel -c local
./init-zitadel -c burginfra-system -n burginfra-production -e production
```

The script will:
1. Generate secure random secrets for Zitadel and PostgreSQL
2. Store them in OpenBao at the correct path
3. Verify the secrets were created successfully
4. The same secrets are used for both Zitadel configuration and CloudNativePG cluster

## Manual Setup

If you prefer to create secrets manually, follow the instructions below.

## OpenBao Secret Path

**Path**: `kv/infrastructure/zitadel/<namespace>`

For staging: `kv/infrastructure/zitadel/burginfra-staging`
For production: `kv/infrastructure/zitadel/burginfra-production`

## Required Secret Keys

The following keys must be created at the above path in OpenBao:

### 1. ZITADEL_MASTERKEY

The masterkey is used for symmetric encryption of sensitive data in the database.

**Requirements**:
- Minimum length: 32 characters
- Must be a random, cryptographically secure string
- **IMPORTANT**: Once set, do not change this key as it will make existing encrypted data unreadable

**How to generate**:
```bash
openssl rand -base64 32
```

### 2. ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD

Password for the PostgreSQL admin user (`postgres`). This user has full administrative privileges on the database.

**Used by**: CloudNativePG Cluster superuser secret

**How to generate**:
```bash
openssl rand -base64 32
```

### 3. ZITADEL_DATABASE_POSTGRES_USER_PASSWORD

Password for the PostgreSQL application user (`zitadel`). This user is used by Zitadel for normal database operations and owns the Zitadel database.

**Used by**: 
- CloudNativePG Cluster bootstrap (application user)
- Zitadel application configuration

**How to generate**:
```bash
openssl rand -base64 32
```

## Creating the Secrets in OpenBao

### Using OpenBao CLI

```bash
# Set OpenBao address
export BAO_ADDR="http://openbao.burginfra-staging.svc.cluster.local:8200"

# Login to OpenBao
bao login

# Generate secrets
MASTERKEY=$(openssl rand -base64 32)
ADMIN_PASSWORD=$(openssl rand -base64 32)
USER_PASSWORD=$(openssl rand -base64 32)

# Create the secret in OpenBao
bao kv put kv/infrastructure/zitadel/burginfra-staging \
  ZITADEL_MASTERKEY="$MASTERKEY" \
  ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  ZITADEL_DATABASE_POSTGRES_USER_PASSWORD="$USER_PASSWORD"

# Verify the secrets were created
bao kv get kv/infrastructure/zitadel/burginfra-staging
```

## Verification

After creating the secrets, verify that the VaultStaticSecret resource can read them:

```bash
# Check if the secret is created in Kubernetes
kubectl get vaultstaticsecret -n burginfra-staging zitadel-config-secret

# Check if the Kubernetes secret was created
kubectl get secret -n burginfra-staging zitadel-config-secret

# Verify the secret contains the correct keys (without showing values)
kubectl get secret -n burginfra-staging zitadel-config-secret -o jsonpath='{.data}' | jq 'keys'
```

Expected output should show:
```json
[
  "ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD",
  "ZITADEL_DATABASE_POSTGRES_USER_PASSWORD",
  "ZITADEL_MASTERKEY"
]
```

## Security Notes

- **Never commit these secrets to Git**
- Store the masterkey securely - losing it means losing access to encrypted data
- Use different passwords for admin and user accounts
- Consider rotating passwords periodically
- For production, ensure OpenBao itself is properly secured and backed up

## Troubleshooting

### VaultStaticSecret not syncing

Check the vault-secrets-operator logs:
```bash
kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator
```

### Secret not found in OpenBao

Verify the path is correct:
```bash
bao kv list kv/infrastructure/zitadel
bao kv get kv/infrastructure/zitadel/burginfra-staging
```

### Authentication issues

Check the VaultAuth configuration:
```bash
kubectl get vaultauth -n burginfra-staging infra-kv-burginfra-staging -o yaml
```
