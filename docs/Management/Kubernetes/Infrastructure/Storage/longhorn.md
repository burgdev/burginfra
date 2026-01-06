---
title: Longhorn
aside: false
---

# Longhorn

[OpenEBS Local PV LVM](https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-lvm/lvm-overview) is used to mount local storage.

::: warning :rocket: Deployment
Currently not deployed
:::

## Storage Classes

Two storage classes are defined:

* `distributed-data-v0`: Distributed storage for data files (`ext4`)
* `distributed-data-encrypted-v0`: Distributed storage for data files (`ext4`), encrypted

## `pvc` Templates


```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc-v0
spec:
  accessModes:
    - ReadWriteOnce # ReadWriteMany is supported
  storageClassName: distributed-data-v0
  resources:
    requests:
      storage: 50M
```

## Setup

:memo: [Source Code](https://github.com/burgdev/burginfra/tree/main/k8s/infrastructure/longhorn)

::: details :gear: Configuration {open}
<<< @/../k8s/infrastructure/longhorn/configs/.env.template{dotenv:no-line-numbers} [configs/.env.template]
:::
::: details :key: Secrets {close}
<<< @/../k8s/infrastructure/longhorn/configs/.env.secret.template{dotenv:no-line-numbers} [configs/.env.secret.template]
:::


::: details :package: Helm Installation
::: code-group
<<< @/../k8s/infrastructure/longhorn/base/values.yaml{yaml} [base/values.yaml]
<<< @/../k8s/infrastructure/longhorn/base/helmrelease.yaml{yaml} [base/helmrelease.yaml]
:::

::: details :package: Storage Classes
::: code-group
<<< @/../k8s/infrastructure/longhorn/base/storageclasses.yaml{yaml} [base/storageclass_kdrive_data_v0.yaml]
:::
