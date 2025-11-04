---
title: Overview
---

# Infrastructure

The infrastructure is managed by [Flux CD](https://fluxcd.io/).

The structure is as follows:

```tree:no-line-numbers{7-9,21-22,28-30}
k8s
├── applications
│   └── some-app
│       ├── base
│       │   ├── ...
│       │   ├── kustomization.yaml
│       ├── flux
│       │   └── local|prod|staging
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
        │   └── local|prod|staging
        │       └── flux-kustom.yaml
        ├── helm                       # optional
        │   ├── base
        │   │   ├── kustomization.yaml
        │   │   ├── values.yaml
        │   │   └── namespace.yaml
        │   └── overlays
        │       └── local|prod|staging
        │           └── flux-kustom.yaml
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

## Resources
* [Flux Kustomization](https://fluxcd.io/docs/components/kustomize/kustomization/)
  * [Substitute](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
* [Source Controllers](https://fluxcd.io/flux/components/source/)
