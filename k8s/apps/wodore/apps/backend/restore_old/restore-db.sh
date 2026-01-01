#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"

# Simple restore script for Wodore backend database
BACKUP_FILE="/home/tobias/git/wodore/wodore-server/scripts/restore/extract/backend/db/db.postgres.dump"
POD="wd-backend-postgres-1"
NAMESPACE="production"
DB_NAME="wodore"

echo "====================================="
echo "Wodore Backend Database Restore"
echo "====================================="
echo ""
echo "Backup file: $BACKUP_FILE"
echo "Target pod:  $POD"
echo "Namespace:   $NAMESPACE"
echo "Database:    $DB_NAME"
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
	psql -U postgres -d postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$DB_NAME' AND pid <> pg_backend_pid();" 2>/dev/null || true

sleep 2

echo "Dropping and recreating database..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
	psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"

kubectl exec -n "$NAMESPACE" "$POD" -- \
	psql -U postgres -d postgres -c "CREATE DATABASE $DB_NAME OWNER wodore;"

echo "Restoring database (this is a binary dump, using pg_restore)..."
echo "Note: The backup includes PostGIS extensions, so they will be restored automatically."
cat "$BACKUP_FILE" | kubectl exec -i -n "$NAMESPACE" "$POD" -- \
	pg_restore \
	--username=postgres \
	--dbname="$DB_NAME" \
	--no-owner \
	--no-acl \
	--verbose

RESTORE_EXIT_CODE=$?

if [ $RESTORE_EXIT_CODE -eq 0 ]; then
	echo ""
	echo "Transferring ownership to wodore user..."
	
	# Transfer table ownership
	kubectl exec -n "$NAMESPACE" "$POD" -- \
		psql -U postgres -d "$DB_NAME" -c "
			DO \$\$
			DECLARE
				r RECORD;
			BEGIN
				-- Transfer all tables
				FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
					EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' OWNER TO wodore';
				END LOOP;
				
				-- Transfer all sequences
				FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public' LOOP
					EXECUTE 'ALTER SEQUENCE public.' || quote_ident(r.sequence_name) || ' OWNER TO wodore';
				END LOOP;
				
				-- Transfer all views
				FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'public' LOOP
					EXECUTE 'ALTER VIEW public.' || quote_ident(r.viewname) || ' OWNER TO wodore';
				END LOOP;
			END
			\$\$;
		"
	
	# Transfer schema ownership
	kubectl exec -n "$NAMESPACE" "$POD" -- \
		psql -U postgres -d "$DB_NAME" -c "ALTER SCHEMA public OWNER TO wodore;"
	
	echo ""
	echo "====================================="
	echo "Database restored successfully!"
	echo "====================================="
	echo ""
	echo "Next steps:"
	echo "1. Verify database integrity"
	echo "2. Restart the backend deployment if needed:"
	echo "   kubectl rollout restart deployment/wd-backend -n $NAMESPACE"
else
	echo ""
	echo "ERROR: Database restore failed"
	exit 1
fi
