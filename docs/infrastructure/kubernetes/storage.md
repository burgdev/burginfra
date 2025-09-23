---
title: Storage
order: 30
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
  name: database-pv # PV_NAME
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  hostPath:
    path: /mnt/database # MOUNT_PATH
    type: DirectoryOrCreate
```
```yaml [pvc.yaml]
# PERSISTENT VOLUME CLAIM #
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database # PVC_NAME
  namespace: db  # NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
  volumeName: database-pv # PV_NAME (optional)
```
:::

### Commands

```bash
kubectl get pv # PV_NAME
kubectl get pvc -n NAMESPACE # PVC_NAME
```

 
#### Delete

::: warning
Deleting a PersistentVolumeClaim will not delete the underlying storage. You need to delete the PersistentVolume manually.
:::

::: tip
Often you can just delete the content directly on the file system (`rm -r MOUNT_PATH`).
:::

```bash
kubectl delete pvc -n NAMESPACE PVC_NAME
kubectl get pvc -n NAMESPACE PVC_NAME -w # wait until delted
```
Sometimes it can get stuck then run this command:

```bash
kubectl patch pvc PVC_NAME -n NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl get pvc -n NAMESPACE PVC_NAME # check again
```

After this you can check the persitent volume:

```bash
kubectl get pv PV_NAME
# if needed
kubectl delete pv PV_NAME
kubectl patch pv PV_NAME -p '{"metadata":{"finalizers":null}}' --type=merge
```

Remove the directory manually:
```bash
rm -rf MOUNT_PATH
```


