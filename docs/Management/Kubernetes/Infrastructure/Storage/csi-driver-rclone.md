---
title: Rclone
aside: false
---

# Rclone CSI Driver

The [`rclone-csi-driver`](https://www.veloxpack.io/docs/csi-driver-rclone) from [VeloxPack](https://www.veloxpack.io/) is used to mount remote storage.
It supports all storage provider by [rclone](https://rclone.org/#providers).

## Storage Classes

Two storage classes are defined:

* `kdrive-data-v0`: optimized for data files
* `kdrive-media-v0`: optimized for media files

They both use [`kdrive`](https://www.infomaniak.com/en/ksuite/kdrive) as the storage provider.

## `pvc` Templates


```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: remote-data-pvc-v0
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: kdrive-data-v0
  resources:
    requests:
      storage: 50M
```

## Setup

:memo: [Source Code](https://github.com/burgdev/burginfra/tree/main/k8s/infrastructure/csi-driver-rclone)

::: details :key: Secrets {close}
<<< @/../k8s/infrastructure/csi-driver-rclone/configs/.env.secret.template{dotenv:no-line-numbers} [configs/.env.secret.template]
:::

::: details :package: Helm Installation
::: code-group
<<< @/../k8s/infrastructure/csi-driver-rclone/helm/base/values.yaml{yaml} [helm/base/values.yaml]
<<< @/../k8s/infrastructure/csi-driver-rclone/helm/base/helmrelease.yaml{yaml} [helm/base/helmrelease.yaml]
:::

::: details :package: Storage Classes
::: code-group
<<< @/../k8s/infrastructure/csi-driver-rclone/base/storageclass_kdrive_data_v0.yaml{yaml} [base/storageclass_kdrive_data_v0.yaml]
<<< @/../k8s/infrastructure/csi-driver-rclone/base/storageclass_kdrive_media_v0.yaml{yaml} [base/storageclass_kdrive_media_v0.yaml]
:::
