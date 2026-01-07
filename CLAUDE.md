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

### Application Suspend Flags

Each application can be enabled/disabled per cluster using suspend variables:
- `VALHALLA_SUSPEND: "true|false"` - Valhalla routing engine
- `IMMICH_SUSPEND: "true|false"` - Immich photo management
- `UMAMI_SUSPEND: "true|false"` - Umami analytics
- `WODORE_SUSPEND: "true|false"` - Wodore application

Set to `"true"` to prevent Flux from reconciling the application (no resources created).
Set to `"false"` to enable the application.

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

## Resource Limits Best Practices

### CPU Limits
**DO NOT set CPU limits** (only set requests):
- CPU limits cause throttling which adds latency
- In single-node clusters, throttling has no scheduling benefit
- Kubernetes will still use requests for priority decisions

```yaml
resources:
  requests:
    cpu: 500m
  # NO limits.cpu
```

### Memory Limits
**ALWAYS set memory limits**:
- Memory limits prevent OOM crashes
- In single-node clusters, one runaway pod can kill the entire node
- Set limits ≈ 1.5-2× requests to allow burst capacity

```yaml
resources:
  requests:
    memory: 2Gi
  limits:
    memory: 4Gi  # Hard stop to protect node
```

### Guidelines
- **Memory-intensive jobs** (builds, processing): Set tight limits to prevent node OOM
- **Steady-state services**: Allow some headroom (1.5-2× requests)
- **Monitor regularly**: Use `kubectl top nodes` and `kubectl top pods` to track actual usage

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
