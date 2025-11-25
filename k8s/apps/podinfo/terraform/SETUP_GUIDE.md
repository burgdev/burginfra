# Podinfo OIDC with Zitadel - Setup Guide

## Overview

This setup uses Flux's tofu-controller to manage Zitadel OIDC configuration for Podinfo via Terraform/OpenTofu in a GitOps way.

## Architecture

1. **Zitadel** automatically creates a machine user (service account) during first installation
2. **Tofu-controller** (Flux's Terraform controller) runs Terraform to create Zitadel projects and OIDC apps
3. **Flux** provides variables from the `cluster-settings` ConfigMap
4. **Kubernetes Secrets** store the OIDC credentials for use by applications

## What's Included

### Infrastructure Components

- **tofu-controller**: Installed in `flux-system` namespace to run Terraform/OpenTofu
- **Zitadel machine user**: Auto-created service account named `terraform-admin`

### Application Components

- **Terraform configuration**: Creates Zitadel project and OIDC application for Podinfo
- **Flux Terraform resource**: Manages the Terraform lifecycle
- **Secret output**: OIDC credentials written to `podinfo-oidc-credentials` Secret

## Setup Steps

### 1. Install Infrastructure (One-time)

The tofu-controller has been added to the infrastructure deployment. Commit and push:

```bash
# The following has been configured:
# k8s/infrastructure/tofu-controller/helm/system/helmrelease.yaml
# k8s/infrastructure/tofu-controller/flux/system/flux-kustom.yaml
# k8s/infrastructure/_deploy/system/kustomization.yaml (updated)
```

### 2. Configure Zitadel Machine User (One-time)

The Zitadel Helm values have been updated to create a machine user automatically.

After Zitadel is deployed (or redeployed), retrieve the credentials:

```bash
# Wait for Zitadel to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zitadel -n burginfra-staging --timeout=300s

# Get the machine user key
kubectl get secret terraform-admin -n burginfra-staging -o jsonpath='{.data.zitadel-key\.json}' | base64 -d > terraform-admin.json

# Create the secret for tofu-controller
kubectl create secret generic zitadel-terraform-credentials \
  --from-file=zitadel_jwt_profile=./terraform-admin.json \
  -n staging
```

Repeat for production:

```bash
kubectl get secret terraform-admin -n burginfra-production -o jsonpath='{.data.zitadel-key\.json}' | base64 -d > terraform-admin-production.json

kubectl create secret generic zitadel-terraform-credentials \
  --from-file=zitadel_jwt_profile=./terraform-admin-production.json \
  -n production
```

### 3. Deploy Podinfo with Terraform Resource

The `terraform.yaml` resource has been added to `k8s/apps/podinfo/base/`. Commit and push:

```bash
git add .
git commit -m "Add Terraform-based Zitadel OIDC configuration for Podinfo"
git push
```

Flux will automatically:
1. Apply the Terraform resource
2. Run Terraform to create the Zitadel project and OIDC app
3. Store credentials in the `podinfo-oidc-credentials` Secret

### 4. Monitor Progress

```bash
# Check Terraform resource status
kubectl get terraform podinfo-zitadel -n staging

# Watch Terraform apply
kubectl logs -f -n staging -l infra.contrib.fluxcd.io/terraform=podinfo-zitadel

# Verify the Secret was created
kubectl get secret podinfo-oidc-credentials -n staging
```

## Using OIDC Credentials in Podinfo

See `OIDC_INTEGRATION_EXAMPLE.md` for examples of how to reference the credentials in your deployment.

## Variable Substitution

The Terraform configuration uses variables from:

1. **cluster-settings ConfigMap**:
   - `BURGDEV_HOST` → Used to construct domains

2. **Flux inline substitution**:
   - `ENVIRONMENT` → staging/production
   - `zitadel_domain` → Computed as `auth.${ENVIRONMENT}.${BURGDEV_HOST}`
   - `podinfo_domain` → Computed as `podinfo.${ENVIRONMENT}.${BURGDEV_HOST}`

3. **zitadel-terraform-credentials Secret**:
   - `zitadel_jwt_profile` → Machine user JSON key

Example for staging with `BURGDEV_HOST=burgdev.local.gd`:
- Zitadel domain: `auth.staging.burgdev.local.gd`
- Podinfo domain: `podinfo.staging.burgdev.local.gd`

## Cleanup / Removal

When you delete the `terraform.yaml` resource, tofu-controller automatically runs `terraform destroy`, which:
- Removes the OIDC application from Zitadel
- Removes the project from Zitadel
- Deletes the `podinfo-oidc-credentials` Secret

This ensures your Zitadel state stays in sync with Git (true GitOps).

## Answers to Your Questions

### Can we use variable replacement in Terraform files by Flux?

**Yes!** The Terraform resource uses `varsFrom` to inject variables from ConfigMaps and Secrets:

```yaml
varsFrom:
  - kind: ConfigMap
    name: cluster-settings
    varsKeys:
      - BURGDEV_HOST
```

### Can we use the cluster-settings ConfigMap?

**Yes!** The configuration already references it, making it easy to keep URLs and settings consistent.

### Is it removed if you remove the YAML files?

**Yes!** Terraform's state is managed by tofu-controller, so removing the resource triggers `terraform destroy`.

### Can we create the machine user automatically?

**Yes!** The Zitadel Helm chart creates it during the first installation. You just need to retrieve the credentials and create the Kubernetes Secret. See `k8s/infrastructure/zitadel/MACHINE_USER_SETUP.md` for details.

## Next Steps

1. Commit and push all changes
2. Wait for Zitadel to deploy/redeploy
3. Retrieve machine user credentials and create Secrets
4. Watch Flux apply the Terraform configuration
5. Update your Podinfo deployment to use the OIDC credentials

Later, you can add global settings like Google or GitHub login by:
1. Creating additional Zitadel identity providers via Terraform
2. Linking them to projects as needed
