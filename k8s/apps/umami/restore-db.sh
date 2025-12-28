#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"

# Simple restore script for Umami database
BACKUP_FILE="/home/tobias/git/wodore/wodore-server/scripts/restore/extract/umami/umami-db/umami-db.postgres.dump"
POD="umami-postgres-1"
NAMESPACE="production"

echo "====================================="
echo "Umami Database Restore"
echo "====================================="
echo ""
echo "Backup file: $BACKUP_FILE"
echo "Target pod:  $POD"
echo "Namespace:   $NAMESPACE"
echo ""

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
	echo "ERROR: Backup file not found: $BACKUP_FILE"
	exit 1
fi

# Check if pod exists
if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
	echo "ERROR: Pod $POD not found in namespace $NAMESPACE"
	exit 1
fi

# Confirm
read -p "Are you sure you want to restore? This will overwrite the current database. [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo "Aborted."
	exit 1
fi

echo ""
echo "Terminating existing database connections..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
	psql -U postgres -d postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = 'umami' AND pid <> pg_backend_pid();" 2>/dev/null || true

sleep 2

echo "Restoring database (this is a binary dump, using pg_restore)..."
cat "$BACKUP_FILE" | kubectl exec -i -n "$NAMESPACE" "$POD" -- \
	pg_restore \
	--username=postgres \
	--dbname=umami \
	--clean \
	--if-exists \
	--no-owner \
	--no-acl \
	--verbose

if [ $? -eq 0 ]; then
	echo ""
	echo "====================================="
	echo "Database restored successfully!"
	echo "====================================="
else
	echo ""
	echo "ERROR: Database restore failed"
	exit 1
fi
