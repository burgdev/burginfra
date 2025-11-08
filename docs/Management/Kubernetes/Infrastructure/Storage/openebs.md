---
title: OpenEBS
aside: false
---

# OpenEBS

[OpenEBS Local PV LVM](https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-lvm/lvm-overview) is used to mount local storage.

::: tip Node Setup
See [LVM setup](/Management/Linux/lvm) on how to setup the LVM in order to use it with OpenEBS.
:::

## Storage Classes

Two storage classes are defined:

* `fast-local-data-v0`: Local storage for data files (`ext4`)
* `fast-local-media-v0`: Local storage for media files (`xfs`), only for min 1Gi.

::: info [Shared Volumes](https://openebs.io/docs/main/user-guides/local-storage-user-guide/local-pv-lvm/configuration/lvm-storageclass-options#shared-optional)
If `paramters.share` is not set to `yes` in the storage class the volume can only be used by one pod at a time.
Use `Recreate` as `strategy` in the deployment to ensure data consistency.
:::

## `pvc` Templates

<<< @/../k8s/apps/podinfo/base/pvc_local_data.yaml{yaml:no-line-numbers}

## Snapshots

A `VolumeSnapshotClass` is required in order to create [snapshots](https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-lvm/advanced-operations/lvm-snapshot) of the volume.

::: warning Restore not supported
Restore is not supported yet but [is planned vor OpenEbs 4.4](https://github.com/openebs/openebs/issues/4071).

You could also use [OpenEBS Local PV ZFS](https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-zfs/zfs-overview) instead
which has more features.
:::

## Setup

:memo: [Source Code](https://github.com/burgdev/burginfra/tree/main/k8s/infrastructure/openebs)

::: details :gear: Configuration {open}
<<< @/../k8s/infrastructure/openebs/configs/.env.template{dotenv:no-line-numbers} [configs/.env.template]
:::

::: details :package: Storage Classes & Volume Snapshot Class
::: code-group
<<< @/../k8s/infrastructure/openebs/system/storageclass_fast_local_data_v1.yaml{yaml} [system/storageclass_fast_local_data_v1.yaml]
<<< @/../k8s/infrastructure/openebs/system/storageclass_fast_local_media_v1.yaml{yaml} [system/storageclass_fast_local_media_v1.yaml]
<<< @/../k8s/infrastructure/openebs/system/volumesnapshotclass.yaml{yaml} [system/volumesnapshotclass.yaml]
:::

::: details :package: Helm Installation
::: code-group
<<< @/../k8s/infrastructure/openebs/helm/system/values.yaml{yaml} [system/values.yaml]
<<< @/../k8s/infrastructure/openebs/helm/system/helmrelease.yaml{yaml} [system/helmrelease.yaml]
:::
::: details :rocket: Flux Kustomization
::: code-group
<<< @/../k8s/infrastructure/openebs/flux/system/flux-kustom.yaml{yaml} [flux/system/flux-kustom.yaml]
:::
