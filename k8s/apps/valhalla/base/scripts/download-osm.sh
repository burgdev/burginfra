#!/bin/bash
set -e

# Source shared functions
source /scripts/job-functions.sh

# Check if we should skip based on init job mode
if ! handle_download_mode; then
	echo "Skipping OSM download based on mode"
	exit 0
fi

# If check failed and we're in check mode, we would have exited already
# So if we're here, we need to download
if check_osm_data; then
	echo "OSM data already exists, skipping download"
	exit 0
fi

echo "=== Starting OSM Download ==="

# Default to Switzerland OSM data if not set
if [ -z "$OSM_URLS" ]; then
	OSM_URLS="https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
fi
if [ -z "$CUSTOM_DIR" ]; then
	CUSTOM_DIR="/custom_files"
fi
if [ -z "$ERROR_SLEEP" ]; then
	ERROR_SLEEP=30
fi
if [ -z "$FINISH_SLEEP" ]; then
	FINISH_SLEEP=0
fi

# Install dependencies (skip if already installed for local testing)
if command -v apt-get >/dev/null 2>&1; then
	apt-get update -qq && apt-get install -y -qq wget osmium-tool >/dev/null
fi

echo "=== Downloading OSM data ==="

# Ensure target directory exists and is accessible
if [ ! -d "$CUSTOM_DIR" ]; then
	echo "ERROR: Target directory $CUSTOM_DIR does not exist"
	sleep $ERROR_SLEEP
	exit 1
fi

cd "$CUSTOM_DIR" || {
	echo "ERROR: Cannot access target directory $CUSTOM_DIR"
	sleep $ERROR_SLEEP
	exit 1
}

# Parse comma-separated URLs
IFS=','
for url in $OSM_URLS; do
	url=$(echo "$url" | xargs) # trim whitespace
	filename=$(basename "$url")
	echo "Downloading: $filename"
	wget -c "$url" -O "$filename" || exit 1
done

# Merge if multiple files exist
pbf_count=$(ls -1 *.pbf 2>/dev/null | wc -l)
if [ "$pbf_count" -gt 1 ]; then
	echo "=== Merging $pbf_count PBF files ==="
	osmium merge *.pbf -o merged.osm.pbf
	# Keep only merged file
	find . -name "*.pbf" ! -name "merged.osm.pbf" -delete
	echo "Merged into: merged.osm.pbf"
else
	echo "Single PBF file, no merge needed"
fi

ls -lh $CUSTOM_DIR/*.pbf

# Set permissions so build job (user 1000) can access files
chmod -R g+rw $CUSTOM_DIR/*.pbf 2>/dev/null || true

echo "=== OSM download complete ==="

sleep $FINISH_SLEEP
