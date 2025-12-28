#!/bin/bash

# ============================================================================
# Heartbeat Sender Script
# ============================================================================
# Sends heartbeat notifications to monitoring services (e.g., Betterstack).
#
# Usage:
#   bash /kopia-config/send-heartbeat.sh -u <heartbeat_url> [-f]
#
# Parameters:
#   -u heartbeat_url: URL to send heartbeat to (required, use "" to skip)
#   -f: External validation failed flag (if present, sends failure heartbeat)
#
# Exit codes:
#   0: Always exits 0 (never fails the calling script)
#
# Examples:
#   # Send success heartbeat
#   bash /kopia-config/send-heartbeat.sh -u "https://heartbeat.example.com/backup-id"
#
#   # Send failure heartbeat
#   bash /kopia-config/send-heartbeat.sh -u "https://heartbeat.example.com/backup-id" -f
#
#   # Skip heartbeat (empty URL)
#   bash /kopia-config/send-heartbeat.sh -u ""
# ============================================================================

# Parse parameters
HEARTBEAT_URL=""
EXTERNAL_CHECK_FAILED=0

while getopts "u:f" opt; do
	case $opt in
	u) HEARTBEAT_URL="$OPTARG" ;;
	f) EXTERNAL_CHECK_FAILED=1 ;;
	*)
		echo "ERROR: Invalid option" >&2
		exit 0 # Never fail the calling script
		;;
	esac
done

# Skip if no heartbeat URL provided
if [ -z "$HEARTBEAT_URL" ]; then
	echo "==> No heartbeat URL provided, skipping heartbeat"
	exit 0
fi

# Determine success or failure
if [ "$EXTERNAL_CHECK_FAILED" = "0" ]; then
	# Success - send normal heartbeat
	echo "==> Sending success heartbeat to monitoring service..."
	if curl -fsS -m 10 "$HEARTBEAT_URL" >/dev/null 2>&1; then
		echo "==> Success heartbeat sent"
	else
		echo "WARNING: Failed to send success heartbeat (curl failed)"
	fi
else
	# Failure - send error heartbeat
	echo "==> Sending error heartbeat to monitoring service..."
	if curl -fsS -m 10 "$HEARTBEAT_URL/fail" >/dev/null 2>&1; then
		echo "==> Error heartbeat sent"
	else
		echo "ERROR: Failed to send error heartbeat (curl failed)"
	fi
fi

# Always exit 0 to not fail the calling script
exit 0
