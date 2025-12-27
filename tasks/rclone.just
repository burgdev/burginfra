import 'core.just'

# 🚀 Apply config (cluster: local|burginfra)
apply-config cluster="local":
    #! ./.shell-wrapper.sh
    header "$(doc rclone apply-config)"
    env_secret="{{justfile_dir()}}/k8s/infrastructure/csi-driver-rclone/config/base/.env.secret"
    if [[ -z $env_secret ]]; then
      error "No env file file, please add to '$env_secret'"
      exit 1
    fi
    {{justfile_dir()}}/k8s/infrastructure/csi-driver-rclone/apply-config {{cluster}}

# ❓ Show help
[private]
[default]
help task="":
    @just-help volsync {{task}}


