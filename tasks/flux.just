import 'core.just'


# 🚀 Initialize cluster with flux (env: dev|staging|prod)
bootstrap:
    @header "$(doc flux bootstrap)"
    kubectl apply -f k8s/clusters/flux-system/base/gotk-components.yaml
    @info "Wait until flux-system pods are ready, this can take a while ..."
    @info $'Run \'\e[34mjust flux create-deploy-key\e[0m\' to create the deploy key.'

# 🔑 create deploy key for flux-system git repository
create-deploy-key:
    @header "$(doc flux create-deploy-key)"
    flux create secret git flux-system --url=ssh://git@github.com/burgdev/burginfra.git
    @info "Add deploy key to github https://github.com/burgdev/burginfra/settings/keys/new"
    @info $'Run \'\e[34mjust flux deploy\e[0m\' to deploy.'
   
# 🚀 Deploy everything to a cluster (cluster: local|burginfra, dry: dry|no-dry)
deploy cluster="local" dry="dry":   
    #! ./.shell-wrapper.sh
    if [ -z $KUBECONFIG ]; then
        @error "KUBECONFIG is not set. Please set it first."
        exit 1
    fi
    current_cluster=$(kubectl config current-context)
    if [ "$current_cluster" != "{{cluster}}" ]; then
        warn "Current cluster is not set to '{{cluster}}'"
        read -p $'\e[1;31mAre you sure to continue? [y/N]\e[0m ' -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Aborted."
            exit 1
        fi
    fi
    header "🚀 Deploying to {{cluster}}" 
    cluster_path="k8s/clusters/flux-system/overlays/{{cluster}}"
    if [ "{{dry}}" == "no-dry" ]; then
        if ! git diff --quiet || ! git diff --cached --quiet; then
            error "Git working directory is not clean. Please commit or stash your changes first."
            exit 1
        fi
        if [ $(git rev-parse @) != $(git rev-parse @{u}) ]; then
            error "Your branch is not up to date with the remote. Please push to sync."
            exit 1
        fi
        #kubectl apply -k $cluster_path
        success "Deploy to {{cluster}} successful."
    else
        kubectl apply -k $cluster_path --dry-run=client
        success $'\e[1;33mDRY RUN\e[0m to {{cluster}} successful.'
        info $'Run \'\e[34mjust flux deploy {{cluster}} no-dry\e[0m\' to deploy.'
    fi
 
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


