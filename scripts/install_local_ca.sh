#!/usr/bin/env bash
# Description: Install local Kubernetes cluster CA certificates to system trust store
# This eliminates browser warnings for self-signed certificates
#
# Usage:
#   ./install_local_ca.sh              - Install root CA
#   ./install_local_ca.sh --watch      - Watch for changes and auto-update

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-localhost}"
CA_DIR="/usr/local/share/ca-certificates/k8s-local"
WATCH_MODE=false
ROOT_CA_NAMESPACE="burginfra-system"
ROOT_CA_SECRET="local-root-ca-secret"

# Helper function to run kubectl with proper TLS handling
# For clusters with self-signed certs we may need to skip verification
kubectl_cmd() {
	# First try normal kubectl
	if kubectl --kubeconfig="$KUBECONFIG" "$@" 2>/dev/null; then
		return 0
	fi

	# If that fails due to cert issues, try with insecure-skip-tls-verify
	kubectl --kubeconfig="$KUBECONFIG" --insecure-skip-tls-verify "$@"
}

# Parse arguments
if [ "${1:-}" = "--watch" ]; then
	WATCH_MODE=true
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

install_root_ca() {
	echo "Installing root CA certificate from Kubernetes cluster..."

	# Create CA directory
	sudo mkdir -p "$CA_DIR"

	# Check if root CA secret exists
	if ! kubectl_cmd get secret "$ROOT_CA_SECRET" -n "$ROOT_CA_NAMESPACE" &>/dev/null; then
		log_error "Root CA secret '$ROOT_CA_SECRET' not found in namespace '$ROOT_CA_NAMESPACE'"
		log_warn "Please ensure the cert-manager configuration has been applied"
		return 1
	fi

	# Extract root CA certificate
	cert_file="$CA_DIR/burginfra-local-root-ca.crt"
	
	echo "Extracting root CA certificate..."
	ca_data=$(kubectl_cmd get secret "$ROOT_CA_SECRET" -n "$ROOT_CA_NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || echo "")

	if [ -z "$ca_data" ]; then
		log_error "Could not extract CA certificate from secret"
		return 1
	fi

	# Decode and save certificate
	echo "$ca_data" | base64 -d | sudo tee "$cert_file" >/dev/null

	# Verify it's a CA certificate
	if ! openssl x509 -in "$cert_file" -noout -text | grep -q "CA:TRUE"; then
		log_error "Certificate is not a CA certificate (CA:TRUE not found)"
		log_warn "The root CA may not have been created yet. Waiting for cert-manager to create it..."
		return 1
	fi

	# Get certificate details
	subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unknown")
	not_after=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
	fingerprint=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || echo "Unknown")

	log_info "Root CA certificate installed: $cert_file"
	echo "  Subject: $subject"
	echo "  Expires: $not_after"
	echo "  SHA256: $fingerprint"

	# Clean up old certificates
	echo ""
	echo "Cleaning up old certificates..."
	for old_cert in "$CA_DIR"/*.crt; do
		if [ -f "$old_cert" ] && [ "$old_cert" != "$cert_file" ]; then
			log_warn "Removing old certificate: $(basename "$old_cert")"
			sudo rm "$old_cert"
		fi
	done

	# Update CA certificates
	echo ""
	echo "Updating system CA certificates..."
	sudo update-ca-certificates 2>&1 | grep -E "^(Adding|Removing|done)" || true

	echo ""
	log_info "Done! Root CA installed"
	echo ""
	echo "Summary:"
	echo "  - Root CA: $cert_file"
	echo "  - All certificates signed by this CA will now be trusted"
	echo ""
	echo "You may need to restart your browser for changes to take effect."
}

watch_certificates() {
	log_info "Starting watch mode - will update CA automatically"
	echo "Press Ctrl+C to stop"
	echo ""

	# Initial installation
	install_root_ca

	# Watch for changes every 5 minutes
	while true; do
		sleep 300 # 5 minutes
		echo ""
		echo "Checking for CA certificate changes..."
		install_root_ca
	done
}

# Main execution
if [ "$WATCH_MODE" = true ]; then
	watch_certificates
else
	install_root_ca
fi
