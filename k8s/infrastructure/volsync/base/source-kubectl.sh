#!/bin/bash

# ============================================================================
# kubectl Source Script
# ============================================================================
# Downloads kubectl and adds it to PATH for use in backup scripts.
#
# Usage:
#   . /kopia-config/source-kubectl.sh [version] [cache_dir]
#   source /kopia-config/source-kubectl.sh [version] [cache_dir]
#
# Parameters:
#   tools_dir: directory to store kubectl binary (default: /cache/.volsync-tools)
#
# After sourcing, kubectl is available directly:
#   kubectl get pods
#
# Example:
#   . /kopia-config/source-kubectl.sh "v1.31.0"
#   kubectl get pods -n default
# ============================================================================

# Check if script is being sourced (not executed)
if [[ "$${BASH_SOURCE[0]}" == "$${0}" ]]; then
	echo "ERROR: This script must be sourced, not executed directly" >&2
	echo "Usage: . /kopia-config/source-kubectl.sh [tools_dir]" >&2
	echo "   or: source /kopia-config/source-kubectl.sh [tools_dir]" >&2
	exit 1
fi

KUBECTL_VERSION="${KUBE_TOOLS_VERSION}"
TOOLS_DIR="$${2:-/cache/.volsync-tools}"
KUBECTL_PATH="$TOOLS_DIR/kubectl"

# Download kubectl if it doesn't exist
if [ ! -f "$KUBECTL_PATH" ]; then
	echo "==> Downloading kubectl $KUBECTL_VERSION (first run only)..." >&2
	mkdir -p "$TOOLS_DIR"

	# Download kubectl with error handling
	if ! curl -fsSL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl" -o "$KUBECTL_PATH"; then
		echo "ERROR: Failed to download kubectl $KUBECTL_VERSION" >&2
		echo "ERROR: Version may not exist or network error occurred" >&2
		echo "ERROR: Check available versions at: https://github.com/kubernetes/kubernetes/releases" >&2
		rm -f "$KUBECTL_PATH" # Clean up partial download
		return 1
	fi

	# Verify download succeeded and file is not empty
	if [ ! -s "$KUBECTL_PATH" ]; then
		echo "ERROR: Downloaded kubectl binary is empty or missing" >&2
		rm -f "$KUBECTL_PATH"
		return 1
	fi

	chmod +x "$KUBECTL_PATH"

	# Verify kubectl works
	if ! "$KUBECTL_PATH" version --client &>/dev/null; then
		echo "ERROR: Downloaded kubectl binary is not valid or executable" >&2
		rm -f "$KUBECTL_PATH"
		return 1
	fi

	echo "==> kubectl $KUBECTL_VERSION downloaded and cached at $KUBECTL_PATH" >&2
fi

# Add kubectl directory to PATH
export PATH="$TOOLS_DIR:$PATH"
