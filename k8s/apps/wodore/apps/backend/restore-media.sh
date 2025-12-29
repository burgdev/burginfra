#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"

# Simple restore script for Wodore backend media files
BACKUP_DIR="/home/tobias/git/wodore/wodore-server/scripts/restore/extract/backend/media"
PVC_NAME="wd-backend-media-v1"
NAMESPACE="production"
RESTORE_POD_NAME="wd-backend-media-restore"

echo "====================================="
echo "Wodore Backend Media Restore"
echo "====================================="
echo ""
echo "Backup directory: $BACKUP_DIR"
echo "Target PVC:       $PVC_NAME"
echo "Namespace:        $NAMESPACE"
echo ""

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
	echo "ERROR: Backup directory not found: $BACKUP_DIR"
	exit 1
fi

# Check if PVC exists
if ! kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
	echo "ERROR: PVC $PVC_NAME not found in namespace $NAMESPACE"
	exit 1
fi

# Count files to restore
FILE_COUNT=$(find "$BACKUP_DIR" -type f | wc -l)
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

echo "Files to restore: $FILE_COUNT"
echo "Backup size:      $BACKUP_SIZE"
echo ""

# Confirm
read -p "Are you sure you want to restore? This will overwrite existing media files. [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo "Aborted."
	exit 1
fi

echo ""
echo "Creating restore pod with PVC mounted..."

# Clean up any existing restore pod
kubectl delete pod "$RESTORE_POD_NAME" -n "$NAMESPACE" --wait=false 2>/dev/null || true
sleep 2

# Create restore pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $RESTORE_POD_NAME
  namespace: $NAMESPACE
spec:
  containers:
  - name: restore
    image: alpine:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: media
      mountPath: /media
  volumes:
  - name: media
    persistentVolumeClaim:
      claimName: $PVC_NAME
  restartPolicy: Never
EOF

echo "Waiting for restore pod to be ready..."
kubectl wait --for=condition=ready pod/"$RESTORE_POD_NAME" -n "$NAMESPACE" --timeout=60s

echo ""
echo "Deleting existing media files..."
kubectl exec -n "$NAMESPACE" "$RESTORE_POD_NAME" -- sh -c "rm -rf /media/*"

echo ""
echo "Copying media files to PVC..."
echo "This may take a while depending on the number and size of files..."

# Copy contents of the backup directory (not the directory itself)
# kubectl cp copies the directory, so we copy to /media and then move contents
kubectl cp "$BACKUP_DIR" "$NAMESPACE/$RESTORE_POD_NAME:/tmp/media-restore" --retries=3

COPY_EXIT_CODE=$?

if [ $COPY_EXIT_CODE -eq 0 ]; then
	echo "Moving files to correct location..."
	kubectl exec -n "$NAMESPACE" "$RESTORE_POD_NAME" -- sh -c "cp -r /tmp/media-restore/* /media/ && rm -rf /tmp/media-restore"
fi

# Verify the copy
if [ $COPY_EXIT_CODE -eq 0 ]; then
	echo ""
	echo "Verifying copied files..."
	COPIED_COUNT=$(kubectl exec -n "$NAMESPACE" "$RESTORE_POD_NAME" -- sh -c "find /media -type f 2>/dev/null | wc -l" || echo "0")
	echo "Files in PVC: $COPIED_COUNT"

	# Fix permissions (set to 1001:1001 as per deployment.yaml)
	echo ""
	echo "Setting correct ownership (1001:1001)..."
	kubectl exec -n "$NAMESPACE" "$RESTORE_POD_NAME" -- sh -c "chown -R 1001:1001 /media"
fi

# Cleanup restore pod
echo ""
echo "Cleaning up restore pod..."
kubectl delete pod "$RESTORE_POD_NAME" -n "$NAMESPACE" --wait=false || true

if [ $COPY_EXIT_CODE -eq 0 ]; then
	echo ""
	echo "====================================="
	echo "Media files restored successfully!"
	echo "====================================="
	echo ""
	echo "Next steps:"
	echo "1. Verify media files are accessible"
	echo "2. Restart the backend deployment to ensure proper access:"
	echo "   kubectl rollout restart deployment/wd-backend -n $NAMESPACE"
else
	echo ""
	echo "ERROR: Media restore failed"
	exit 1
fi
