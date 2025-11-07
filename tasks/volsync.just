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

# ❓ Show help
[private]
[default]
help task="":
    @just-help flux {{task}}


