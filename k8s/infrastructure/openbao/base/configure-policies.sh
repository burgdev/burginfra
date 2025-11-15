#!/bin/bash
set -euo pipefail

export BAO_ADDR="${OPENBAO_ADDR}"

echo "========================================"
echo "OpenBao Configuration Script"
echo "========================================"
echo "Target: $BAO_ADDR"
echo ""

# Authenticate using Kubernetes service account
echo "==> Authenticating to OpenBao using Kubernetes auth..."
SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

if ! BAO_TOKEN=$(bao write -field=token auth/kubernetes/login role=openbao-admin jwt="$SA_TOKEN" 2>&1); then
	echo "ERROR: Failed to authenticate to OpenBao"
	echo "$BAO_TOKEN"
	exit 1
fi

export BAO_TOKEN
echo "✓ Authenticated successfully"

# Check OpenBao status
echo ""
echo "==> Checking OpenBao status..."
if ! bao status >/dev/null 2>&1; then
	echo "ERROR: Cannot connect to OpenBao or it is sealed"
	exit 1
fi
echo "✓ OpenBao is accessible and unsealed"

echo ""
echo "========================================"
echo "Creating/Updating Policies"
echo "========================================"

POLICIES_DIR="/policies"
MANAGED_POLICIES=()

# Default service account (can be overridden in policy file)
DEFAULT_SERVICE_ACCOUNT="vault-secrets-operator-controller-manager"

# Associative arrays to store policy metadata
declare -A POLICY_NAMESPACES
declare -A POLICY_SERVICE_ACCOUNTS
declare -A POLICY_ROLES

# Function to extract metadata from policy file
extract_metadata() {
	local file="$1"
	local policy_name=$(basename "$file" .hcl)

	# Extract OPENBAO_NAMESPACES
	local namespaces=$(grep "^# OPENBAO_NAMESPACES:" "$file" | sed 's/^# OPENBAO_NAMESPACES: *//' | tr -d '\r')

	# Extract OPENBAO_SERVICE_ACCOUNTS (optional, defaults to VSO SA)
	local service_accounts=$(grep "^# OPENBAO_SERVICE_ACCOUNTS:" "$file" | sed 's/^# OPENBAO_SERVICE_ACCOUNTS: *//' | tr -d '\r')

	# Extract OPENBAO_ROLE (optional, defaults to policy name)
	local role=$(grep "^# OPENBAO_ROLE:" "$file" | sed 's/^# OPENBAO_ROLE: *//' | tr -d '\r')

	# Store metadata
	if [ -n "$namespaces" ]; then
		POLICY_NAMESPACES["$policy_name"]="$namespaces"
	fi

	if [ -n "$service_accounts" ]; then
		POLICY_SERVICE_ACCOUNTS["$policy_name"]="$service_accounts"
	else
		POLICY_SERVICE_ACCOUNTS["$policy_name"]="$DEFAULT_SERVICE_ACCOUNT"
	fi

	if [ -n "$role" ]; then
		POLICY_ROLES["$policy_name"]="$role"
	fi
}

# Loop through all .hcl files and create policies
for policy_file in "$POLICIES_DIR"/*.hcl; do
	if [ -f "$policy_file" ]; then
		policy_name=$(basename "$policy_file" .hcl)

		echo "Processing policy: $policy_name"

		# Extract metadata
		extract_metadata "$policy_file"

		# Create/update the policy
		if bao policy write "$policy_name" "$policy_file"; then
			echo "  ✓ Policy '$policy_name' configured"
			MANAGED_POLICIES+=("$policy_name")
		else
			echo "  ✗ Failed to create policy '$policy_name'"
		fi
	fi
done

echo ""
echo "✓ Created/updated ${#MANAGED_POLICIES[@]} policies"

echo ""
echo "========================================"
echo "Creating Kubernetes Auth Roles"
echo "========================================"

MANAGED_ROLES=()

# Build namespace to policies mapping from policy metadata
declare -A NAMESPACE_TO_POLICIES

for policy_name in "${MANAGED_POLICIES[@]}"; do
	namespaces="${POLICY_NAMESPACES[$policy_name]:-}"

	# Skip policies without namespace metadata (like openbao-admin)
	if [ -z "$namespaces" ]; then
		continue
	fi

	# Split namespaces by comma
	IFS=',' read -ra NS_ARRAY <<<"$namespaces"
	for namespace in "${NS_ARRAY[@]}"; do
		# Trim whitespace
		namespace=$(echo "$namespace" | xargs)

		if [ -n "$namespace" ]; then
			# Append policy to namespace's policy list
			if [ -n "${NAMESPACE_TO_POLICIES[$namespace]:-}" ]; then
				NAMESPACE_TO_POLICIES[$namespace]="${NAMESPACE_TO_POLICIES[$namespace]},$policy_name"
			else
				NAMESPACE_TO_POLICIES[$namespace]="$policy_name"
			fi
		fi
	done
done

# Create roles for each namespace
for namespace in "${!NAMESPACE_TO_POLICIES[@]}"; do
	policies="${NAMESPACE_TO_POLICIES[$namespace]}"
	role_name="$namespace"

	# Use default service account (all policies should use the same SA in our case)
	service_account="$DEFAULT_SERVICE_ACCOUNT"

	echo "Creating/updating role: $role_name"
	echo "  Namespace: $namespace"
	echo "  Policies: $policies"
	echo "  Service Account: $service_account"

	if bao write auth/kubernetes/role/"$role_name" \
		bound_service_account_names="$service_account" \
		bound_service_account_namespaces="$namespace" \
		policies="$policies" \
		ttl=24h >/dev/null; then

		MANAGED_ROLES+=("$role_name")
		echo "  ✓ Role '$role_name' configured"
	else
		echo "  ✗ Failed to create role '$role_name'"
	fi
done

# Handle special roles (like openbao-admin with custom role name and multiple namespaces)
for policy_name in "${MANAGED_POLICIES[@]}"; do
	custom_role="${POLICY_ROLES[$policy_name]:-}"

	if [ -n "$custom_role" ]; then
		namespaces="${POLICY_NAMESPACES[$policy_name]:-}"
		service_account="${POLICY_SERVICE_ACCOUNTS[$policy_name]}"

		echo ""
		echo "Creating/updating special role: $custom_role"
		echo "  Policy: $policy_name"
		echo "  Namespaces: $namespaces"
		echo "  Service Account: $service_account"

		if bao write auth/kubernetes/role/"$custom_role" \
			bound_service_account_names="$service_account" \
			bound_service_account_namespaces="$namespaces" \
			policies="$policy_name" \
			ttl=1h >/dev/null; then

			MANAGED_ROLES+=("$custom_role")
			echo "  ✓ Role '$custom_role' configured"
		else
			echo "  ✗ Failed to create role '$custom_role'"
		fi
	fi
done

echo ""
echo "✓ Created/updated ${#MANAGED_ROLES[@]} roles"

echo ""
echo "========================================"
echo "Cleanup - Removing Unmanaged Resources"
echo "========================================"

# Cleanup policies
echo "Checking for obsolete policies..."
ALL_POLICIES=$(bao policy list)

for policy in $ALL_POLICIES; do
	# Skip system policies
	if [[ "$policy" == "default" || "$policy" == "root" ]]; then
		continue
	fi

	# Check if this policy is managed by us
	is_managed=false
	for managed in "${MANAGED_POLICIES[@]}"; do
		if [[ "$policy" == "$managed" ]]; then
			is_managed=true
			break
		fi
	done

	# Delete if not managed
	if [[ "$is_managed" == "false" ]]; then
		echo "  Removing obsolete policy: $policy"
		bao policy delete "$policy" 2>/dev/null || echo "    (failed to delete, may be in use)"
	fi
done
echo "✓ Policy cleanup complete"

# Cleanup roles
echo ""
echo "Checking for obsolete roles..."
ALL_ROLES=$(bao list -format=json auth/kubernetes/role 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

for role in $ALL_ROLES; do
	# Check if this role is managed by us
	is_managed=false
	for managed in "${MANAGED_ROLES[@]}"; do
		if [[ "$role" == "$managed" ]]; then
			is_managed=true
			break
		fi
	done

	# Delete if not managed
	if [[ "$is_managed" == "false" ]]; then
		echo "  Removing obsolete role: $role"
		bao delete "auth/kubernetes/role/$role" 2>/dev/null || echo "    (failed to delete)"
	fi
done
echo "✓ Role cleanup complete"

echo ""
echo "========================================"
echo "Configuration Summary"
echo "========================================"

echo ""
echo "Policies (${#MANAGED_POLICIES[@]}):"
for policy in "${MANAGED_POLICIES[@]}"; do
	echo "  ✓ $policy"
done

echo ""
echo "Namespace Mappings (${#NAMESPACE_TO_POLICIES[@]}):"
for namespace in "${!NAMESPACE_TO_POLICIES[@]}"; do
	policies="${NAMESPACE_TO_POLICIES[$namespace]}"
	echo "  ✓ $namespace → $policies"
done

if [ ${#POLICY_ROLES[@]} -gt 0 ]; then
	echo ""
	echo "Special Roles:"
	for policy_name in "${!POLICY_ROLES[@]}"; do
		role="${POLICY_ROLES[$policy_name]}"
		echo "  ✓ $role (policy: $policy_name)"
	done
fi

echo ""
echo "✓ OpenBao configuration complete!"
