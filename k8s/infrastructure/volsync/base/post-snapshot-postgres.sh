#!/bin/bash
# Note: Continue even if validation fails to send error heartbeat
set +e

# ============================================================================
# Generic PostgreSQL Post-Snapshot Validation Script for CloudNativePG
# ============================================================================
# This script validates the backup and sends optional heartbeat notifications.
#
# Usage:
#   sh /kopia-config/post-snapshot-postgres.sh [config_file]
#
# Parameters:
#   config_file: Path to config file (default: /tmp/backup-config.env)
#
# Required configuration (loaded from config file):
# - NAMESPACE: Kubernetes namespace
# - CNPG_CLUSTER_NAME: CloudNativePG cluster name
# - BACKUP_FILENAME: SQL dump filename
# - MIN_DUMP_SIZE: Minimum valid dump size in bytes
# - MAX_DUMP_AGE: Maximum age in seconds
# - HEARTBEAT_URL: Optional heartbeat URL (leave empty to skip)
# - REPLICATION_SOURCE_NAME: VolSync ReplicationSource name
# ============================================================================

CONFIG_FILE="$${1:-/tmp/backup-config.env}"

# Load configuration from pre-snapshot
if [ ! -f "$CONFIG_FILE" ]; then
	echo "ERROR: Configuration file $CONFIG_FILE not found"
	exit 1
fi
. "$CONFIG_FILE"

echo "==> [$(date)] Post-backup validation starting for $CNPG_CLUSTER_NAME..."

# Source kubectl (adds kubectl to PATH)
. /kopia-config/source-kubectl.sh
BACKUP_FILE="/data/$BACKUP_FILENAME"

VALIDATION_FAILED=0
ERROR_MSG=""

# Validate SQL dump exists
if [ ! -f "$BACKUP_FILE" ]; then
	echo "ERROR: Backup file not found at $BACKUP_FILE"
	ERROR_MSG="Backup file not found"
	VALIDATION_FAILED=1
fi

# Validate dump file size
if [ $VALIDATION_FAILED -eq 0 ]; then
	DUMP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || echo 0)
	if [ "$DUMP_SIZE" -lt $MIN_DUMP_SIZE ]; then
		echo "ERROR: Backup file too small ($DUMP_SIZE bytes)"
		ERROR_MSG="Backup file too small: $DUMP_SIZE bytes"
		VALIDATION_FAILED=1
	else
		echo "==> Backup file size: $(numfmt --to=iec-i --suffix=B $DUMP_SIZE)"
	fi
fi

# Validate dump file age (created during this backup run)
if [ $VALIDATION_FAILED -eq 0 ]; then
	CURRENT_TIME=$(date +%s)
	DUMP_MTIME=$(stat -c%Y "$BACKUP_FILE" 2>/dev/null || echo 0)
	DUMP_AGE=$((CURRENT_TIME - DUMP_MTIME))

	if [ $DUMP_AGE -gt $MAX_DUMP_AGE ]; then
		echo "ERROR: Backup file is too old ($DUMP_AGE seconds)"
		ERROR_MSG="Backup file is stale: $DUMP_AGE seconds old"
		VALIDATION_FAILED=1
	else
		echo "==> Backup file age: $${DUMP_AGE}s (recent)"
	fi
fi

# Validate VolSync ReplicationSource status
if [ $VALIDATION_FAILED -eq 0 ]; then
	echo "==> Checking VolSync backup status..."
	REPLICATION_STATUS=$(kubectl get replicationsource "$REPLICATION_SOURCE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.lastSyncTime}' 2>/dev/null || echo "")

	if [ -z "$REPLICATION_STATUS" ]; then
		echo "WARNING: Could not retrieve ReplicationSource status"
		# Don't fail on this - might be transient
	else
		echo "==> Last sync time: $REPLICATION_STATUS"
	fi
fi

# Send heartbeat using helper script
sh /kopia-config/send-heartbeat.sh "$HEARTBEAT_URL" "$VALIDATION_FAILED"

# Log backup result to data volume
if [ $VALIDATION_FAILED -eq 0 ]; then
	echo "[$(date)] Backup completed successfully - size: $(numfmt --to=iec-i --suffix=B $DUMP_SIZE)" >>/data/backup.log
else
	echo "[$(date)] Backup FAILED - $ERROR_MSG" >>/data/backup.log
fi

# Cleanup old logs (keep last 100 lines)
if [ -f /data/backup.log ]; then
	tail -n 100 /data/backup.log >/data/backup.log.tmp
	mv /data/backup.log.tmp /data/backup.log
fi

echo "==> Post-backup complete"
exit 0 # Always exit 0 to not fail the VolSync job
