---
title: OpenEBS
aside: false
---

# OpenEBS

[OpenEBS Local PV LVM](https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-lvm/lvm-overview) is used to mount local storage.

## Deployment

Since it is `ReadWriteOnce` it can only be used by one pod at a time.
Make sure to add

```yaml:no-line-numbers
spec:
  strategy:
    type: Recreate # NEEDED
```
to the deployment.

## Storage Classes

Two storage classes are defined:

* `fast-local-data-v0`: Local storage for data files (`ext4`)
* `fast-local-media-v0`: Local storage for media files (`xfs`), only for min 1Gi.

## `pvc` Templates


<<< @/../k8s/apps/podinfo-image/base/pvc_local_data.yaml{yaml:no-line-numbers}

## Setup

:memo: [Source Code](https://github.com/burgdev/burginfra/tree/main/k8s/infrastructure/openebs)

::: details :gear: Configuration {open}
<<< @/../k8s/infrastructure/openebs/configs/.env.template{dotenv:no-line-numbers} [configs/.env.template]
:::

::: details :package: Storage Classes
::: code-group
<<< @/../k8s/infrastructure/openebs/base/storageclass_fast_local_data_v0.yaml{yaml} [base/storageclass_fast_local_data_v0.yaml]
<<< @/../k8s/infrastructure/openebs/base/storageclass_fast_local_media_v0.yaml{yaml} [base/storageclass_fast_local_media_v0.yaml]
:::

::: details :package: Helm Installation
::: code-group
<<< @/../k8s/infrastructure/openebs/helm/base/values.yaml{yaml} [base/values.yaml]
<<< @/../k8s/infrastructure/openebs/helm/base/helmrelease.yaml{yaml} [base/helmrelease.yaml]
:::
::: details :rocket: Flux Kustomization
::: code-group
<<< @/../k8s/infrastructure/openebs/flux/local/flux-kustom.yaml{yaml} [flux/flux-kustom.yaml]
:::
