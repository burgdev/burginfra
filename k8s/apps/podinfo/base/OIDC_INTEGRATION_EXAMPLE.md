# Using OIDC Credentials in Podinfo

The Terraform configuration automatically creates OIDC credentials and stores them in a Secret named `podinfo-oidc-credentials`.

## Example: Adding OIDC Environment Variables to Deployment

To use the OIDC credentials in your application, you can reference them in the deployment:

```yaml
spec:
  template:
    spec:
      containers:
        - name: podinfo
          env:
            - name: OIDC_CLIENT_ID
              valueFrom:
                secretKeyRef:
                  name: podinfo-oidc-credentials
                  key: client_id
            - name: OIDC_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: podinfo-oidc-credentials
                  key: client_secret
            - name: OIDC_ISSUER_URL
              valueFrom:
                secretKeyRef:
                  name: podinfo-oidc-credentials
                  key: issuer_url
            - name: OIDC_AUTHORIZATION_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: podinfo-oidc-credentials
                  key: authorization_endpoint
            - name: OIDC_TOKEN_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: podinfo-oidc-credentials
                  key: token_endpoint
            - name: OIDC_USERINFO_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: podinfo-oidc-credentials
                  key: userinfo_endpoint
```

Or use `envFrom` to load all credentials at once:

```yaml
spec:
  template:
    spec:
      containers:
        - name: podinfo
          envFrom:
            - secretRef:
                name: podinfo-oidc-credentials
                optional: true  # Set to true if OIDC is optional
```

## Prerequisites

Before the OIDC credentials Secret is available, you need to:

1. **Create the Zitadel Service Account JWT Profile Secret**:
   ```bash
   kubectl create secret generic zitadel-terraform-credentials \
     --from-file=zitadel_jwt_profile=/path/to/service-account.json \
     -n staging
   ```

2. **Apply the Terraform resource**: Flux will automatically apply it when you commit the changes

3. **Wait for Terraform to complete**: The Secret will be created after the first successful Terraform apply

## Checking Status

```bash
# Check Terraform resource status
kubectl get terraform podinfo-zitadel -n staging

# Check if the Secret was created
kubectl get secret podinfo-oidc-credentials -n staging

# View the Secret contents (base64 encoded)
kubectl get secret podinfo-oidc-credentials -n staging -o yaml
```
