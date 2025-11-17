---
title: Zitadel
---
# [Zitadel](/apps/zitadel) <Badge type="info" text="zitadel" />

This document describes the Kubernetes-specific setup and deployment of Zitadel in the burginfra cluster.

[[toc]]

Identity and access management (_iam_) platform.

## Architecture

Zitadel is deployed in the `burginfra-system` namespace using Flux CD with the following components:

- **Zitadel Application**: Identity and access management service
- **PostgreSQL Database**: Bundled database for Zitadel data persistence
- **Ingress**: Traefik-based ingress with TLS termination
- **Secrets**: Managed via OpenBao Vault using VaultStaticSecret CRD

## Deployment

### Prerequisites

1. **Namespace**: `burginfra-system` namespace must exist
2. **Storage Class**: `fast-local-data-v1` storage class must be available
3. **OpenBao**: Must be configured with:
   - VaultAuth: `infra-kv-staging` in the staging namespace
   - Policy: Access to `kv/apps/zitadel/staging` path
4. **Infrastructure**:
   - Traefik ingress controller
   - cert-manager with letsencrypt-prod issuer
   - vault-secrets-operator

### Secret Configuration

Before deploying, create the required secrets in OpenBao. See `k8s/apps/zitadel/config.template.md` for detailed instructions.

**Quick setup**:

```bash
# Generate secrets
MASTERKEY=$(openssl rand -base64 32)
ADMIN_PASSWORD=$(openssl rand -base64 24)
USER_PASSWORD=$(openssl rand -base64 24)

# Store in OpenBao
bao kv put kv/apps/zitadel/staging \
  ZITADEL_MASTERKEY="$MASTERKEY" \
  ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  ZITADEL_DATABASE_POSTGRES_USER_PASSWORD="$USER_PASSWORD"
```

### Deploy via Flux

The deployment is automatically synced by Flux via:

```
k8s/apps/_deploy/flux/staging/flux_kustom_apps.yaml
  → k8s/apps/_deploy/staging/kustomization.yaml
    → k8s/apps/zitadel/overlays/staging/kustomization.yaml
      → k8s/apps/zitadel/base/
```

To trigger immediate reconciliation:

```bash
flux reconcile kustomization apps-sync-all-staging -n flux-system
```

### Manual Deployment (for testing)

```bash
# Build and view manifests
kubectl kustomize k8s/apps/zitadel/overlays/staging

# Apply
kubectl apply -k k8s/apps/zitadel/overlays/staging
```

## Configuration

### Domain and Ingress

- **URL**: `https://iam.staging.${BURGDEV_HOST}` (e.g., `https://iam.staging.burgdev.ch`)
- **Ingress Class**: traefik
- **TLS**: Automatic via cert-manager with Let's Encrypt
- **Certificate Secret**: `zitadel-tls`

### Database

- **Type**: PostgreSQL (bundled with Zitadel Helm chart)
- **Service Name**: `zitadel-postgresql`
- **Port**: 5432
- **Database**: `zitadel`
- **Users**:
  - Admin: `postgres`
  - Application: `zitadel`
- **Persistence**:
  - Storage Class: `fast-local-data-v1`
  - Size: 10Gi
  - PVC: Automatically created by StatefulSet

### Secrets Management

Secrets are managed via OpenBao and synced to Kubernetes using the vault-secrets-operator:

1. **Source**: OpenBao KV path `kv/apps/zitadel/staging`
2. **VaultStaticSecret**: `zitadel-config-secret` (in staging namespace)
3. **Kubernetes Secret**: `zitadel-config-secret` (created by operator)
4. **Consumed by**:
   - Zitadel deployment (via `envVarsSecret`)
   - PostgreSQL deployment (via `existingSecret`)

### Helm Chart Configuration

- **Chart**: `zitadel` from `oci://ghcr.io/zitadel/charts`
- **Version**: `9.*` (Zitadel v4)
- **Repository**: Defined in HelmRepository CRD
- **Values**: Stored in ConfigMap `zitadel-values`

Key configuration options:

```yaml
zitadel:
  masterkeySecretName: zitadel-config-secret
  envVarsSecret: zitadel-config-secret
  configmapConfig:
    ExternalDomain: iam.staging.${BURGDEV_HOST}
    ExternalPort: 443
    ExternalSecure: true
    TLS:
      Enabled: false  # TLS termination at Traefik
```

## Operations

### Monitoring Status

```bash
# Check HelmRelease status
kubectl get helmrelease -n staging zitadel

# Check pods
kubectl get pods -n staging -l app.kubernetes.io/name=zitadel

# Check PostgreSQL
kubectl get pods -n staging -l app.kubernetes.io/name=postgresql

# Check secrets sync
kubectl get vaultstaticsecret -n staging zitadel-config-secret
kubectl get secret -n staging zitadel-config-secret
```

### Logs

```bash
# Zitadel application logs
kubectl logs -n staging -l app.kubernetes.io/name=zitadel --tail=100 -f

# PostgreSQL logs
kubectl logs -n staging -l app.kubernetes.io/name=postgresql --tail=100 -f

# Helm controller logs (for deployment issues)
kubectl logs -n flux-system -l app=helm-controller --tail=100 -f
```

### Database Access

```bash
# Port-forward to PostgreSQL
kubectl port-forward -n staging svc/zitadel-postgresql 5432:5432

# Connect using psql (password from OpenBao secret)
psql -h localhost -U zitadel -d zitadel
```

### Backup and Restore

PostgreSQL data is stored in a PersistentVolume using `fast-local-data-v1` storage class.

**Backup**:

```bash
# Get the PostgreSQL pod name
POD=$(kubectl get pod -n staging -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')

# Create a backup
kubectl exec -n staging $POD -- pg_dump -U postgres zitadel > zitadel-backup-$(date +%Y%m%d).sql
```

**Restore**:

```bash
# Restore from backup
kubectl exec -i -n staging $POD -- psql -U postgres zitadel < zitadel-backup-YYYYMMDD.sql
```

### Restart Deployment

```bash
# Restart Zitadel pods
kubectl rollout restart deployment -n staging -l app.kubernetes.io/name=zitadel

# Restart PostgreSQL StatefulSet
kubectl rollout restart statefulset -n staging -l app.kubernetes.io/name=postgresql
```

### Update Configuration

1. Update values in `k8s/apps/zitadel/base/helmrelease.yaml`
2. Commit and push changes
3. Flux will automatically reconcile (or trigger manually)

```bash
flux reconcile source git burgdev-burginfra -n flux-system
flux reconcile kustomization apps-sync-all-staging -n flux-system
```

### Update Secrets

```bash
# Update secrets in OpenBao
bao kv put kv/apps/zitadel/staging \
  ZITADEL_MASTERKEY="<keep-existing-value>" \
  ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD="<new-password>" \
  ZITADEL_DATABASE_POSTGRES_USER_PASSWORD="<new-password>"

# Force secret refresh
kubectl delete secret -n staging zitadel-config-secret
# VaultStaticSecret will recreate it automatically

# Restart pods to pick up new secrets
kubectl rollout restart deployment -n staging -l app.kubernetes.io/name=zitadel
```

## Troubleshooting

### Pods Not Starting

Check HelmRelease status:

```bash
kubectl describe helmrelease -n staging zitadel
```

Common issues:

- **Image pull errors**: Check OCI repository access
- **Secret not found**: Verify VaultStaticSecret synced correctly
- **PVC pending**: Check storage class availability

### Secrets Not Syncing

```bash
# Check VaultStaticSecret
kubectl describe vaultstaticsecret -n staging zitadel-config-secret

# Check vault-secrets-operator logs
kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator

# Verify OpenBao secret exists
bao kv get kv/apps/zitadel/staging

# Check VaultAuth configuration
kubectl describe vaultauth -n staging apps-kv-staging
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
kubectl get pods -n staging -l app.kubernetes.io/name=postgresql

# Check PostgreSQL logs
kubectl logs -n staging -l app.kubernetes.io/name=postgresql

# Verify database credentials
kubectl exec -n staging -l app.kubernetes.io/name=postgresql -- \
  psql -U postgres -c "\du"
```

### Ingress Not Working

```bash
# Check ingress status
kubectl describe ingress -n staging -l app.kubernetes.io/name=zitadel

# Check certificate
kubectl get certificate -n staging zitadel-tls

# Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

### Masterkey Issues

**WARNING**: Never change the masterkey after initial deployment. Encrypted data cannot be recovered.

If you must rotate the masterkey (rare):

1. Backup the entire database
2. Decrypt all data with old key
3. Update masterkey in OpenBao
4. Re-encrypt data with new key
5. Restart application

## Upgrade

To upgrade Zitadel version:

1. Update version in `helmrelease.yaml`:

   ```yaml
   version: "9.x.x"  # Specify exact version
   ```

2. Review [Zitadel release notes](https://github.com/zitadel/zitadel/releases)

3. Backup database before upgrading

4. Commit and let Flux apply the upgrade

5. Monitor the upgrade process:

   ```bash
   kubectl get helmrelease -n staging zitadel -w
   ```

## Security Considerations

- **Masterkey**: Never commit to Git, store only in OpenBao
- **Database passwords**: Use strong, randomly generated passwords
- **TLS**: Always use HTTPS in production (handled by Traefik/cert-manager)
- **Network policies**: Consider implementing NetworkPolicies to restrict traffic
- **Database access**: PostgreSQL is only accessible within the cluster
- **Secrets rotation**: Plan for periodic password rotation

## Resources

- **Zitadel Documentation**: <https://zitadel.com/docs>
- **Helm Chart**: <https://github.com/zitadel/zitadel-charts>
- **Artifact Hub**: <https://artifacthub.io/packages/helm/zitadel/zitadel>
