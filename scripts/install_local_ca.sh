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

	# Install into browser NSS certificate stores
	echo ""
	echo "Installing into browser certificate stores..."
	
	# Initialize counters
	browsers_updated=0
	browsers_failed=0
	
	if ! command -v certutil &>/dev/null; then
		log_warn "certutil not found - skipping browser installation"
		log_warn "Install with: sudo apt install libnss3-tools"
	else
		# Check if browsers are running
		firefox_running=false
		chromium_running=false
		
		if pgrep -x "firefox" &>/dev/null || pgrep -f "firefox" &>/dev/null; then
			firefox_running=true
		fi
		
		if pgrep -x "brave" &>/dev/null || pgrep -f "brave-browser" &>/dev/null || \
		   pgrep -x "chromium" &>/dev/null || pgrep -x "chrome" &>/dev/null || \
		   pgrep -x "google-chrome" &>/dev/null; then
			chromium_running=true
		fi
		
		# Warn if browsers are running
		if [ "$firefox_running" = true ] || [ "$chromium_running" = true ]; then
			echo ""
			log_warn "The following browsers are currently running:"
			[ "$firefox_running" = true ] && echo "  - Firefox"
			[ "$chromium_running" = true ] && echo "  - Brave/Chromium/Chrome"
			log_warn "Browser certificate databases are locked while browsers are running"
			log_warn "Please close all browsers and run this script again"
			echo ""
		fi
		
		# Install into Firefox profiles
		if [ -d "$HOME/.mozilla/firefox" ]; then
			for profile_dir in "$HOME/.mozilla/firefox"/*.*/; do
				if [ -f "$profile_dir/cert9.db" ]; then
					profile_name=$(basename "$profile_dir")
					echo "  Installing into Firefox profile: $profile_name"
					
					# Remove old certificate if it exists
					certutil -D -n "BurgInfra Local Root CA" -d "sql:$profile_dir" 2>/dev/null || true
					
					# Add the certificate with trust flags for SSL/TLS
					# C = trusted CA, , = not trusted for email, , = not trusted for code signing
					if certutil -A -n "BurgInfra Local Root CA" -t "C,," -i "$cert_file" -d "sql:$profile_dir" 2>/dev/null; then
						log_info "Installed into Firefox profile: $profile_name"
						browsers_updated=$((browsers_updated + 1))
					else
						log_error "Failed to install into Firefox profile: $profile_name"
						if [ "$firefox_running" = true ]; then
							echo "    Reason: Firefox is running - close it and try again"
						fi
						browsers_failed=$((browsers_failed + 1))
					fi
				fi
			done
		fi
		
		# Install into Chromium/Chrome/Brave NSS database
		if [ -d "$HOME/.pki/nssdb" ]; then
			echo "  Installing into Chromium/Chrome/Brave certificate store"
			
			# Create the NSS database if it doesn't exist
			if [ ! -f "$HOME/.pki/nssdb/cert9.db" ]; then
				mkdir -p "$HOME/.pki/nssdb"
				certutil -N -d "sql:$HOME/.pki/nssdb" --empty-password 2>/dev/null || true
			fi
			
			# Remove old certificate if it exists
			certutil -D -n "BurgInfra Local Root CA" -d "sql:$HOME/.pki/nssdb" 2>/dev/null || true
			
			# Add the certificate with trust flags for SSL/TLS
			if certutil -A -n "BurgInfra Local Root CA" -t "C,," -i "$cert_file" -d "sql:$HOME/.pki/nssdb" 2>/dev/null; then
				log_info "Installed into Chromium/Chrome/Brave certificate store"
				browsers_updated=$((browsers_updated + 1))
			else
				log_error "Failed to install into Chromium/Chrome/Brave certificate store"
				if [ "$chromium_running" = true ]; then
					echo "    Reason: Brave/Chromium/Chrome is running - close it and try again"
				fi
				browsers_failed=$((browsers_failed + 1))
			fi
		else
			# Create the NSS database directory
			echo "  Creating Chromium/Chrome/Brave certificate store"
			mkdir -p "$HOME/.pki/nssdb"
			certutil -N -d "sql:$HOME/.pki/nssdb" --empty-password 2>/dev/null || true
			
			if certutil -A -n "BurgInfra Local Root CA" -t "C,," -i "$cert_file" -d "sql:$HOME/.pki/nssdb" 2>/dev/null; then
				log_info "Created and installed into Chromium/Chrome/Brave certificate store"
				browsers_updated=$((browsers_updated + 1))
			else
				log_error "Failed to create Chromium/Chrome/Brave certificate store"
				browsers_failed=$((browsers_failed + 1))
			fi
		fi
		
		# Summary of browser installations
		if [ "$browsers_failed" -gt 0 ]; then
			echo ""
			log_error "Failed to install CA into $browsers_failed browser certificate store(s)"
			log_warn "Close all browsers and run this script again"
		fi
	fi

	# Install into Python certifi bundle
	echo ""
	echo "Installing into Python certifi certificate stores..."
	
	# Initialize counter
	python_updated=0
	python_failed=0
	
	# Find all Python installations
	for python_cmd in python3 python; do
		if command -v "$python_cmd" &>/dev/null; then
			echo "  Checking $python_cmd..."
			
			# Get the certifi bundle path
			certifi_path=$($python_cmd -c "import certifi; print(certifi.where())" 2>/dev/null || echo "")
			
			if [ -z "$certifi_path" ]; then
				log_warn "$python_cmd: certifi module not found - skipping"
				log_warn "Install with: $python_cmd -m pip install certifi"
				continue
			fi
			
			# Check if our CA is already in the bundle
			if grep -q "BurgInfra Local Root CA" "$certifi_path" 2>/dev/null; then
				# Remove old certificate section
				# Create temp file without our old CA
				temp_file=$(mktemp)
				awk '/BurgInfra Local Root CA/,/END CERTIFICATE/ {next} {print}' "$certifi_path" > "$temp_file"
				sudo cp "$temp_file" "$certifi_path"
				rm "$temp_file"
			fi
			
			# Append our CA to the bundle with a label
			{
				echo ""
				echo "# BurgInfra Local Root CA"
				cat "$cert_file"
			} | sudo tee -a "$certifi_path" >/dev/null
			
			if [ $? -eq 0 ]; then
				log_info "Installed into $python_cmd certifi bundle: $certifi_path"
				python_updated=$((python_updated + 1))
			else
				log_error "Failed to install into $python_cmd certifi bundle"
				python_failed=$((python_failed + 1))
			fi
		fi
	done
	
	if [ "$python_updated" -eq 0 ] && [ "$python_failed" -eq 0 ]; then
		log_warn "No Python installations found"
	fi

	echo ""
	log_info "Done! Root CA installed"
	echo ""
	echo "Summary:"
	echo "  - Root CA: $cert_file"
	echo "  - System trust store: Updated"
	echo "  - Browser trust stores: $browsers_updated browser(s) updated"
	echo "  - Python certifi stores: $python_updated Python installation(s) updated"
	echo "  - All certificates signed by this CA will now be trusted"
	echo ""
	echo "IMPORTANT: You must completely close and restart your browser for changes to take effect."
	echo "           - Firefox: Use Ctrl+Q or File > Quit"
	echo "           - Brave/Chrome: Close all windows and quit completely"
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

# Ensure clean exit
exit 0
