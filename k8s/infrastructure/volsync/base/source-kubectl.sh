#!/bin/bash

# ============================================================================
# kubectl Source Script
# ============================================================================
# Downloads the latest stable kubectl and adds it to PATH for use in backup scripts.
#
# Usage:
#   . /kopia-config/source-kubectl.sh [tools_dir]
#   source /kopia-config/source-kubectl.sh [tools_dir]
#
# Parameters:
#   tools_dir: directory to store kubectl binary (default: /cache/.volsync-tools)
#
# After sourcing, kubectl is available directly:
#   kubectl get pods
#
# Example:
#   . /kopia-config/source-kubectl.sh
#   kubectl get pods -n default
# ============================================================================

# Check if script is being sourced (not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	echo "ERROR: This script must be sourced, not executed directly" >&2
	echo "Usage: . /kopia-config/source-kubectl.sh [tools_dir]" >&2
	echo "   or: source /kopia-config/source-kubectl.sh [tools_dir]" >&2
	exit 1
fi

TOOLS_DIR="${1:-/cache/.volsync-tools}"
KUBECTL_PATH="$TOOLS_DIR/kubectl"

# Download kubectl if it doesn't exist
if [ ! -f "$KUBECTL_PATH" ]; then
	echo "==> Downloading latest stable kubectl (first run only)..." >&2
	mkdir -p "$TOOLS_DIR"

	# Get latest stable version
	echo "==> Fetching latest stable kubectl version..." >&2
	KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
	if [ -z "$KUBECTL_VERSION" ]; then
		echo "ERROR: Failed to fetch latest kubectl version" >&2
		echo "ERROR: Network error or API unavailable" >&2
		return 1
	fi
	echo "==> Latest stable version: ${KUBECTL_VERSION}" >&2

	# Download kubectl with error handling
	if ! curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o "$KUBECTL_PATH"; then
		echo "ERROR: Failed to download kubectl ${KUBECTL_VERSION}" >&2
		echo "ERROR: Network error occurred" >&2
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

	# Download checksum file for validation
	echo "==> Downloading kubectl checksum for verification..." >&2
	CHECKSUM_PATH="$TOOLS_DIR/kubectl.sha256"
	if ! curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" -o "$CHECKSUM_PATH"; then
		echo "ERROR: Failed to download kubectl checksum" >&2
		rm -f "$KUBECTL_PATH" "$CHECKSUM_PATH"
		return 1
	fi

	# Validate kubectl binary against checksum
	echo "==> Validating kubectl binary checksum..." >&2
	if ! echo "$(cat "$CHECKSUM_PATH")  $KUBECTL_PATH" | sha256sum --check --status; then
		echo "ERROR: kubectl checksum validation failed" >&2
		echo "ERROR: Binary may be corrupted or tampered with" >&2
		rm -f "$KUBECTL_PATH" "$CHECKSUM_PATH"
		return 1
	fi
	rm -f "$CHECKSUM_PATH" # Clean up checksum file
	echo "==> Checksum validation passed" >&2

	chmod +x "$KUBECTL_PATH"

	# Verify kubectl works
	if ! "$KUBECTL_PATH" version --client &>/dev/null; then
		echo "ERROR: Downloaded kubectl binary is not valid or executable" >&2
		rm -f "$KUBECTL_PATH"
		return 1
	fi

	echo "==> kubectl ${KUBECTL_VERSION} downloaded and cached at $KUBECTL_PATH" >&2
fi

# Add kubectl directory to PATH
export PATH="$TOOLS_DIR:$PATH"
