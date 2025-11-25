# Zitadel Machine User Setup for Terraform

## Overview

The Zitadel Helm chart is configured to automatically create a machine user (service account) named `terraform-admin` during the first installation. This machine user is used by Terraform/OpenTofu to manage Zitadel resources via the API.

## How It Works

When Zitadel is first deployed, the setup job automatically:
1. Creates a machine user named `terraform-admin`
2. Generates a JSON key for authentication
3. Stores the key in a Kubernetes Secret

## Configuration

The machine user is configured in `helm/base/values.yaml`:

```yaml
FirstInstance:
  Org:
    Machine:
      Machine:
        Username: terraform-admin
        Name: "Terraform Service Account"
      MachineKey:
        ExpirationDate: "2026-11-24T00:00:00Z"
        Type: 1  # JSON key type
```

## Retrieving the Credentials

After Zitadel has been deployed, retrieve the machine user credentials:

### 1. Find the Secret Name

The secret is named after the machine username:

```bash
kubectl get secrets -n burginfra-staging | grep terraform-admin
```

Expected output: `terraform-admin`

### 2. Retrieve the JSON Key

```bash
# For staging
kubectl get secret terraform-admin -n burginfra-staging -o jsonpath='{.data.zitadel-key\.json}' | base64 -d > terraform-admin-staging.json

# For production
kubectl get secret terraform-admin -n burginfra-production -o jsonpath='{.data.zitadel-key\.json}' | base64 -d > terraform-admin-production.json
```

### 3. Create the Secret for Terraform Controller

Create the secret that tofu-controller will use:

```bash
# For staging
kubectl create secret generic zitadel-terraform-credentials \
  --from-file=zitadel_jwt_profile=./terraform-admin-staging.json \
  -n staging

# For production
kubectl create secret generic zitadel-terraform-credentials \
  --from-file=zitadel_jwt_profile=./terraform-admin-production.json \
  -n production
```

## Verification

Check that the machine user was created successfully:

```bash
# Check Zitadel setup job logs
kubectl logs -n burginfra-staging -l app.kubernetes.io/name=zitadel,app.kubernetes.io/component=setup

# Verify the secret exists
kubectl get secret terraform-admin -n burginfra-staging
```

## Key Expiration

The machine key is set to expire on **2026-11-24**. Before expiration:

1. Update the `ExpirationDate` in `values.yaml` to a future date
2. Delete the existing secret: `kubectl delete secret terraform-admin -n burginfra-staging`
3. Let Flux recreate Zitadel (or manually trigger a helm upgrade)
4. Retrieve the new key and update the `zitadel-terraform-credentials` secrets

## Permissions

The machine user is created with administrative permissions (IAM_OWNER role by default) which allows it to:
- Create and manage projects
- Create and manage applications
- Create and manage users
- Configure OIDC settings

## Troubleshooting

If the machine user wasn't created:

1. Check if Zitadel already had a FirstInstance configured (machine user only created on first install)
2. Check the setup job logs for errors
3. Verify the values.yaml configuration is correct
4. For existing Zitadel instances, you may need to create the machine user manually via the Zitadel UI

To manually create a machine user:
1. Log into Zitadel UI
2. Go to Organization → Service Accounts
3. Create new service account: `terraform-admin`
4. Generate a JSON key
5. Assign IAM_OWNER role
6. Download the JSON and create the Kubernetes secret
