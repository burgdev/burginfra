#!/bin/sh
set -eu

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
MANAGED_POLICIES=""

# Default service account
DEFAULT_SERVICE_ACCOUNT="vault-secrets-operator-controller-manager"

# Temporary files to store policy metadata
METADATA_FILE="/tmp/policy_metadata.txt"
> "$METADATA_FILE"

# Function to extract metadata from policy file
extract_metadata() {
	local file="$1"
	local policy_name=$(basename "$file" .hcl)

	# Extract OPENBAO_ACCESS (new format)
	local access_methods=$(grep "^# OPENBAO_ACCESS:" "$file" | sed 's/^# OPENBAO_ACCESS: *//' | tr -d '\r' || true)

	# Extract Kubernetes-specific metadata (new format)
	local k8s_namespaces=$(grep "^# KUBERNETES_NAMESPACES:" "$file" | sed 's/^# KUBERNETES_NAMESPACES: *//' | tr -d '\r' || true)
	local k8s_role=$(grep "^# KUBERNETES_ROLE:" "$file" | sed 's/^# KUBERNETES_ROLE: *//' | tr -d '\r' || true)
	local k8s_service_account=$(grep "^# KUBERNETES_SERVICE_ACCOUNT:" "$file" | sed 's/^# KUBERNETES_SERVICE_ACCOUNT: *//' | tr -d '\r' || true)

	# Backward compatibility: Check for old format
	if [ -z "$access_methods" ] && [ -z "$k8s_namespaces" ]; then
		# Try old format
		k8s_namespaces=$(grep "^# OPENBAO_NAMESPACES:" "$file" | sed 's/^# OPENBAO_NAMESPACES: *//' | tr -d '\r' || true)
		k8s_service_account=$(grep "^# OPENBAO_SERVICE_ACCOUNTS:" "$file" | sed 's/^# OPENBAO_SERVICE_ACCOUNTS: *//' | tr -d '\r' || true)
		k8s_role=$(grep "^# OPENBAO_ROLE:" "$file" | sed 's/^# OPENBAO_ROLE: *//' | tr -d '\r' || true)
		
		# If we found old format metadata, set access to kubernetes
		if [ -n "$k8s_namespaces" ]; then
			access_methods="kubernetes"
		fi
	fi

	# Default service account if not specified
	if [ -z "$k8s_service_account" ]; then
		k8s_service_account="$DEFAULT_SERVICE_ACCOUNT"
	fi

	# Store metadata in file format: policy_name|access_methods|k8s_namespaces|k8s_service_account|k8s_role
	printf '%s|%s|%s|%s|%s\n' "$policy_name" "$access_methods" "$k8s_namespaces" "$k8s_service_account" "$k8s_role" >> "$METADATA_FILE"
}

# Loop through all .hcl files and create policies
for policy_file in "$POLICIES_DIR"/*.hcl; do
	if [ -f "$policy_file" ]; then
		policy_name=$(basename "$policy_file" .hcl)
		
		# Skip template file
		if [ "$policy_name" = "policy.template" ]; then
			continue
		fi

		echo "Processing policy: $policy_name"

		# Extract metadata
		extract_metadata "$policy_file"

		# Create/update the policy
		if bao policy write "$policy_name" "$policy_file"; then
			echo "  ✓ Policy '$policy_name' configured"
			if [ -z "$MANAGED_POLICIES" ]; then
				MANAGED_POLICIES="$policy_name"
			else
				MANAGED_POLICIES="$MANAGED_POLICIES $policy_name"
			fi
		else
			echo "  ✗ Failed to create policy '$policy_name'"
		fi
	fi
done

POLICY_COUNT=$(echo "$MANAGED_POLICIES" | wc -w)
echo ""
echo "✓ Created/updated $POLICY_COUNT policies"

echo ""
echo "========================================"
echo "Configuring Access Methods"
echo "========================================"

# Process Kubernetes access method
echo ""
echo "==> Kubernetes Auth Method"
echo ""

MANAGED_ROLES=""
NAMESPACE_POLICIES_FILE="/tmp/namespace_policies.txt"
> "$NAMESPACE_POLICIES_FILE"

# Build namespace to policies mapping from policy metadata
while IFS='|' read -r policy_name access_methods k8s_namespaces k8s_service_account k8s_role; do
	# Skip if kubernetes is not in access methods
	if [ -z "$access_methods" ] || ! printf '%s' "$access_methods" | grep -q "kubernetes"; then
		continue
	fi
	
	# Skip policies without namespace metadata
	if [ -z "$k8s_namespaces" ]; then
		continue
	fi
	
	# Skip policies with wildcard namespaces (handled as special roles)
	if [ "$k8s_namespaces" = "*" ]; then
		continue
	fi

	# Split namespaces by comma and process each
	printf '%s\n' "$k8s_namespaces" | tr ',' '\n' | while read -r namespace; do
		# Trim whitespace
		namespace=$(printf '%s' "$namespace" | xargs)
		
		if [ -n "$namespace" ] && [ "$namespace" != "*" ]; then
			# Append to namespace policies mapping
			printf '%s|%s\n' "$namespace" "$policy_name" >> "$NAMESPACE_POLICIES_FILE"
		fi
	done
done < "$METADATA_FILE"

# Create roles for each namespace
for namespace in $(cut -d'|' -f1 "$NAMESPACE_POLICIES_FILE" | sort -u); do
	# Collect all policies for this namespace
	policies=$(grep "^$namespace|" "$NAMESPACE_POLICIES_FILE" | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//')
	
	role_name="$namespace"

	# Use default service account (from first policy for this namespace)
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

		if [ -z "$MANAGED_ROLES" ]; then
			MANAGED_ROLES="$role_name"
		else
			MANAGED_ROLES="$MANAGED_ROLES $role_name"
		fi
		echo "  ✓ Role '$role_name' configured"
	else
		echo "  ✗ Failed to create role '$role_name'"
	fi
done

# Handle wildcard namespace policies and custom roles
while IFS='|' read -r policy_name access_methods k8s_namespaces k8s_service_account k8s_role; do
	# Skip if kubernetes is not in access methods
	if [ -z "$access_methods" ] || ! printf '%s' "$access_methods" | grep -q "kubernetes"; then
		continue
	fi
	
	# Skip if no namespaces specified
	if [ -z "$k8s_namespaces" ]; then
		continue
	fi
	
	# Process wildcard namespaces or custom role
	if [ "$k8s_namespaces" = "*" ] || [ -n "$k8s_role" ]; then
		# Use custom role name if specified, otherwise use policy name for wildcards
		if [ -n "$k8s_role" ]; then
			role_to_create="$k8s_role"
		else
			role_to_create="$policy_name"
		fi

		echo ""
		echo "Creating/updating role: $role_to_create"
		echo "  Policy: $policy_name"
		echo "  Namespaces: $k8s_namespaces"
		echo "  Service Account: $k8s_service_account"

		if bao write auth/kubernetes/role/"$role_to_create" \
			bound_service_account_names="$k8s_service_account" \
			bound_service_account_namespaces="$k8s_namespaces" \
			policies="$policy_name" \
			ttl=1h >/dev/null; then

			if [ -z "$MANAGED_ROLES" ]; then
				MANAGED_ROLES="$role_to_create"
			else
				MANAGED_ROLES="$MANAGED_ROLES $role_to_create"
			fi
			echo "  ✓ Role '$role_to_create' configured"
		else
			echo "  ✗ Failed to create role '$role_to_create'"
		fi
	fi
done < "$METADATA_FILE"

ROLE_COUNT=$(echo "$MANAGED_ROLES" | wc -w)
echo ""
echo "✓ Created/updated $ROLE_COUNT Kubernetes roles"

echo ""
echo "========================================"
echo "Cleanup - Removing Unmanaged Resources"
echo "========================================"

# Cleanup policies
echo "Checking for obsolete policies..."
ALL_POLICIES=$(bao policy list)

for policy in $ALL_POLICIES; do
	# Skip system policies
	if [ "$policy" = "default" ] || [ "$policy" = "root" ]; then
		continue
	fi

	# Check if this policy is managed by us
	is_managed=false
	for managed in $MANAGED_POLICIES; do
		if [ "$policy" = "$managed" ]; then
			is_managed=true
			break
		fi
	done

	# Delete if not managed
	if [ "$is_managed" = "false" ]; then
		echo "  Removing obsolete policy: $policy"
		bao delete "sys/policy/$policy" 2>/dev/null || echo "    (failed to delete, may be in use)"
	fi
done
echo "✓ Policy cleanup complete"

# Cleanup Kubernetes roles
echo ""
echo "Checking for obsolete Kubernetes roles..."
ALL_ROLES=$(bao list -format=json auth/kubernetes/role 2>/dev/null | grep -o '"[^"]*"' | tr -d '"' || echo "")

for role in $ALL_ROLES; do
	# Check if this role is managed by us
	is_managed=false
	for managed in $MANAGED_ROLES; do
		if [ "$role" = "$managed" ]; then
			is_managed=true
			break
		fi
	done

	# Delete if not managed
	if [ "$is_managed" = "false" ]; then
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
echo "Policies ($POLICY_COUNT):"
for policy in $MANAGED_POLICIES; do
	echo "  ✓ $policy"
done

echo ""
echo "Kubernetes Namespace Mappings:"
if [ -s "$NAMESPACE_POLICIES_FILE" ]; then
	for namespace in $(cut -d'|' -f1 "$NAMESPACE_POLICIES_FILE" | sort -u); do
		policies=$(grep "^$namespace|" "$NAMESPACE_POLICIES_FILE" | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//')
		echo "  ✓ $namespace → $policies"
	done
else
	echo "  (none)"
fi

# Show custom Kubernetes roles
CUSTOM_ROLES=""
while IFS='|' read -r policy_name access_methods k8s_namespaces k8s_service_account k8s_role; do
	if [ -n "$k8s_role" ] && printf '%s' "$access_methods" | grep -q "kubernetes"; then
		if [ -z "$CUSTOM_ROLES" ]; then
			CUSTOM_ROLES="yes"
			echo ""
			echo "Custom Kubernetes Roles:"
		fi
		echo "  ✓ $k8s_role (policy: $policy_name, namespaces: $k8s_namespaces)"
	fi
done < "$METADATA_FILE"

echo ""
echo "✓ OpenBao configuration complete!"

# Cleanup temp files
rm -f "$METADATA_FILE" "$NAMESPACE_POLICIES_FILE"
