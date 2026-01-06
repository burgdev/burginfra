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
just flux bootstrap
kubectl get pods -n flux-system # wait until ready
just flux create-deploy-key local
# add deploy key to github
just flux deploy local
```

Check connection:

```bash
just flux gitrepos
```

Force uodate:

```bash
just flux reconcile
```

<!-- # --8<-- [end:readme_index] <!-- -->

## License

MIT - See [LICENSE](LICENSE) for details.
