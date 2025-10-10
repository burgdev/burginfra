<script setup>
defineProps({
  namespace: String,
  path: String
})
</script>

<!-- code group does not work
::: code-group
:::
-->
```bash-vue [apply]
cd {{path}}
kubectl kustomize .     # see resulting files
# ./apply.sh            # run 'apply' script if available
kubectl apply -k .      # apply changes:
```
<details>
<summary>check status</summary>

```bash-vue [check status]
k9s -n {{namespace}}                   # tui
```
```bash-vue [check status]
kubectl get pods -n {{namespace}}      # see pods
kubectl get svc -n {{namespace}}       # see services
kubectl get ingress -n {{namespace}}   # see ingress
kubectl get pvc,pc -n {{namespace}}    # see persistent volumes (claims)
```
</details>