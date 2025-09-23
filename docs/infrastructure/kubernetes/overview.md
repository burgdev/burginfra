---
title: Setup
order: 0
---
# Kubernetes Setup

Documentation for the [Kubernetes](https://kubernetes.io) setup.


## Prerequisites

Install `k3s` as described in the [k3s setup](/infrastructure/kubernetes/k3s-setup.md).

Very helpful is the `k9s` tool ([setup](/infrastructure/kubernetes/k9s-setup.md)) as a terminal UI for `kubectl`.



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
