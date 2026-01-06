#!/bin/bash
set -e

# CloudNativePG Snapshot Restore Script for Zitadel PostgreSQL
# This script helps restore a Zitadel PostgreSQL database from a volume snapshot

NAMESPACE="burginfra-system"
CLUSTER_NAME="zitadel-postgres"
KUBECONFIG="${KUBECONFIG:-~/.kube/config-localhost}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CloudNativePG Snapshot Restore Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check if kubectl is available
if ! command -v kubectl &>/dev/null; then
	echo -e "${RED}Error: kubectl not found${NC}"
	exit 1
fi

# Set kubeconfig
export KUBECONFIG

# Function to list snapshots
list_snapshots() {
	echo -e "${BLUE}Fetching available volume snapshots...${NC}"
	SNAPSHOTS=$(kubectl get volumesnapshot -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.creationTime}{"\t"}{.status.readyToUse}{"\n"}{end}' 2>/dev/null)

	if [ -z "$SNAPSHOTS" ]; then
		echo -e "${RED}No volume snapshots found in namespace: $NAMESPACE${NC}"
		exit 1
	fi

	echo -e "${GREEN}Available snapshots:${NC}"
	echo
	printf "%-5s %-60s %-30s %-10s\n" "No." "Snapshot Name" "Created" "Ready"
	echo "-------------------------------------------------------------------------------------------------------------------------------------------------"

	local i=1
	while IFS=$'\t' read -r name created ready; do
		SNAPSHOT_ARRAY[$i]="$name"
		printf "%-5s %-60s %-30s %-10s\n" "$i" "$name" "$created" "$ready"
		((i++))
	done <<<"$SNAPSHOTS"

	SNAPSHOT_COUNT=$((i - 1))
	echo
}

# Function to select snapshot
select_snapshot() {
	while true; do
		read -p "Enter snapshot number to restore (1-$SNAPSHOT_COUNT): " SNAPSHOT_NUM

		if [[ "$SNAPSHOT_NUM" =~ ^[0-9]+$ ]] && [ "$SNAPSHOT_NUM" -ge 1 ] && [ "$SNAPSHOT_NUM" -le "$SNAPSHOT_COUNT" ]; then
			SELECTED_SNAPSHOT="${SNAPSHOT_ARRAY[$SNAPSHOT_NUM]}"
			echo -e "${GREEN}Selected snapshot: $SELECTED_SNAPSHOT${NC}"
			break
		else
			echo -e "${RED}Invalid selection. Please enter a number between 1 and $SNAPSHOT_COUNT${NC}"
		fi
	done
}

# Function to select restore mode
select_restore_mode() {
	echo
	echo -e "${YELLOW}Select restore mode:${NC}"
	echo "1) Create new restore cluster (safe, non-destructive)"
	echo "2) Overwrite existing cluster (DESTRUCTIVE - replaces current database)"
	echo

	while true; do
		read -p "Enter choice (1 or 2): " RESTORE_MODE

		case $RESTORE_MODE in
		1)
			RESTORE_TYPE="new"
			RESTORE_CLUSTER_NAME="${CLUSTER_NAME}-restored"
			echo -e "${GREEN}Will create new cluster: $RESTORE_CLUSTER_NAME${NC}"
			break
			;;
		2)
			RESTORE_TYPE="overwrite"
			RESTORE_CLUSTER_NAME="$CLUSTER_NAME"
			echo -e "${RED}⚠️  WARNING: This will DELETE the existing cluster and restore from snapshot${NC}"
			echo -e "${RED}⚠️  All data after snapshot time will be LOST${NC}"
			echo
			read -p "Type 'yes' to confirm: " CONFIRM
			if [ "$CONFIRM" = "yes" ]; then
				echo -e "${YELLOW}Overwrite mode confirmed${NC}"
				break
			else
				echo -e "${RED}Overwrite cancelled. Exiting.${NC}"
				exit 0
			fi
			;;
		*)
			echo -e "${RED}Invalid choice. Please enter 1 or 2${NC}"
			;;
		esac
	done
}

# Function to create restore manifest
create_restore_manifest() {
	RESTORE_MANIFEST="/tmp/restore-${RESTORE_CLUSTER_NAME}.yaml"

	cat >"$RESTORE_MANIFEST" <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${RESTORE_CLUSTER_NAME}
  namespace: ${NAMESPACE}
spec:
  instances: 1

  storage:
    storageClass: fast-local-data-v3
    size: 5Gi

  # Bootstrap from volume snapshot
  bootstrap:
    recovery:
      volumeSnapshots:
        storage:
          name: ${SELECTED_SNAPSHOT}
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io

      # Restore to exact snapshot point (no WAL replay)
      recoveryTarget:
        targetImmediate: true

  # PostgreSQL Configuration (from original cluster)
  postgresql:
    parameters:
      max_connections: "50"
      shared_buffers: "128MB"
      effective_cache_size: "256MB"
      maintenance_work_mem: "32MB"
      work_mem: "2MB"
      wal_buffers: "4MB"
      min_wal_size: "256MB"
      max_wal_size: "1GB"
      checkpoint_completion_target: "0.9"
      default_statistics_target: "100"
      random_page_cost: "1.1"
      effective_io_concurrency: "200"
      log_checkpoints: "on"
      log_connections: "off"
      log_disconnections: "off"
      log_lock_waits: "on"

  # Resource limits
  resources:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "512Mi"
      cpu: "500m"

  enableSuperuserAccess: true
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  minSyncReplicas: 0
  maxSyncReplicas: 0
EOF

	echo -e "${GREEN}Created restore manifest: $RESTORE_MANIFEST${NC}"
}

# Function to perform restore
perform_restore() {
	echo
	echo -e "${BLUE}========================================${NC}"
	echo -e "${BLUE}Starting Restore Process${NC}"
	echo -e "${BLUE}========================================${NC}"

	if [ "$RESTORE_TYPE" = "overwrite" ]; then
		echo -e "${YELLOW}Step 1: Scaling down Zitadel application...${NC}"
		kubectl scale deployment zitadel -n "$NAMESPACE" --replicas=0 2>/dev/null || echo "Note: Zitadel deployment not found or already scaled down"
		sleep 5

		echo -e "${YELLOW}Step 2: Deleting existing cluster...${NC}"
		kubectl delete cluster "$CLUSTER_NAME" -n "$NAMESPACE" --wait=true
		echo -e "${GREEN}Cluster deleted${NC}"
		sleep 5
	fi

	echo -e "${YELLOW}Step 3: Creating restored cluster...${NC}"
	kubectl apply -f "$RESTORE_MANIFEST"

	echo
	echo -e "${BLUE}Waiting for cluster to be ready...${NC}"
	echo -e "${YELLOW}This may take several minutes...${NC}"
	echo

	# Wait for cluster to be ready
	kubectl wait --for=condition=Ready cluster/"$RESTORE_CLUSTER_NAME" -n "$NAMESPACE" --timeout=600s || {
		echo -e "${RED}Cluster did not become ready in time. Check status with:${NC}"
		echo "kubectl get cluster $RESTORE_CLUSTER_NAME -n $NAMESPACE"
		echo "kubectl describe cluster $RESTORE_CLUSTER_NAME -n $NAMESPACE"
		exit 1
	}

	echo -e "${GREEN}✓ Cluster is ready!${NC}"

	if [ "$RESTORE_TYPE" = "overwrite" ]; then
		echo
		echo -e "${YELLOW}Step 4: Scaling Zitadel application back up...${NC}"
		kubectl scale deployment zitadel -n "$NAMESPACE" --replicas=1 2>/dev/null || echo "Note: Zitadel deployment not found"
	fi
}

# Function to show post-restore info
show_post_restore_info() {
	echo
	echo -e "${GREEN}========================================${NC}"
	echo -e "${GREEN}Restore Complete!${NC}"
	echo -e "${GREEN}========================================${NC}"
	echo
	echo -e "${BLUE}Cluster Details:${NC}"
	kubectl get cluster "$RESTORE_CLUSTER_NAME" -n "$NAMESPACE"
	echo
	echo -e "${BLUE}Pod Status:${NC}"
	kubectl get pods -n "$NAMESPACE" | grep "$RESTORE_CLUSTER_NAME"
	echo

	echo -e "${BLUE}Useful Commands:${NC}"
	echo "# View cluster status:"
	echo "kubectl describe cluster $RESTORE_CLUSTER_NAME -n $NAMESPACE"
	echo
	echo "# View logs:"
	echo "kubectl logs -n $NAMESPACE ${RESTORE_CLUSTER_NAME}-1 -c postgres --tail=50"
	echo
	echo "# Connect to database:"
	echo "kubectl exec -it ${RESTORE_CLUSTER_NAME}-1 -n $NAMESPACE -- psql -U postgres -d zitadel"
	echo

	if [ "$RESTORE_TYPE" = "new" ]; then
		echo -e "${YELLOW}Note: This is a NEW cluster running alongside the original.${NC}"
		echo -e "${YELLOW}Original cluster '$CLUSTER_NAME' is still running.${NC}"
		echo
		echo -e "${BLUE}To switch Zitadel to use the restored database:${NC}"
		echo "1. Update Zitadel configuration to point to: ${RESTORE_CLUSTER_NAME}-rw"
		echo "2. Restart Zitadel pods"
		echo "3. Delete old cluster when satisfied: kubectl delete cluster $CLUSTER_NAME -n $NAMESPACE"
	else
		echo -e "${GREEN}The cluster has been restored and Zitadel should now be using the restored database.${NC}"
	fi

	echo
	echo -e "${GREEN}Restore manifest saved at: $RESTORE_MANIFEST${NC}"
}

# Main execution
declare -A SNAPSHOT_ARRAY

list_snapshots
select_snapshot
select_restore_mode
create_restore_manifest

echo
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Restore Summary${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "Snapshot:      ${GREEN}$SELECTED_SNAPSHOT${NC}"
echo -e "Restore Mode:  ${GREEN}$RESTORE_TYPE${NC}"
echo -e "Cluster Name:  ${GREEN}$RESTORE_CLUSTER_NAME${NC}"
echo -e "Namespace:     ${GREEN}$NAMESPACE${NC}"
echo -e "${YELLOW}========================================${NC}"
echo

read -p "Proceed with restore? (yes/no): " PROCEED
if [ "$PROCEED" != "yes" ]; then
	echo -e "${RED}Restore cancelled${NC}"
	rm -f "$RESTORE_MANIFEST"
	exit 0
fi

perform_restore
show_post_restore_info

echo -e "${GREEN}Done!${NC}"
