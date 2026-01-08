#!/bin/bash
set -e

# Default to Switzerland OSM data if not set
if [ -z "$OSM_URLS" ]; then
	OSM_URLS="https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
fi
if [ -z "$TARGET_DIR" ]; then
	TARGET_DIR="/custom_files"
fi

# Install dependencies (skip if already installed for local testing)
if command -v apt-get >/dev/null 2>&1; then
	apt-get update -qq && apt-get install -y -qq wget osmium-tool >/dev/null
fi

echo "=== Downloading OSM data ==="
cd "$TARGET_DIR"

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

ls -lh $TARGET_DIR/*.pbf
echo "=== OSM download complete ==="
