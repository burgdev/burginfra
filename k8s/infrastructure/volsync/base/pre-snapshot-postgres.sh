#!/bin/bash
set -e

# ============================================================================
# Generic PostgreSQL Pre-Snapshot Backup Script for CloudNativePG
# ============================================================================
# This script creates a SQL dump and performs a PostgreSQL CHECKPOINT before
# the VolSync snapshot to ensure backup consistency.
#
# Usage:
#   bash /kopia-config/pre-snapshot-postgres.sh -c <config_file>
#
# Parameters:
#   -c config_file: Path to config file (default: /tmp/backup-config.env)
#
# Required configuration (loaded from config file):
# - NAMESPACE: Kubernetes namespace
# - CNPG_CLUSTER_NAME: CloudNativePG cluster name
# - DB_NAME: Database name to dump
# - DB_USER: PostgreSQL user (default: postgres)
# - BACKUP_FILENAME: SQL dump filename
# - DUMP_TIMEOUT: Dump timeout in seconds
# - MIN_DUMP_SIZE: Minimum valid dump size in bytes
# - PG_DUMP_COMMAND: pg_dump or pg_dumpall
# - PG_DUMP_ARGS: Additional pg_dump arguments
# ============================================================================

# Parse parameters
CONFIG_FILE="/tmp/backup-config.env"
while getopts "c:" opt; do
	case $opt in
	c) CONFIG_FILE="$OPTARG" ;;
	*)
		echo "ERROR: Invalid option" >&2
		exit 1
		;;
	esac
done

# Load configuration from caller
if [ ! -f "$CONFIG_FILE" ]; then
	echo "ERROR: Configuration file $CONFIG_FILE not found"
	echo "This script must be called after creating the config file"
	exit 1
fi
. "$CONFIG_FILE"

echo "==> [$(date)] PostgreSQL backup starting for $CNPG_CLUSTER_NAME..."

# Source kubectl (adds kubectl to PATH)
. /kopia-config/source-kubectl.sh

BACKUP_FILE="/data/$BACKUP_FILENAME"

# Find postgres pod dynamically
echo "==> Finding postgres pod..."
POSTGRES_POD=$(kubectl get pods -n "$NAMESPACE" -l cnpg.io/cluster=$${CNPG_CLUSTER_NAME} -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POSTGRES_POD" ]; then
	echo "ERROR: Could not find pod for cluster: $${CNPG_CLUSTER_NAME}"
	exit 1
fi
echo "==> Found postgres pod: $POSTGRES_POD"
echo "==> Database: $DB_NAME, User: $DB_USER"

# Delete old backup file if it exists
if [ -f "$BACKUP_FILE" ]; then
	echo "==> Removing old backup file..."
	rm -f "$BACKUP_FILE"
fi

# Create SQL dump inside postgres container (using PGDATA env var for path)
# Use superuser with Unix socket (no password needed, peer auth)
echo "==> Creating SQL dump with $PG_DUMP_COMMAND (timeout: $${DUMP_TIMEOUT}s)..."
DUMP_START=$(date +%s)

# Build dump command based on PG_DUMP_COMMAND
if [ "$PG_DUMP_COMMAND" = "pg_dumpall" ]; then
	# pg_dumpall doesn't take -d flag, dumps all databases
	DUMP_CMD="$PG_DUMP_COMMAND -U \"$DB_USER\" $PG_DUMP_ARGS -f \"\$PGDATA/$BACKUP_FILENAME\""
else
	# pg_dump requires -d flag for database name
	DUMP_CMD="$PG_DUMP_COMMAND -U \"$DB_USER\" -d \"$DB_NAME\" $PG_DUMP_ARGS -f \"\$PGDATA/$BACKUP_FILENAME\""
fi

kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -c postgres -- \
	timeout $DUMP_TIMEOUT sh -c "$DUMP_CMD"

DUMP_EXIT_CODE=$?
DUMP_END=$(date +%s)
DUMP_DURATION=$((DUMP_END - DUMP_START))

if [ $DUMP_EXIT_CODE -ne 0 ]; then
	echo "ERROR: pg_dump failed with exit code $DUMP_EXIT_CODE"
	exit 1
fi
echo "==> SQL dump completed in $${DUMP_DURATION}s"

# Verify dump file was created
if [ ! -f "$BACKUP_FILE" ]; then
	echo "ERROR: Backup file was not created at $BACKUP_FILE"
	exit 1
fi

# Verify dump file size
DUMP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || echo 0)
if [ "$DUMP_SIZE" -lt $MIN_DUMP_SIZE ]; then
	echo "ERROR: Backup file too small ($DUMP_SIZE bytes < $MIN_DUMP_SIZE bytes), likely corrupted"
	exit 1
fi
echo "==> Backup file created: $(numfmt --to=iec-i --suffix=B $DUMP_SIZE)"

# Issue CHECKPOINT to ensure PostgreSQL buffers are flushed to disk
echo "==> Issuing PostgreSQL CHECKPOINT..."
kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -c postgres -- \
	psql -U postgres -c "CHECKPOINT;"
echo "==> CHECKPOINT completed - database is ready for snapshot"

# Store metadata for post-snapshot validation
echo "$DUMP_START" >/tmp/dump-timestamp
echo "$DUMP_SIZE" >/tmp/dump-size

echo "==> Pre-backup complete - ready for PVC snapshot"
