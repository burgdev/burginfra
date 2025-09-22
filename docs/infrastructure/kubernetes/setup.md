---
title: Setup
order: 0
---

Documentation for the [Kubernetes](https://kubernetes.io) setup.


## Requirements

### Mandatory

- **k3s** ([setup](/infrastructure/kubernetes/k3s-setup.md))

### Optional

- **k9s** ([setup](/infrastructure/kubernetes/k9s-setup.md))



## Common Commands

```bash
# Get cluster info
kubectl cluster-info

# Get nodes
kubectl get nodes

# Get all pods in all namespaces
kubectl get pods -A

# Get services
kubectl get svc -A
```
