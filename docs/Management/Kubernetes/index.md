---
title: Overview
order: 0
---

# Overview

[Official Documentation](https://kubernetes.io/docs/home/) | [Quick Reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/)

# Kubernetes Setup

Documentation for the [Kubernetes](https://kubernetes.io) setup.

## Prerequisites

Install `k3s` as described in the [k3s setup](/Management/Kubernetes/Installation/k3s_Setup).

Very helpful is the `k9s` tool ([setup](/Management/Kubernetes/Installation/k9s_Setup)) as a terminal UI for `kubectl`.

## Initial Flux Setup

[Flux](https://fluxcd.io) is used for continuous delivery of Kubernetes resources.

```bash
cluster=local
just flux bootstrap
kubectl get pods -n flux-system # wait until ready
just flux create-deploy-key $cluster
# add deploy key to github
just flux deploy $cluster
# make sure all needed secrets are created
./k8s/Infrastructure/volsync/apply-config $cluster
```

Check connection:

```bash
just flux gitrepos
```

Force update:

```bash
just flux reconcile-git
just flux reconcile-helm
```

For more information about how to use flux see [Infrastructure/fluxcd](Infrastructure/fluxcd).

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

# Scale
DP=deployment_name
NS=namespace
kubectl scale deployment $DP --replicas=0 -n $NS # stop 
kubectl scale deployment $DP --replicas=1 -n $NS # start 
```
