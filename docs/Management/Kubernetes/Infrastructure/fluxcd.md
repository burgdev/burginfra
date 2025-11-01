---
title: Flux CD
order: 10
---

# Flux CD for GitOps

[Flux CD](https://fluxcd.io/) is used for GitOps.

The structure is as follows:

```
k8s
├── applications
│   └── some-app
│       ├── base
│       │   ├── ...
│       │   ├── kustomization.yaml
│       ├── flux
│       │   └── local
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
│   └── local
│       └── kustomization.yaml
└── infrastructure
    └── some-service
        ├── base
        │   ├── ...
        │   ├── kustomization.yaml
        ├── flux
        │   └── local
        │       └── flux-kustom.yaml
        └── overlays
            └── ...
```

The important paths for flux are:

* `k8s/clusters/flux-system`: Defines flux components and git source
* `k8s/clusters/local|prod|staging`: Defines all other manifest files (e.g. `../../apps/podinfo/flux/local/flux-kustom.yaml`)
* `k8s/infrastructure|apps/flux`: Defines the source for flux for this resources (either git or helm)

As soon something is pushed to the branch defined in `k8s/clusters/flux-system/overlays/ENV/source.patch.yaml` flux will update the cluster
with the changes. 

This can be forced with:

```bash
just flux reconcile-git
just flux reconcile-helm
```
