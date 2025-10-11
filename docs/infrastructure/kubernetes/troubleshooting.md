---
title: Troubleshooting
order: 50
---
# Troubleshooting

## Delete namespace

::: warning
This will delete all resources in the namespace!
:::

```bash
NS=immich
kubectl delete namespace $NS
```
Check if the namespace is deleted:

```bash
kubectl get namespace $NS
```
If it "hangs" try this:

```bash
kubectl get namespace $NS -o json | tr -d "\n" \
    | sed "s/\"finalizers\": \[[^]]*\]/\"finalizers\": []/" \
    | kubectl replace --raw /api/v1/namespaces/$NS/finalize -f -
```

## Delete persistent volumes and claims

See [storage](/infrastructure/kubernetes/storage#delete).