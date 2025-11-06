<p align="center">
  <a href="https://burgdev.github.io/imgora"><img src="/assets/logo_banner_burginfra.png" alt="BurgInfra" width="400" /></a>
</p>
<p align="center">
    <em>Infrastructure for burgdev web services</em>
</p>
<!-- <p align="center">
    <b><a href="https://burgdev.github.io/burginfra">Documentation</a></b>
</p>
-->

---
<!-- # --8<-- [start:readme_index] <!-- -->

## Initial Setup

### Local

```bash
kubectl apply -f k8s/clusters/flux-system/base/gotk-components.yaml
kubectl get pods -n flux-system # wait until ready
kubectl apply -k k8s/clusters/flux-system/overlays/local
# create deploy key
flux create secret git flux-system --url=ssh://git@github.com/burgdev/burginfra.git
# add deploy key to github
```

Check connection:

```bash
kubectl -n flux-system get gitrepositories
```

Force uodate:

```bash
flux reconcile source git git-burginfra-dev --namespace flux-system
```

<!-- # --8<-- [end:readme_index] <!-- -->

## License

MIT - See [LICENSE](LICENSE) for details.
