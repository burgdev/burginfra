#!/bin/bash

# Local test wrapper for download-all.sh
#
# This script converts the Flux-compatible $${VAR} syntax to standard ${VAR} syntax
# for local testing. The download-all.sh script uses $${VAR} to prevent Flux from
# substituting variables when creating the ConfigMap in Kubernetes.
#
# Usage:
#   ./test-download-local.sh
#
# Set environment variables before running to customize behavior:
#   CUSTOM_DIR=/tmp/valhalla ./test-download-local.sh
#   OSM_URLS=https://example.com/map.osm.pbf ./test-download-local.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/download-all.sh"

if [ ! -f "$SOURCE_SCRIPT" ]; then
	echo "ERROR: Cannot find download-all.sh at: $SOURCE_SCRIPT"
	exit 1
fi

echo "=== Local Test Wrapper ==="
echo "Converting Flux syntax (\$\${VAR}) to bash syntax (\${VAR})..."
echo ""

# Set defaults if not provided (use absolute paths to avoid issues with cd)
export CUSTOM_DIR="${CUSTOM_DIR:-$(pwd)/custom_files}"
export GTFS_DIR="${GTFS_DIR:-$(pwd)/gtfs_feeds}"

# Create directories if they don't exist
echo "Creating test directories:"
echo "  - $CUSTOM_DIR"
echo "  - $GTFS_DIR"
mkdir -p "$CUSTOM_DIR"
mkdir -p "$GTFS_DIR"
echo ""

# Convert $${VAR} to ${VAR}
# Then execute the modified script
sed 's/\$\${\([^}]*\)}/${\1}/g' "$SOURCE_SCRIPT" | bash

echo ""
echo "=== Local test complete ==="
