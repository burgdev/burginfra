#!/usr/bin/env bash
# Description: Install local Kubernetes cluster CA certificates to system trust store
# This eliminates browser warnings for self-signed certificates
#
# Usage:
#   ./install_local_ca.sh              - Install from all namespaces
#   ./install_local_ca.sh production   - Install from specific namespace only
#   ./install_local_ca.sh --watch      - Watch for changes and auto-update

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-localhost}"
CA_DIR="/usr/local/share/ca-certificates/k8s-local"
WATCH_MODE=false
SPECIFIC_NAMESPACE=""

# Helper function to run kubectl with proper TLS handling
# For clusters with self-signed certs we may need to skip verification
kubectl_cmd() {
	# First try normal kubectl
	if kubectl_cmd "$@" 2>/dev/null; then
		return 0
	fi

	# If that fails due to cert issues, try with insecure-skip-tls-verify
	kubectl_cmd --insecure-skip-tls-verify "$@"
}

# Parse arguments
if [ "${1:-}" = "--watch" ]; then
	WATCH_MODE=true
elif [ -n "${1:-}" ]; then
	SPECIFIC_NAMESPACE="$1"
fi

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
	echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
	echo -e "${RED}✗${NC} $1"
}

install_certificates() {
	echo "Installing CA certificates from Kubernetes cluster..."

	# Create CA directory
	sudo mkdir -p "$CA_DIR"

	# Track installed certificates
	declare -A installed_certs

	# Get namespaces to process
	if [ -n "$SPECIFIC_NAMESPACE" ]; then
		namespaces=("$SPECIFIC_NAMESPACE")
	else
		mapfile -t namespaces < <(kubectl_cmd get certificates --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' | sort -u)
	fi

	if [ ${#namespaces[@]} -eq 0 ]; then
		log_warn "No certificates found in the cluster"
		return 0
	fi

	# Process each namespace
	for namespace in "${namespaces[@]}"; do
		echo ""
		echo "Processing namespace: $namespace"

		# Get all certificates in the namespace
		mapfile -t certificates < <(kubectl_cmd get certificates -n "$namespace" -o name 2>/dev/null || true)

		if [ ${#certificates[@]} -eq 0 ]; then
			log_warn "No certificates found in $namespace"
			continue
		fi

		# Extract and install each CA certificate
		for cert in "${certificates[@]}"; do
			cert_name=$(echo "$cert" | cut -d/ -f2)
			secret_name=$(kubectl_cmd get "$cert" -n "$namespace" -o jsonpath='{.spec.secretName}' 2>/dev/null || echo "")

			if [ -z "$secret_name" ]; then
				log_warn "Could not find secret for certificate: $cert_name"
				continue
			fi

			echo "  Processing: $cert_name (secret: $secret_name)"

			# Create unique filename with namespace prefix
			cert_file="$CA_DIR/${namespace}_${cert_name}.crt"
			installed_certs["$cert_file"]=1

			# Extract CA certificate (or the cert itself for self-signed)
			ca_data=""
			if ca_data=$(kubectl_cmd get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.ca\.crt}' 2>/dev/null) && [ -n "$ca_data" ]; then
				: # ca.crt exists
			else
				# For self-signed certs without a separate CA, use the cert itself
				ca_data=$(kubectl_cmd get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || echo "")
			fi

			if [ -n "$ca_data" ]; then
				# Decode and save certificate
				echo "$ca_data" | base64 -d | sudo tee "$cert_file" >/dev/null

				# Get certificate details
				not_after=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")

				log_info "Installed $cert_file (expires: $not_after)"
			else
				log_error "No CA data found for $cert_name"
			fi
		done
	done

	# Clean up certificates that no longer exist in the cluster
	echo ""
	echo "Cleaning up old certificates..."
	if [ -d "$CA_DIR" ]; then
		for cert_file in "$CA_DIR"/*.crt; do
			if [ -f "$cert_file" ]; then
				if [ -z "${installed_certs[$cert_file]:-}" ]; then
					log_warn "Removing obsolete certificate: $(basename "$cert_file")"
					sudo rm "$cert_file"
				fi
			fi
		done
	fi

	# Update CA certificates
	echo ""
	echo "Updating system CA certificates..."
	sudo update-ca-certificates 2>&1 | grep -E "^(Adding|Removing|done)" || true

	echo ""
	log_info "Done! Certificates installed"

	# Show summary
	cert_count=$(find "$CA_DIR" -name "*.crt" 2>/dev/null | wc -l)
	echo ""
	echo "Summary:"
	echo "  - Total certificates installed: $cert_count"
	echo "  - Location: $CA_DIR"
	echo ""
	echo "You may need to restart your browser for changes to take effect."
}

watch_certificates() {
	log_info "Starting watch mode - will update certificates automatically"
	echo "Press Ctrl+C to stop"
	echo ""

	# Initial installation
	install_certificates

	# Watch for changes every 5 minutes
	while true; do
		sleep 300 # 5 minutes
		echo ""
		echo "Checking for certificate changes..."
		install_certificates
	done
}

# Main execution
if [ "$WATCH_MODE" = true ]; then
	watch_certificates
else
	install_certificates
fi
