---
title: Storage
order: 30
outline: [2,4]
---
# Storage

[Introduction](https://www.simplyblock.io/blog/kubernetes-storage-concepts/) | [Official Documentation](https://kubernetes.io/docs/concepts/storage/)

## Local storage

For local testing/deployments `local-path` storage class is used.

::: code-group
```yaml [pv.yaml]
# PERSISTENT VOLUME #
apiVersion: v1
kind: PersistentVolume
metadata:
  name: database-pv # PV
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  hostPath:
    path: /mnt/database # MOUNT
    type: DirectoryOrCreate
```
```yaml [pvc.yaml]
# PERSISTENT VOLUME CLAIM #
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database # PVC
  namespace: db  # NS
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
  volumeName: database-pv # PV (optional)
```
:::

### Commands

You an use this settings for the following commands

```dotenv [variables]
NS=db
PV=database-pv
PVC=database
MOUNT=/mnt/database
```

#### Status

```bash
kubectl get pv $PV
kubectl get pvc -n $NS $PVC
```

 
#### Delete

::: warning
Deleting a PersistentVolumeClaim will not delete the underlying storage. You need to delete the PersistentVolume manually.
:::

::: tip
Often you can just delete the content directly on the file system (`rm -r MOUNT_PATH`).
:::

```bash
kubectl delete pvc -n $NS $PVC
kubectl get pvc -n $NS $PVC -w # wait until delted
```
Sometimes it can get stuck then run this command:

```bash
kubectl patch pvc $PVC -n $NS -p \
  '{"metadata":{"finalizers":null}}' --type=merge
```

After this you can check the persitent volume:

```bash
kubectl get pv $PV
# if needed
# kubectl delete pv $PV
# kubectl patch pv $PV -p '{"metadata":{"finalizers":null}}' --type=merge
```

Remove the directory manually:
```bash
rm -rf $MOUNT
```


