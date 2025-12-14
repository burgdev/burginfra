#!/usr/bin/env bash
# Usage: source restore_base.sh
# Expects: $TEMPLATE_FILE, $CLUSTERS and $NAMESPACES to be set

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

if [ -z "${CLUSTERS+x}" ] || [ "${#CLUSTERS[@]}" -eq 0 ]; then
	CLUSTERS=("local" "burginfra")
fi
if [ -z "${NAMESPACES+x}" ] || [ "${#NAMESPACES[@]}" -eq 0 ]; then
	NAMESPACES=("staging" "production" "burginfra-staging" "burginfra-system")
fi
TEMPLATE_FILE=${TEMPLATE_FILE:-"configs/restore_volsync.template.yaml"}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

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

	printf "${YELLOW}%s (${def_upper}/${def_lower}): ${RESET}" "$prompt" >&2
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

	printf "\n${CYAN}%s${RESET}\n" "$prompt" >&2
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

	printf "${YELLOW}Enter restore date and time (default: %s):${RESET} " "$current_datetime" >&2
	read -r input_datetime </dev/tty

	# Use current datetime if empty
	if [[ -z "$input_datetime" ]]; then
		input_datetime="$current_datetime"
	fi

	# Validate format
	if [[ ! "$input_datetime" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
		echo -e "${RED}Invalid format. Expected YYYY-MM-DD HH:MM${RESET}" >&2
		exit 1
	fi

	# Convert to RFC-3339 format with timezone
	# Replace space with T, add :00 for seconds, and append timezone
	RESTORE_AS_OF=$(echo "$input_datetime" | sed 's/ /T/')":00${current_tz}"

	echo -e "${GREEN}Restore as of: ${RESTORE_AS_OF}${RESET}" >&2
fi

# --- Export vars ---
export CLUSTER NAMESPACE SRC_CLUSTER SRC_NAMESPACE TIMESTAMP RESTORE_AS_OF

# --- Generate YAML into variable ---
RESTORE_YAML=$(envsubst <"$TEMPLATE_FILE")

# --- Helper function to wait for restore (auto namespace and metadata.name) ---
wait_for_restore() {
	# Extract metadata.name from YAML
	local rd_name
	rd_name=$(echo "$RESTORE_YAML" | grep "^\s*name:" | head -n1 | awk '{print $2}')
	if [[ -z "$rd_name" ]]; then
		echo -e "${RED}Failed to determine metadata.name from RESTORE_YAML${RESET}"
		return 1
	fi

	# Extract manual trigger name from YAML
	local trigger_name
	trigger_name=$(echo "$RESTORE_YAML" | grep "^\s*manual:" | head -n1 | awk '{print $2}')
	if [[ -z "$trigger_name" ]]; then
		echo -e "${RED}Failed to determine manual trigger name from RESTORE_YAML${RESET}"
		return 1
	fi

	echo -e "${BLUE}Waiting for ReplicationDestination $rd_name in namespace $NAMESPACE...${RESET}"
	echo " → Expected manual trigger: $trigger_name"

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
				echo -e "\n${GREEN}Restore completed successfully!${RESET}"
				break
			else
				echo -e "\n${RED}Restore failed! Logs:${RESET}"
				echo -e "$logs"
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
