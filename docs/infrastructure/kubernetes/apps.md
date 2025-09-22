---
title: Applications
order: 40
---
# Kubernetes Applications

This document lists and describes the applications running on our Kubernetes cluster.

## Application List

### [Immich](/apps/immich)

- **Namespace**: `immich`
- **Description**: Self-hosted photo and video backup solution
- **Storage**: Two volumes, one for databasee and one for the library (images)
- **Backup**: Not yet

```bash
kubectl get pods -n immich
```

### [Zitadel](/apps/zitadel)

- **Namespace**: `zitadel`
- **Description**: Identity and access management platform
- **Storage**: One volume for database
- **Backup**: Not yet

```bash
kubectl get pods -n zitadel
```

### Using kubectl

```bash
# Apply a manifest
kubectl apply -f path/to/manifest.yaml

# Check deployment status
kubectl get deployments -n <namespace>
```
