import 'core.just'


# 🚀 Check kopia policies (env: staging|prod)
check-policies env="staging" configmap="kopia-policies":
    #! ./.shell-wrapper.sh
    header "$(doc volsync check-policies)"
    info "Output of global-policy.json:"
    policy=$(kubectl get configmap {{configmap}} -n {{env}} -o jsonpath='{.data.global-policy\.json}')
    if [[ -z $policy ]]; then
      error "No policy found or error in configmap {{configmap}} ({{env}})"
      exit 1
    fi
    echo "$policy" | jq .
    success "Policy format is valid."
    info "Output of repository.config:"
    config=$(kubectl get configmap {{configmap}} -n {{env}} -o jsonpath='{.data.repository\.config}')
    if [[ -z $config ]]; then
      error "No config found or error in configmap {{configmap}} ({{env}})"
      exit 1
    fi
    echo "$config" | jq .
    success "Config format is valid."

# 🚀 Apply config (cluster: local|burginfra)
apply-config cluster="local":
    #! ./.shell-wrapper.sh
    header "$(doc volsync apply-config)"
    env_secret="{{justfile_dir()}}/k8s/infrastructure/volsync/config/base/.env.secret"
    if [[ -z $env_secret ]]; then
      error "No env file file, please add to '$env_secret'"
      exit 1
    fi
    {{justfile_dir()}}/k8s/infrastructure/volsync/apply-config {{cluster}}
    info $'  Run \'\e[34mjust rclone apply-config {{cluster}}\e[0m\' to set rclone configs.'
    info $'  Run \'\e[34mjust bao restore\e[0m\' to restore openbao configs.'

# ❓ Show help
[private]
[default]
help task="":
    @just-help volsync {{task}}


