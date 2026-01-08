#!/bin/bash
set -e

# Source shared functions
source /scripts/job-functions.sh

# Check if we should skip based on init job mode
if ! handle_download_mode; then
    echo "Skipping elevation download based on mode"
    exit 0
fi

# If we're here, check if data already exists
if check_elevation_data; then
    echo "Elevation data already exists, skipping download"
    exit 0
fi

echo "=== Starting Elevation Download ==="

# Default to Switzerland elevation bounds if not set
# Switzerland: lat 45-48°N, lon 5-11°E
if [ -z "$ELEVATION_BOUNDS" ]; then
	ELEVATION_BOUNDS="45,46,47,48:5,6,7,8,9,10,11"
fi
if [ -z "$TARGET_DIR" ]; then
	TARGET_DIR="/custom_files"
fi

# Install dependencies (skip if already installed for local testing)
if command -v apt-get >/dev/null 2>&1; then
	apt-get update -qq && apt-get install -y -qq wget unzip file tree >/dev/null
fi

echo "=== Downloading elevation data (SRTM HGT) ==="
mkdir -p $TARGET_DIR/elevation_data
cd $TARGET_DIR/elevation_data

# Parse bounds: "45,46,47,48:5,6,7,8,9,10,11" -> lat_range:lon_range
LAT_RANGE=$(echo "$ELEVATION_BOUNDS" | cut -d':' -f1)
LON_RANGE=$(echo "$ELEVATION_BOUNDS" | cut -d':' -f2)

echo "Latitude range: $LAT_RANGE"
echo "Longitude range: $LON_RANGE"

total=0
downloaded=0

IFS=','
for lat in $LAT_RANGE; do
	lat=$(echo "$lat" | xargs) # trim whitespace
	mkdir -p "N$lat"

	for lon in $LON_RANGE; do
		lon_raw=$(echo "$lon" | xargs)         # raw value without padding
		lon_padded=$(printf "%03d" "$lon_raw") # 3-digit padded version
		total=$((total + 1))

		tile_lat="N$lat"
		tile_lon="E$lon_padded"
		tile="$tile_lat$tile_lon"
		echo "Attempting to download: $tile"

		# Try multiple sources in order of preference
		# Note: AWS S3 is most reliable, so prioritize it
		target_file="N$lat/$tile.hgt"
		success=false

		# Try AWS S3 first
		url="https://elevation-tiles-prod.s3.amazonaws.com/skadi/N$lat/$tile.hgt.gz"
		echo "  Trying: $url"
		temp_file="$target_file.gz"
		if wget -q -O "$temp_file" "$url" 2>/dev/null; then
			if file "$temp_file" | grep -q "gzip"; then
				gunzip -f "$temp_file"
				downloaded=$((downloaded + 1))
				echo "✓ Downloaded and extracted: $tile"
				success=true
			else
				rm -f "$temp_file"
			fi
		fi

		# Try viewfinder if AWS failed
		if [ "$success" = false ]; then
			url="http://viewfinderpanoramas.org/dem3/$tile.hgt.zip"
			echo "  Trying: $url"
			temp_file="$target_file.zip"
			if wget -q -O "$temp_file" "$url" 2>/dev/null; then
				if file "$temp_file" | grep -q "Zip"; then
					unzip -q -o "$temp_file" -d "N$lat/" "$tile.hgt" 2>/dev/null && success=true
					rm -f "$temp_file"
					if [ "$success" = true ]; then
						downloaded=$((downloaded + 1))
						echo "✓ Downloaded and extracted: $tile"
					fi
				else
					rm -f "$temp_file"
				fi
			fi
		fi

		if [ "$success" = false ]; then
			echo "✗ Not available from any source: $tile"
		fi
	done
done

echo "=== Elevation download complete ==="
echo "Downloaded $downloaded out of $total tiles"
tree -fhi $TARGET_DIR/elevation_data/

# Set permissions so build job (user 1000) can access files
chmod -R g+rw $TARGET_DIR/elevation_data 2>/dev/null || true

# Valhalla needs at least some elevation data
if [ $downloaded -eq 0 ]; then
	echo "ERROR: No elevation tiles downloaded!"
	exit 1
fi
