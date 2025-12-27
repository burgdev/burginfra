# Kubernetes Cluster

## `local` Cluster

This runs local and need the following kubernetes config:

```
KUBECONFIG=$HOME/.kube/config-localhost
```

## `burginfra` Cluster

This is a single node server which runs on a vps (8 CPUs, 16GB).

```
KUBECONFIG=$HOME/.kube/config-infra-vps1.burgdev.ch
```

## Infrastructure

Kubernetes is managed by [Flux CD](https://fluxcd.io/).

The structure is as follows:

```
k8s
├── applications
│   ├── _deploy
│   │   ├── flux
│   │   │   └── ...
│   │   └── production|staging
│   │       └── ...
│   └── some-app
│       ├── base
│       │   ├── ...
│       │   ├── kustomization.yaml
│       ├── flux
│       │   └── production|staging
│       │       └── flux-kustom.yaml
│       └── overlays
│           └── ...
├── clusters
│   ├── flux-system
│   │   ├── base
│   │   │   ├── flux-kustom.yaml
│   │   │   ├── gotk-components.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── source.yaml
│   │   └── overlays
│   │       └── ...
│   └── _deploy
│       └── kustomization.yaml
└── infrastructure
│   ├── _deploy
│   │   ├── flux
│   │   │   └── ...
│   │   └── system|staging
│   │       └── ...
    └── some-service
        ├── base
        │   ├── ...
        │   ├── kustomization.yaml
        ├── flux
        │   └── production|staging
        │       └── flux-kustom.yaml
        ├── helm                       # optional
        │   ├── base
        │   │   ├── kustomization.yaml
        │   │   ├── values.yaml
        │   │   └── namespace.yaml
        │   └── overlays
        │       └── production|staging
        │           └── flux-kustom.yaml
        └── overlays
            └── ...

```
