#!/bin/bash
set -e

# Source shared functions
source /scripts/job-functions.sh

# Check if we should skip based on init job mode
if ! handle_download_mode; then
	echo "Skipping GTFS download based on mode"
	exit 0
fi

# If we're here, check if data already exists
if check_gtfs_data; then
	echo "GTFS data already exists, skipping download"
	exit 0
fi

echo "=== Starting GTFS Download ==="

# Default to Swiss GTFS feeds if not set
if [ -z "$GTFS_URLS" ]; then
	GTFS_URLS="https://data.opentransportdata.swiss/en/dataset/timetable-2026-gtfs2020/resource_permalink/gtfs_fp2026_20260103.zip"
fi
if [ -z "$GTFS_DIR" ]; then
	GTFS_DIR="/gtfs_feeds"
fi
if [ -z "$ERROR_SLEEP" ]; then
	ERROR_SLEEP=30
fi
if [ -z "$FINISH_SLEEP" ]; then
	FINISH_SLEEP=0
fi

# Install dependencies (skip if already installed for local testing)
if command -v apt-get >/dev/null 2>&1; then
	apt-get update -qq && apt-get install -y -qq wget unzip file >/dev/null
fi

echo "=== Downloading GTFS data ==="
mkdir -p $GTFS_DIR
cd $GTFS_DIR

# Parse comma-separated URLs
IFS=','
index=1
for url in $GTFS_URLS; do
	url=$(echo "$url" | xargs) # trim whitespace
	feed_dir="feed_$index"
	mkdir -p "$feed_dir"
	cd "$feed_dir"

	echo "Downloading GTFS feed $index from: $url"

	# Download with redirect following and progress bar
	if wget --max-redirect=5 -O gtfs.zip "$url" 2>&1; then
		# Check if we actually got a file
		if [ -f gtfs.zip ] && [ -s gtfs.zip ]; then
			# Check if it's actually a zip file
			if file gtfs.zip | grep -q "Zip"; then
				unzip -q gtfs.zip
				rm gtfs.zip
				echo "✓ GTFS feed $index extracted successfully"
			else
				echo "WARNING: Downloaded file is not a zip archive, keeping as-is"
				mv gtfs.zip gtfs_data
			fi
		else
			echo "✗ ERROR: Downloaded file is empty or missing"
			sleep $ERROR_SLEEP
			rm -f gtfs.zip
		fi
	else
		echo "✗ WARNING: Could not download GTFS feed from $url"
		sleep $ERROR_SLEEP
	fi

	cd ..
	index=$((index + 1))
done

ls -lhR $GTFS_DIR

# Set permissions so build job (user 1000) can access files
chmod -R g+rw $GTFS_DIR 2>/dev/null || true

echo "=== GTFS download complete ==="

sleep $FINISH_SLEEP
