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
kubectl delete namespace immich
```
Check if the namespace is deleted:

```bash
kubectl get namespace immich
```
If it "hangs" try this:

```bash
kubectl get namespace immich -o json | tr -d "\n" \
    | sed "s/\"finalizers\": \[[^]]*\]/\"finalizers\": []/" \
    | kubectl replace --raw /api/v1/namespaces/immich/finalize -f -
```