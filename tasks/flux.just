import 'core.just'


# 🚀 Initialize cluster with flux (env: dev|staging|prod)
init env="dev":
    @header "$(doc flux init)"
    kubectl apply -f k8s/clusters/flux-system/base/gotk-components.yaml
    @info "Wait until flux-system pods are ready, this can take a while ..."
    @info "Run 'just flux create-deploy-key' to create the deploy key."

create-deploy-key:
    @header "$(doc flux create-deploy-key)"
    flux create secret git flux-system --url=ssh://git@github.com/burgdev/burginfra.git
    @info "Add deploy key to github https://github.com/burgdev/burginfra/settings/keys/new"
    @info "Run 'just flux gitrepos' to check if it works."
    @info "Run 'just flux deploy' to deploy."
   
# 🚀 Deploy everything
deploy env="dev":   
    @header "$(doc flux deploy)"
    @info "Deploy ..."
    kubectl apply -k k8s/clusters/flux-system/overlays/{{env}}
 
gitrepos:
    @header "$(doc flux gitrepos)"
    kubectl -n flux-system get gitrepositories

# ♻️  Reconcile everything
reconcile-all: reconcile-git reconcile-helm

# ♻️  reconcile-all
[group("aliases")]
ra: reconcile-all

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


