# Kubernetes Cluster

## Cluster Settings

Cluster-specific configuration variables are stored in ConfigMaps:

- **Local cluster**: `k8s/clusters/flux-system/overlays/local/cluster_settings.yaml`
- **Burginfra cluster**: `k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml`

These ConfigMaps contain environment-specific settings like:
- Domain names (e.g., `BURGDEV_HOST`, `CRUXLI_HOST`)
- Email addresses
- Certificate issuers
- Storage sizes
- Kubernetes version (`KUBE_VERSION`)

**Important**: Changes to cluster_settings.yaml must be manually applied using `kubectl apply -f <file>`.

## `local` Cluster

This runs locally and needs the following kubernetes config:

```bash
KUBECONFIG=$HOME/.kube/config-localhost
```

## `burginfra` Cluster

This is a single node server which runs on a VPS (8 CPUs, 16GB).

```bash
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
