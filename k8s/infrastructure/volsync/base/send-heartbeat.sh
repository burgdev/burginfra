#!/bin/sh

# ============================================================================
# Heartbeat Sender Script
# ============================================================================
# Sends heartbeat notifications to monitoring services (e.g., Betterstack).
#
# Usage:
#   sh /kopia-config/send-heartbeat.sh <heartbeat_url> [external_check_failed]
#
# Parameters:
#   heartbeat_url: URL to send heartbeat to (required, use "" to skip)
#   external_check_failed: 0 = success, 1 = external validation failed (default: 0)
#
# Exit codes:
#   0: Always exits 0 (never fails the calling script)
#
# Examples:
#   # Send success heartbeat
#   sh /kopia-config/send-heartbeat.sh "https://heartbeat.example.com/backup-id"
#
#   # Send failure heartbeat (external validation failed)
#   sh /kopia-config/send-heartbeat.sh "https://heartbeat.example.com/backup-id" 1
#
#   # Skip heartbeat (empty URL)
#   sh /kopia-config/send-heartbeat.sh ""
# ============================================================================

HEARTBEAT_URL="$1"
EXTERNAL_CHECK_FAILED="$${2:-0}"

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
