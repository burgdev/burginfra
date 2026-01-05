# Flux Image Update Webhooks for GitHub

This document describes how to set up webhooks to trigger immediate image updates when new container images are pushed to GitHub Container Registry (GHCR).

## Overview

Instead of waiting for Flux to poll the container registry every 5 minutes, you can configure GitHub to send a webhook notification to Flux whenever a new image is pushed. This enables near-instant deployments.

## Prerequisites

- Flux image-reflector-controller and image-automation-controller installed
- GitHub repository with container registry access
- Ingress controller configured in your cluster

## Setup Steps

### 1. Create a Receiver in Flux

Create a `Receiver` resource that will handle incoming webhooks from GitHub:

```yaml
# k8s/apps/wodore/apps/backend/base/image-webhook.yaml
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: wd-backend-image-updates
spec:
  type: github
  events:
    - "ping"
    - "package"  # GitHub Container Registry package event
  secretRef:
    name: webhook-token
  resources:
    - apiVersion: image.toolkit.fluxcd.io/v1beta2
      kind: ImageRepository
      name: wd-backend
```

### 2. Create a Webhook Secret

Generate a random token for webhook authentication:

```bash
# Generate random token
TOKEN=$(head -c 12 /dev/urandom | shasum | cut -d ' ' -f1)

# Create secret in the appropriate namespace
kubectl create secret generic webhook-token \
  --from-literal=token=$TOKEN \
  --namespace=staging  # or production

# Save the token for GitHub configuration
echo "Webhook token: $TOKEN"
```

### 3. Expose the Receiver via Ingress

Create an Ingress to make the webhook endpoint accessible from GitHub:

```yaml
# k8s/apps/wodore/apps/backend/overlays/staging/webhook-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wd-backend-webhook
  annotations:
    cert-manager.io/cluster-issuer: ${CERT_ISSUER}
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - webhook.staging.${WODORE_HOST}
      secretName: wd-backend-webhook-tls
  rules:
    - host: webhook.staging.${WODORE_HOST}
      http:
        paths:
          - path: /hook/
            pathType: Prefix
            backend:
              service:
                name: webhook-receiver
                port:
                  number: 80
```

### 4. Configure GitHub Webhook

1. Go to your GitHub repository settings
2. Navigate to "Webhooks" → "Add webhook"
3. Configure the webhook:
   - **Payload URL**: `https://webhook.staging.${WODORE_HOST}/hook/<receiver-path>`
   - **Content type**: `application/json`
   - **Secret**: Use the token generated in step 2
   - **Which events**: Select "Packages"
   - **Active**: Check this box

Get the receiver path:
```bash
kubectl get receiver wd-backend-image-updates -n staging \
  -o jsonpath='{.status.webhookPath}'
```

### 5. Test the Webhook

1. Push a new image to GHCR:
   ```bash
   docker tag my-image:latest ghcr.io/wodore/wodore-backend:edge-alpine
   docker push ghcr.io/wodore/wodore-backend:edge-alpine
   ```

2. Check GitHub webhook delivery (Settings → Webhooks → Recent Deliveries)

3. Verify Flux received the webhook:
   ```bash
   kubectl logs -n flux-system -l app=notification-controller
   ```

4. Check if the deployment was updated:
   ```bash
   kubectl rollout status deployment/wd-backend -n staging
   ```

## How It Works

1. You push a new container image to GHCR
2. GitHub sends a webhook to your Flux receiver
3. The notification-controller triggers the image-reflector-controller
4. Image-reflector-controller scans the registry immediately (bypasses the 5m interval)
5. If a new image digest is detected, the ImagePolicy is updated
6. Kustomize-controller detects the policy change and reconciles the deployment
7. Kubernetes performs a rolling update with the new image

## Benefits

- **Near-instant deployments**: Updates happen within seconds instead of waiting up to 5 minutes
- **Event-driven**: Only checks registry when something actually changed
- **Reduced API calls**: Less frequent polling means fewer registry API calls

## Security Considerations

- Use HTTPS for webhook endpoint (enforce TLS via cert-manager)
- Protect webhook secret and rotate regularly
- Consider IP allowlisting for GitHub webhook IPs
- Monitor webhook logs for suspicious activity

## Troubleshooting

### Webhook not triggering updates

1. Check receiver status:
   ```bash
   kubectl describe receiver wd-backend-image-updates -n staging
   ```

2. Verify webhook secret:
   ```bash
   kubectl get secret webhook-token -n staging -o jsonpath='{.data.token}' | base64 -d
   ```

3. Check notification-controller logs:
   ```bash
   kubectl logs -n flux-system -l app=notification-controller --tail=50
   ```

### GitHub webhook failing

1. Check webhook delivery in GitHub (Settings → Webhooks → Recent Deliveries)
2. Verify DNS resolution for webhook endpoint
3. Ensure Ingress is properly configured and TLS certificate is valid

## References

- [Flux Image Update Guide](https://fluxcd.io/flux/guides/image-update/)
- [Flux Webhooks](https://fluxcd.io/flux/guides/webhook-receivers/)
- [GitHub Package Webhooks](https://docs.github.com/en/webhooks-and-events/webhooks/webhook-events-and-payloads#package)
