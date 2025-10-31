import 'core.just'

# ♻️  Reconcile everything
reconcile-all: reconcile-git reconcile-helm

# ♻️  Reconcile all GitRepositories
reconcile-git:
    @header "$(doc flux reconcile-git)"
    @kubectl get gitrepository -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' | \
    while read ns name; do \
        echo "Reconciling GitRepository $name in namespace $ns"; \
        flux reconcile source git "$name" -n "$ns"; \
    done

# ♻️  reconcile-git
[group("aliases")]
rg: reconcile-git

# ♻️  Reconcile all HelmReleases
reconcile-helm:
    @header "$(doc flux reconcile-helm)"
    @kubectl get helmrelease -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' | \
    while read ns name; do \
        echo "Reconciling HelmRelease $name in namespace $ns"; \
        flux reconcile helmrelease "$name" -n "$ns" --with-source; \
    done

# ♻️  reconcile-helm
[group("aliases")]
rh: reconcile-helm

# ❓ Show help
[private]
[default]
help task="":
    @just-help flux {{task}}


