#!/usr/bin/env bash
# Description: Run on your host to setup connection to the VPS
#
set -euo pipefail

### GLOBALS (can be overridden by environment variables) ###
K3S_USER="${K3S_USER:-burg}"
K3S_PORT="${K3S_PORT:-6443}"
K3S_HOST="${K3S_HOST:-infra-vps1.burgdev.ch}" # host or IP
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
	b=""
	rst=""
	d=""
	u=""
	nu=""
	R=""
	G=""
	Y=""
	B=""
	C=""
	M=""
	W=""
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

get_k3s_config_help="Get k3s config from the node"
get_k3s_config() {
	section "Get k3s config"
	scp $K3S_USER@$K3S_HOST:/etc/rancher/k3s/k3s.yaml $K3S_MY_CONFIG

	# Get the actual hostname from the remote server
	REMOTE_HOSTNAME=$(ssh $K3S_USER@$K3S_HOST hostname)
	echo "Remote hostname: $(s B $REMOTE_HOSTNAME)"

	# Replace localhost with the actual host
	sed -i "s|server: https://127.0.0.1:6443|server: https://${K3S_HOST}:${K3S_PORT}|" ${K3S_MY_CONFIG}

	# Replace "default" with the actual hostname in cluster name, context name, and user name
	sed -i "s|name: default|name: ${REMOTE_HOSTNAME}|g" ${K3S_MY_CONFIG}

	# Check if K3S_HOST is a domain name (not an IP)
	if ! [[ $K3S_HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "Detected domain name: $K3S_HOST"
		echo "Resolving IP address..."

		# Get IP address from domain
		K3S_IP=$(dig +short $K3S_HOST | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

		if [ -z "$K3S_IP" ]; then
			echo "$(s Y "Warning: Could not resolve $K3S_HOST to an IP address")"
			echo "$(s Y "Trying with getent...")"
			K3S_IP=$(getent hosts $K3S_HOST | awk '{ print $1 }' | head -1)
		fi

		if [ -n "$K3S_IP" ]; then
			echo "Resolved to: $(s B $K3S_IP)"
			echo "Replacing domain with IP in kubeconfig..."
			sed -i "s|server: https://${K3S_HOST}:${K3S_PORT}|server: https://${K3S_IP}:${K3S_PORT}|" ${K3S_MY_CONFIG}
			echo "$(s G "✓ Updated server to use IP: https://${K3S_IP}:${K3S_PORT}")"
		else
			echo "$(s R "Error: Could not resolve domain to IP address")"
			echo "$(s Y "Kubeconfig will use domain name, which may cause certificate issues")"
		fi
	else
		echo "Using IP address: $(s B $K3S_HOST)"
	fi
}

next_steps_help="Show next steps"
next_steps() {
	section "Next steps:"
	echo "$(s d "# Bootstrap Flux")"
	echo "cluster=local"
	echo "just flux bootstrap"
	echo "kubectl get pods -n flux-system # wait until ready"
	echo "just flux create-deploy-key"
	echo "$(s d "# Add deploy key to GitHub and deploy")"
	echo "just flux deploy \$cluster [no-dry]"
	echo ""
	echo "$(s d "# Configure secrets (fill out .env file if needed!")"
	echo "$(s d "# WAIT until namespaces are created")"
	echo "./k8s/infrastructure/volsync/apply-config \$cluster"
}

run_all_help="Runs all the following commands:"
run_all() {
	get_k3s_config
	echo $(s R Export kubeconfig)
	echo "export KUBECONFIG=$K3S_MY_CONFIG"
	next_steps
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
  $(s b run_all)                $(s d $run_all_help)
  $(s b get_k3s_config)         $(s d $get_k3s_config_help)
  $(s b next_steps)             $(s d $next_steps_help)
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
