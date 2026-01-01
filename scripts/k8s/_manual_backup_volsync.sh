#!/usr/bin/env bash
# Usage: source _manual_backup_volsync.sh
# Expects: $BACKUP_NAME to be set (e.g., "wd-backend")
# Optional: $CLUSTERS, $NAMESPACES, $FILTERS (array of filter patterns, default: "*")
# Provides functions to trigger and monitor VolSync backups

# Source base functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../_base.sh"

if [ -z "${CLUSTERS+x}" ] || [ "${#CLUSTERS[@]}" -eq 0 ]; then
	CLUSTERS=("local" "burginfra")
fi
if [ -z "${NAMESPACES+x}" ] || [ "${#NAMESPACES[@]}" -eq 0 ]; then
	NAMESPACES=("staging" "production" "burginfra-staging" "burginfra-system")
fi
if [ -z "${FILTERS+x}" ] || [ "${#FILTERS[@]}" -eq 0 ]; then
	FILTERS=("*")
fi

# Validate BACKUP_NAME is set
if [ -z "${BACKUP_NAME:-}" ]; then
	error "BACKUP_NAME must be set before sourcing this script"
	exit 1
fi

# --- Prompt cluster/namespace ---
if [[ -z "${CLUSTER:-}" ]]; then
	CLUSTER=$(choose_option "Choose cluster:" "${CLUSTERS[@]}")
fi

if [[ -z "${NAMESPACE:-}" ]]; then
	NAMESPACE=$(choose_option "Choose namespace:" "${NAMESPACES[@]}")
fi

# --- Get available ReplicationSources ---
get_replication_sources() {
	local namespace="$1"
	kubectl get replicationsource -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo ""
}

# --- Filter sources by pattern: ${CLUSTER}-${BACKUP_NAME}-${WHAT} ---
filter_backup_sources() {
	local namespace="$1"
	local cluster="$2"
	local backup_name="$3"
	shift 3
	local filters=("$@")

	local all_sources
	all_sources=$(get_replication_sources "$namespace")

	if [[ -z "$all_sources" ]]; then
		echo ""
		return
	fi

	# Filter by cluster-backupname pattern
	local pattern="${cluster}-${backup_name}-"
	local filtered_sources
	filtered_sources=$(echo "$all_sources" | grep "^${pattern}" || true)

	if [[ -z "$filtered_sources" ]]; then
		echo ""
		return
	fi

	# Apply additional filters if not just "*"
	if [[ ${#filters[@]} -eq 1 && "${filters[0]}" == "*" ]]; then
		echo "$filtered_sources"
		return
	fi

	# Apply each filter
	local result=""
	for filter in "${filters[@]}"; do
		local matched
		matched=$(echo "$filtered_sources" | grep "${filter}" || true)
		if [[ -n "$matched" ]]; then
			result="${result}${matched}"$'\n'
		fi
	done

	echo "$result" | sed '/^$/d'
}

# --- Trigger manual backup ---
trigger_backup() {
	local source_name="$1"
	local namespace="$2"
	local trigger_id="manual-$(date +%Y%m%d-%H%M%S)"

	section "Triggering backup for $source_name..." >&2
	info "Trigger ID: $trigger_id" >&2

	kubectl patch replicationsource "$source_name" -n "$namespace" \
		--type merge \
		-p "{\"spec\":{\"trigger\":{\"manual\":\"$trigger_id\"}}}" >&2

	if [[ $? -eq 0 ]]; then
		success "Backup triggered successfully" >&2
		echo "$trigger_id"
	else
		error "Failed to trigger backup" >&2
		return 1
	fi
}

# --- Wait for backup to complete ---
wait_for_backup() {
	local source_name="$1"
	local namespace="$2"
	local trigger_id="$3"
	local timeout="${4:-600}" # Default 10 minutes

	info "Waiting for backup $source_name to complete..."
	info "  Trigger ID: $trigger_id"

	# Give the backup a moment to start
	info "Waiting for backup to initialize..."
	sleep 10

	# Spinner frames
	local FRAME=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
	local i=0
	local start_time=$(date +%s)

	while true; do
		local now=$(date +%s)
		local elapsed=$((now - start_time))

		# Check timeout
		if [[ $elapsed -gt $timeout ]]; then
			echo ""
			error "Backup timed out after ${timeout}s"
			return 1
		fi

		# Check Synchronizing condition status
		local sync_status sync_reason
		sync_status=$(kubectl get replicationsource "$source_name" -n "$namespace" \
			-o jsonpath='{.status.conditions[?(@.type=="Synchronizing")].status}' 2>/dev/null || echo "")
		sync_reason=$(kubectl get replicationsource "$source_name" -n "$namespace" \
			-o jsonpath='{.status.conditions[?(@.type=="Synchronizing")].reason}' 2>/dev/null || echo "")

		# If Synchronizing is not True, the backup has finished (or failed)
		if [[ "$sync_status" != "True" ]]; then
			# Get last manual sync to verify
			local last_sync
			last_sync=$(kubectl get replicationsource "$source_name" -n "$namespace" \
				-o jsonpath='{.status.lastManualSync}' 2>/dev/null || echo "")

			if [[ "$last_sync" == "$trigger_id" ]]; then
				# Get duration and time
				local duration last_sync_time
				duration=$(kubectl get replicationsource "$source_name" -n "$namespace" \
					-o jsonpath='{.status.lastSyncDuration}' 2>/dev/null || echo "")
				last_sync_time=$(kubectl get replicationsource "$source_name" -n "$namespace" \
					-o jsonpath='{.status.lastSyncTime}' 2>/dev/null || echo "")

				echo ""
				success "Backup completed successfully!"
				info "Last sync time: $last_sync_time"
				info "Duration: $duration"
				return 0
			else
				echo ""
				error "Backup finished but lastManualSync doesn't match!"
				error "Expected: $trigger_id"
				error "Got: $last_sync"
				error "Reason: $sync_reason"
				return 1
			fi
		fi

		# Spinner with elapsed time and status
		printf "\r%s Waiting for backup... Elapsed: %02d:%02d (Status: %s)  " \
			"${FRAME[i]}" $((elapsed / 60)) $((elapsed % 60)) "$sync_reason"
		i=$(((i + 1) % ${#FRAME[@]}))

		sleep 0.5
	done
}

# --- Show backup status ---
show_backup_status() {
	local source_name="$1"
	local namespace="$2"

	info "Backup status for $source_name:"
	kubectl get replicationsource "$source_name" -n "$namespace" \
		-o custom-columns=NAME:.metadata.name,SOURCE:.spec.sourcePVC,LAST\ SYNC:.status.lastSyncTime,DURATION:.status.lastSyncDuration,NEXT\ SYNC:.status.nextSyncTime
}

# --- Main execution logic ---
section "Finding available ReplicationSources for ${BACKUP_NAME}..."
SOURCES=$(filter_backup_sources "$NAMESPACE" "$CLUSTER" "$BACKUP_NAME" "${FILTERS[@]}")

if [[ -z "$SOURCES" ]]; then
	error "No ReplicationSources found matching pattern: ${CLUSTER}-${BACKUP_NAME}-*"
	exit 1
fi

# Convert to array
readarray -t SOURCE_ARRAY <<<"$SOURCES"

# Add "all" option as default
SOURCE_ARRAY=("all" "${SOURCE_ARRAY[@]}")

# Choose source
SELECTED_SOURCE=$(choose_option "Choose backup source:" "${SOURCE_ARRAY[@]}")

# --- Show summary and confirm ---
section "Backup Summary"
info "Cluster:          ${CLUSTER}"
info "Namespace:        ${NAMESPACE}"
info "Backup name:      ${BACKUP_NAME}"
info "Selected source:  ${SELECTED_SOURCE}"
echo ""

if [[ "$(ask_yes_no "Proceed with backup?" "y")" != "y" ]]; then
	error "Backup cancelled by user."
	exit 1
fi

# --- Execute backups ---
if [[ "$SELECTED_SOURCE" == "all" ]]; then
	section "Triggering all ${BACKUP_NAME} backups..."

	TRIGGER_IDS=()
	BACKUP_SOURCES=()

	# Trigger all backups
	for source in "${SOURCE_ARRAY[@]}"; do
		if [[ "$source" == "all" ]]; then
			continue
		fi

		info "Trigger '$source' backup ..."
		TRIGGER_ID=$(trigger_backup "$source" "$NAMESPACE")
		if [[ $? -eq 0 ]]; then
			TRIGGER_IDS+=("$TRIGGER_ID")
			BACKUP_SOURCES+=("$source")
		fi
	done

	# Wait for all backups
	section "Waiting for all backups to complete..."
	echo ""
	FAILED=0
	for idx in "${!BACKUP_SOURCES[@]}"; do
		source="${BACKUP_SOURCES[$idx]}"
		trigger_id="${TRIGGER_IDS[$idx]}"

		info "Checking backup: $source"
		wait_for_backup "$source" "$NAMESPACE" "$trigger_id"
		if [[ $? -ne 0 ]]; then
			FAILED=$((FAILED + 1))
		fi
	done

	if [[ $FAILED -eq 0 ]]; then
		success "All backups completed successfully!"
	else
		error "$FAILED backup(s) failed"
		exit 1
	fi
else
	# Single backup
	TRIGGER_ID=$(trigger_backup "$SELECTED_SOURCE" "$NAMESPACE")
	if [[ $? -eq 0 ]]; then
		wait_for_backup "$SELECTED_SOURCE" "$NAMESPACE" "$TRIGGER_ID"
		if [[ $? -eq 0 ]]; then
			section "Final status:"
			show_backup_status "$SELECTED_SOURCE" "$NAMESPACE"
			success "Backup completed successfully!"
		else
			error "Backup failed"
			exit 1
		fi
	else
		error "Failed to trigger backup"
		exit 1
	fi
fi
