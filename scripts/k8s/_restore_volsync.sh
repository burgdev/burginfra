#!/usr/bin/env bash
# Usage: source restore_base.sh
# Expects: $TEMPLATE_FILE, $CLUSTERS and $NAMESPACES to be set

# Source base functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../_base.sh"

if [ -z "${CLUSTERS+x}" ] || [ "${#CLUSTERS[@]}" -eq 0 ]; then
	CLUSTERS=("local" "burginfra")
fi
if [ -z "${NAMESPACES+x}" ] || [ "${#NAMESPACES[@]}" -eq 0 ]; then
	NAMESPACES=("staging" "production" "burginfra-staging" "burginfra-system")
fi
TEMPLATE_FILE=${TEMPLATE_FILE:-"configs/restore_volsync.template.yaml"}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# --- Prompt cluster/namespace ---
if [[ -z "${CLUSTER:-}" ]]; then
	CLUSTER=$(choose_option "Choose target cluster:" "${CLUSTERS[@]}")
fi

if [[ -z "${NAMESPACE:-}" ]]; then
	NAMESPACE=$(choose_option "Choose target namespace:" "${NAMESPACES[@]}")
fi

# --- Source cluster ---
if [[ -z "${SRC_CLUSTER:-}" || -z "${SRC_NAMESPACE:-}" ]]; then
	if [[ "$(ask_yes_no "Is the source the same as destination?" "y")" == "y" ]]; then
		SRC_CLUSTER="$CLUSTER"
		SRC_NAMESPACE="$NAMESPACE"
	else
		SRC_CLUSTER=$(choose_option "Choose source cluster:" "${CLUSTERS[@]}")
		SRC_NAMESPACE=$(choose_option "Choose source namespace:" "${NAMESPACES[@]}")
	fi
fi

# --- Restore as of date ---
if [[ -z "${RESTORE_AS_OF:-}" ]]; then
	# Get current date and time as default
	current_datetime=$(date +"%Y-%m-%d %H:%M")
	current_tz=$(date +"%z" | sed 's/^\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')

	printf "$(style yellow "Enter restore date and time (default: %s): ")" "$current_datetime" >&2
	read -r input_datetime </dev/tty

	# Use current datetime if empty
	if [[ -z "$input_datetime" ]]; then
		input_datetime="$current_datetime"
	fi

	# Validate format
	if [[ ! "$input_datetime" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
		error "Invalid format. Expected YYYY-MM-DD HH:MM" >&2
		exit 1
	fi

	# Convert to RFC-3339 format with timezone
	# Replace space with T, add :00 for seconds, and append timezone
	RESTORE_AS_OF=$(echo "$input_datetime" | sed 's/ /T/')":00${current_tz}"

	success "Restore as of: ${RESTORE_AS_OF}" >&2
fi

# --- Export vars ---
export CLUSTER NAMESPACE SRC_CLUSTER SRC_NAMESPACE TIMESTAMP RESTORE_AS_OF

# --- Generate YAML into variable ---
RESTORE_YAML=$(envsubst <"$TEMPLATE_FILE")

# --- Show summary and ask for confirmation ---
section "Restore Summary"
info "Template file:    ${TEMPLATE_FILE}"
info "Target cluster:   ${CLUSTER}"
info "Target namespace: ${NAMESPACE}"
info "Source cluster:   ${SRC_CLUSTER}"
info "Source namespace: ${SRC_NAMESPACE}"
info "Restore as of:    ${RESTORE_AS_OF}"
info "Timestamp:        ${TIMESTAMP}"
echo ""

if [[ "$(ask_yes_no "Proceed with restore?" "n")" != "y" ]]; then
	error "Restore cancelled by user."
	exit 1
fi

# --- Helper function to wait for restore (auto namespace and metadata.name) ---
wait_for_restore() {
	# Extract metadata.name from YAML
	local rd_name
	rd_name=$(echo "$RESTORE_YAML" | grep "^\s*name:" | head -n1 | awk '{print $2}')
	if [[ -z "$rd_name" ]]; then
		error "Failed to determine metadata.name from RESTORE_YAML"
		return 1
	fi

	# Extract manual trigger name from YAML
	local trigger_name
	trigger_name=$(echo "$RESTORE_YAML" | grep "^\s*manual:" | head -n1 | awk '{print $2}')
	if [[ -z "$trigger_name" ]]; then
		error "Failed to determine manual trigger name from RESTORE_YAML"
		return 1
	fi

	section "Waiting for ReplicationDestination $rd_name in namespace $NAMESPACE..."
	info " → Expected manual trigger: $trigger_name"

	# Spinner frames
	local FRAME=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
	local i=0
	local start_time=$(date +%s)

	while true; do
		# Get lastManualSync
		local last_sync
		last_sync=$(kubectl get replicationdestination "$rd_name" -n "$NAMESPACE" -o jsonpath='{.status.lastManualSync}' 2>/dev/null || echo "")

		if [[ "$last_sync" == "$trigger_name" ]]; then
			# Check result
			local result logs
			result=$(kubectl get replicationdestination "$rd_name" -n "$NAMESPACE" -o jsonpath='{.status.latestMoverStatus.result}' 2>/dev/null || echo "")
			logs=$(kubectl get replicationdestination "$rd_name" -n "$NAMESPACE" -o jsonpath='{.status.latestMoverStatus.logs}' 2>/dev/null || echo "")

			if [[ "$result" == "Successful" ]]; then
				echo ""
				success "Restore completed successfully!"
				break
			else
				echo ""
				error "Restore failed! Logs:"
				echo "$logs"
				return 1
			fi
		fi

		# Spinner with braille frames and elapsed time
		local now=$(date +%s)
		local elapsed=$((now - start_time))
		printf "\r%s Waiting Elapsed: %02d:%02d  " "${FRAME[i]}" $((elapsed / 60)) $((elapsed % 60))
		i=$(((i + 1) % ${#FRAME[@]}))

		sleep 0.2
	done
}
