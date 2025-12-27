#!/bin/bash
# this should besourced!
#
# Color definitions (using tput for better compatibility)
if [ -t 1 ]; then
	# Only define colors if output is a terminal
	b=$(tput bold)
	d=$(tput dim)
	i=$(tput sitm)
	rst=$(tput sgr0)
	u=$(tput smul)
	nu=$(tput rmul)
	red=$(tput setaf 1)
	green=$(tput setaf 2)
	yellow=$(tput setaf 3)
	blue=$(tput setaf 4)
	cyan=$(tput setaf 6)
	magenta=$(tput setaf 5)
	white=$(tput setaf 7)
else
	# No colors if not a terminal
	b=""
	rst=""
	d=""
	u=""
	nu=""
	red=""
	green=""
	yellow=""
	blue=""
	cyan=""
	magenta=""
	white=""
fi

# Helper function for easier color usage
s() {
	local color=$1
	shift
	echo -n "${!color}$*${rst}"
}
style() {
	local color=$1
	shift
	echo -n "${!color}$*${rst}"
}
debug() {
	echo "${d}$1${rst}"
}
title() {
	echo "${b}${blue}==>${rst} ${b}${green}$1${rst}"
}
section() {
	echo " ${blue}=>${rst} ${green}$1${rst}"
}
info() {
	echo "$1"
}
warn() {
	echo "${yellow}$1${rst}"
}
error() {
	echo "${red}$1${rst}"
}
success() {
	echo "${b}${green}$1${rst}"
}

cluster_check() {
	if [ -z "${1-}" ]; then
		error "Usage: kubeconfig_check <local|staging|prod>"
		exit 1
	else
		cluster_name="$1"
	fi
	if [ -z $KUBECONFIG ]; then
		error "KUBECONFIG is not set. Please set it first."
		exit 1
	fi
	current_cluster=$(kubectl config current-context)
	if [ "$current_cluster" != "$cluster_name" ]; then
		warn "Current cluster ($current_cluster) is not set to '$cluster_name'"
		read -p $'\e[1;31mAre you sure to continue? [y/N]\e[0m ' -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			error "Aborted."
			exit 1
		fi
	fi
}

kubeconfig_check() {
	if [ -z "${1-}" ]; then
		error "Usage: kubeconfig_check <local|staging|prod>"
		exit 1
	else
		env_name=$1
	fi

	if [ -z "${KUBECONFIG-}" ]; then
		error "KUBECONFIG is not set"
		exit 1
	fi

	if [ "$env_name" == "dev" ]; then
		EXPECTED_KUBECONFIG="config-localhost"
	elif [ "$env_name" == "staging" ]; then
		EXPECTED_KUBECONFIG="config-burginfra.ch"
	elif [ "$env_name" == "prod" ]; then
		EXPECTED_KUBECONFIG="config-burginfra.ch"
	else
		error "Unknown environment: $env_name"
		echo "$USAGE"
		exit 1
	fi

	if [ "$(basename $KUBECONFIG)" != "$EXPECTED_KUBECONFIG" ]; then
		warn "$(s yellow KUBECONFIG) is not set to '$(s blue $EXPECTED_KUBECONFIG)'"
		read -p "Are you sure to coninue? [y/N] " -n 1 -r
		#echo    # move to a new line
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			error "Aborted."
			exit 1
		fi
	fi
}

# --- Single-key yes/no ---
ask_yes_no() {
	local prompt="$1"
	local default="$2"
	local def_upper def_lower
	if [[ "$default" == "y" ]]; then
		def_upper="Y"
		def_lower="n"
	else
		def_upper="y"
		def_lower="N"
	fi

	printf "${yellow}%s (${def_upper}/${def_lower}): ${rst}" "$prompt" >&2
	local answer
	IFS= read -r -n1 answer </dev/tty || true
	echo >&2
	if [[ -z "$answer" ]]; then
		echo "$default"
	elif [[ "$answer" =~ [Yy] ]]; then
		echo "y"
	else
		echo "n"
	fi
}

# --- Choose option ---
choose_option() {
	local prompt="$1"
	shift
	local options=("$@")
	local default="${options[0]}"

	printf "\n${cyan}%s${rst}\n" "$prompt" >&2
	for i in "${!options[@]}"; do
		printf " [%d] %s\n" "$i" "${options[$i]}" >&2
	done
	printf "Answer (default: %s): " "$default" >&2
	read -r choice </dev/tty
	if [[ -z "$choice" ]]; then
		echo "$default"
	elif [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 0 && choice < ${#options[@]})); then
		echo "${options[$choice]}"
	else
		echo "$choice"
	fi
}
