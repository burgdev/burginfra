#!/usr/bin/env bash
# Description: Run on your host to setup connection to the VPS
#
set -euo pipefail

### GLOBALS (can be overridden by environment variables) ###
K3S_USER="${K3S_USER:-burg}"
K3S_PORT="${K3S_PORT:-6443}"
K3S_HOST="${K3S_HOST:-infra.burgdev.ch}" # host or IP
K3S_MY_CONFIG="$HOME/.kube/config-${K3S_HOST}"

# Color definitions (using tput for better compatibility)
if [ -t 1 ]; then
  # Only define colors if output is a terminal
  b=$(tput bold)
  d=$(tput dim)
  i=$(tput sitm)
  rst=$(tput sgr0)
  u=$(tput smul)
  nu=$(tput rmul)
  R=$(tput setaf 1)
  G=$(tput setaf 2)
  Y=$(tput setaf 3)
  B=$(tput setaf 4)
  C=$(tput setaf 6)
  M=$(tput setaf 5)
  W=$(tput setaf 7)
else
  # No colors if not a terminal
  b=""; rst=""; d=""; u=""; nu=""
  R=""; G=""; Y=""; B=""; C=""; M=""; W=""
fi

# Helper function for easier color usage
s() {
  local color=$1
  shift
  echo -n "${!color}$*${rst}"
}

section() {
  echo -e "${b}${G}==> $1${rst}"
}

get_k3s_config="Get k3s config from the node"
get_k3s_config() {
  section "Get k3s config"
  scp $K3S_USER@$K3S_HOST:/etc/rancher/k3s/k3s.yaml $K3S_MY_CONFIG
  sed -i "s|server: https://127.0.0.1:6443|server: https://${K3S_HOST}:${K3S_PORT}|" ${K3S_MY_CONFIG}
}



run_all_help="Runs all the following commands:"
run_all() {
  get_k3s_config
  echo $(s R Export kubeconfig)
  echo "export KUBECONFIG=$K3S_MY_CONFIG"
}

### 15. Help Menu ###
help_menu() {
  echo "$(s d Usage:) sudo [$(s i ENV_OVERRIDES)] $(s b $0) [command...]

$(s Y Examples:)
  sudo ./setup_myself.sh run_all
  K3S_USER=infra ./setup_myself.sh get_k3s_config

$(s Y Environment variables:)
  $(s b K3S_USER)               User for SSH and kubeconfig ownership (default: $(s B ${K3S_USER}))
  $(s b K3S_PORT)               k3s API port (default: $(s B ${K3S_PORT}))
  $(s b K3S_HOST)               k3s API host/IP (default: $(s B ${K3S_HOST}))
  $(s b K3S_MY_CONFIG)          k3s config on my PC (default: $(s B ${K3S_MY_CONFIG}))

$(s Y Commands:)
  $(s b run_all)                 $(s d $run_all_help)  
  $(s b get_k3s_config)             $(s d $install_k3s_help)
"
}

main() {
  if [ $# -eq 0 ]; then
    help_menu
    exit 1
  fi
  for cmd in "$@"; do
    if declare -f "$cmd" >/dev/null 2>&1; then
       "$cmd"
    else
      echo "Unknown command: $cmd"
      help_menu
      exit 1
    fi
  done
}

main "$@"
