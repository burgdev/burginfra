#!/bin/bash
set -e

# NOTE: This script uses $${VAR} syntax (double dollar signs) for variable expansion
# to prevent Flux from substituting variables when deploying via Kustomize.
# When Flux processes this ConfigMap, $${VAR} becomes ${VAR} in the actual script.
#
# IMPORTANT: Only ${VAR} needs escaping! $VAR and $(command) work fine as-is.
#
# For LOCAL TESTING, use the wrapper script: ./test-download-local.sh
# The wrapper automatically converts $${VAR} to ${VAR} for local execution.

echo "=== Valhalla Data Download ==="
echo "Starting unified download process"

# Configuration with defaults
CUSTOM_DIR="$${CUSTOM_DIR:-/custom_files}"
GTFS_DIR="$${GTFS_DIR:-/gtfs_feeds}"
ERROR_SLEEP="$${ERROR_SLEEP:-30}"
FINISH_SLEEP="$${FINISH_SLEEP:-0}"

# Default URLs if not set
OSM_URLS="$${OSM_URLS:-https://download.geofabrik.de/europe/switzerland-latest.osm.pbf}"
GTFS_URLS="$${GTFS_URLS:-https://data.opentransportdata.swiss/en/dataset/timetable-2026-gtfs2020/resource_permalink/gtfs_fp2026_20260103.zip}"
ELEVATION_BOUNDS="$${ELEVATION_BOUNDS:-45,46,47,48:5,6,7,8,9,10,11}"

# Function to check if a file needs downloading based on ETag/Last-Modified headers
# Usage: check_file_needs_download <url> <header_file> [wget_extra_args]
# Returns: 0 if download needed, 1 if file is up-to-date
check_file_needs_download() {
	local url="$1"
	local header_file="$2"
	shift 2
	local wget_args="$@"

	# Get remote headers
	local remote_headers=$(wget --spider --server-response $wget_args "$url" 2>&1 | grep -E "ETag|Last-Modified" || true)

	if [ -z "$remote_headers" ]; then
		# Server doesn't provide headers, assume download needed
		return 0
	fi

	if [ ! -f "$header_file" ]; then
		# No previous headers, download needed
		return 0
	fi

	local local_headers=$(cat "$header_file")

	if [ "$local_headers" = "$remote_headers" ]; then
		# Headers match, no download needed
		return 1
	else
		# Headers differ, download needed
		return 0
	fi
}

# Function to store headers for future comparison
# Usage: store_file_headers <url> <header_file> [wget_extra_args]
store_file_headers() {
	local url="$1"
	local header_file="$2"
	shift 2
	local wget_args="$@"

	wget --spider --server-response $wget_args "$url" 2>&1 | grep -E "ETag|Last-Modified" >"$header_file" || true
}

# Install all dependencies upfront
echo "=== Installing dependencies ==="
set +e
if command -v apt-get >/dev/null 2>&1; then
	apt-get update -qq
	apt-get install -y -qq wget osmium-tool unzip file tree >/dev/null
fi
set -e

# ============================================
# 1. DOWNLOAD OSM DATA
# ============================================
echo ""
echo "=== 1/3: Downloading OSM data ==="

if [ ! -d "$${CUSTOM_DIR}" ]; then
	echo "ERROR: Target directory $${CUSTOM_DIR} does not exist"
	sleep $${ERROR_SLEEP}
	exit 1
fi

cd "$${CUSTOM_DIR}"

# Download OSM PBF files
IFS=','
for url in $${OSM_URLS}; do
	url=$(echo "$${url}" | xargs)
	filename=$(basename "$${url}")
	header_file="$${filename}.headers"

	# Check if file exists and is up-to-date
	if [ -f "$${filename}" ]; then
		echo "  File exists: $${filename}, checking if update needed..."

		if check_file_needs_download "$${url}" "$${header_file}"; then
			echo "  → File has changed or headers unavailable, re-downloading..."
		else
			echo "  ✓ File is up-to-date (same ETag/Last-Modified), skipping download"
			continue
		fi
	fi

	echo "  Downloading: $${filename}"
	wget -c "$${url}" -O "$${filename}" || {
		echo "ERROR: Failed to download $${url}"
		sleep $${ERROR_SLEEP}
		exit 1
	}

	# Store headers for future comparison
	store_file_headers "$${url}" "$${header_file}"
done

# Merge if multiple files
pbf_count=$(ls -1 *.pbf 2>/dev/null | wc -l)
if [ "$${pbf_count}" -gt 1 ]; then
	echo "  Merging $${pbf_count} PBF files..."
	osmium merge *.pbf -o merged.osm.pbf
	find . -name "*.pbf" ! -name "merged.osm.pbf" -delete
	echo "  ✓ Merged into: merged.osm.pbf"
else
	echo "  ✓ Single PBF file: $(ls *.pbf)"
fi

# ============================================
# 2. DOWNLOAD GTFS DATA
# ============================================
echo ""
echo "=== 2/3: Downloading GTFS data ==="

mkdir -p $${GTFS_DIR}
cd "$${GTFS_DIR}"

# Download GTFS feeds
index=1
for url in $${GTFS_URLS}; do
	url=$(echo "$${url}" | xargs)
	feed_dir="feed_$${index}"
	mkdir -p "$${feed_dir}"
	cd "$${feed_dir}"

	# Check if feed already exists and is up-to-date
	skip_download=false
	if [ -f ".gtfs.complete" ]; then
		echo "  GTFS feed $${index} exists, checking if update needed..."

		# For GTFS feeds with signed URLs, check if zip file exists and matches recorded size
		# This avoids the signed URL timestamp issue (redirects make remote header checks unreliable)
		if [ -f ".gtfs.size" ] && [ -f "gtfs.zip" ]; then
			local_size=$(cat ".gtfs.size")
			actual_size=$(stat -c%s gtfs.zip 2>/dev/null || stat -f%z gtfs.zip 2>/dev/null)

			if [ "$${local_size}" = "$${actual_size}" ]; then
				echo "  ✓ GTFS feed $${index} is up-to-date (size: $${local_size} bytes), skipping download"
				skip_download=true
			else
				echo "  → GTFS feed $${index} zip size mismatch, re-downloading..."
			fi
		else
			echo "  → No previous download found, downloading..."
		fi
	fi

	if [ "$skip_download" = false ]; then
		echo "  Downloading GTFS feed $${index} from: $${url}"

		# Clean directory before re-downloading (except marker files)
		find . -type f ! -name ".gtfs.*" -delete 2>/dev/null || true

		if wget --max-redirect=5 -O gtfs.zip "$${url}" 2>&1; then
			if [ -f gtfs.zip ] && [ -s gtfs.zip ]; then
				if file gtfs.zip | grep -q "Zip"; then
					unzip -o -q gtfs.zip

					# Store file size for future comparison (keep zip for caching)
					stat -c%s gtfs.zip >".gtfs.size" 2>/dev/null || stat -f%z gtfs.zip >".gtfs.size" 2>/dev/null

					# Mark as complete
					touch ".gtfs.complete"

					echo "  ✓ GTFS feed $${index} extracted successfully"
				else
					echo "  WARNING: Downloaded file is not a zip archive, keeping as-is"
					mv gtfs.zip gtfs_data
					touch ".gtfs.complete"
				fi
			else
				echo "  ✗ ERROR: Downloaded file is empty or missing"
				sleep $${ERROR_SLEEP}
			fi
		else
			echo "  ✗ WARNING: Could not download GTFS feed from $${url}"
			sleep $${ERROR_SLEEP}
		fi
	fi

	cd ..
	index=$((index + 1))
done

# ============================================
# 3. DOWNLOAD ELEVATION DATA
# ============================================
echo ""
echo "=== 3/3: Downloading elevation data (SRTM HGT) ==="

mkdir -p $${CUSTOM_DIR}/elevation_data
cd $${CUSTOM_DIR}/elevation_data

# Parse bounds: "45,46,47,48:5,6,7,8,9,10,11" -> lat_range:lon_range
LAT_RANGE=$(echo "$${ELEVATION_BOUNDS}" | cut -d':' -f1)
LON_RANGE=$(echo "$${ELEVATION_BOUNDS}" | cut -d':' -f2)

echo "  Latitude range: $${LAT_RANGE}"
echo "  Longitude range: $${LON_RANGE}"

total=0
downloaded=0

for lat in $${LAT_RANGE}; do
	lat=$(echo "$${lat}" | xargs)
	mkdir -p "N$${lat}"

	for lon in $${LON_RANGE}; do
		lon_raw=$(echo "$${lon}" | xargs)
		lon_padded=$(printf "%03d" "$${lon_raw}")
		total=$((total + 1))

		tile_lat="N$${lat}"
		tile_lon="E$${lon_padded}"
		tile="$${tile_lat}$${tile_lon}"

		target_file="N$${lat}/$${tile}.hgt"
		header_file="N$${lat}/$${tile}.hgt.headers"

		# Check if tile already exists and is up-to-date
		if [ -f "$${target_file}" ] && [ -s "$${target_file}" ]; then
			# Try AWS S3 first for header check
			url="https://elevation-tiles-prod.s3.amazonaws.com/skadi/N$${lat}/$${tile}.hgt.gz"

			if check_file_needs_download "$${url}" "$${header_file}" "-q"; then
				# File changed, re-download
				rm -f "$${target_file}"
			else
				# File is up-to-date
				downloaded=$((downloaded + 1))
				continue
			fi
		fi

		success=false
		source_url=""

		# Try AWS S3 first (most reliable)
		url="https://elevation-tiles-prod.s3.amazonaws.com/skadi/N$${lat}/$${tile}.hgt.gz"
		temp_file="$${target_file}.gz"
		if wget -q -O "$${temp_file}" "$${url}" 2>/dev/null; then
			if file "$${temp_file}" | grep -q "gzip"; then
				gunzip -f "$${temp_file}"
				source_url="$${url}"
				downloaded=$((downloaded + 1))
				echo "  ✓ Downloaded: $${tile}"
				success=true
			else
				rm -f "$${temp_file}"
			fi
		fi

		# Try viewfinder if AWS failed
		if [ "$${success}" = false ]; then
			url="http://viewfinderpanoramas.org/dem3/$${tile}.hgt.zip"
			temp_file="$${target_file}.zip"
			if wget -q -O "$${temp_file}" "$${url}" 2>/dev/null; then
				if file "$${temp_file}" | grep -q "Zip"; then
					unzip -q -o "$${temp_file}" -d "N$${lat}/" "$${tile}.hgt" 2>/dev/null && success=true
					rm -f "$${temp_file}"
					if [ "$${success}" = true ]; then
						source_url="$${url}"
						downloaded=$((downloaded + 1))
						echo "  ✓ Downloaded: $${tile}"
					fi
				else
					rm -f "$${temp_file}"
				fi
			fi
		fi

		# Store headers if download was successful
		if [ "$${success}" = true ] && [ -n "$${source_url}" ]; then
			store_file_headers "$${source_url}" "$${header_file}" "-q"
		fi

		if [ "$${success}" = false ]; then
			echo "  ✗ Not available: $${tile}"
		fi
	done
done

echo "  Downloaded $${downloaded} out of $${total} elevation tiles"

# Valhalla needs at least some elevation data
if [ $${downloaded} -eq 0 ]; then
	echo "ERROR: No elevation tiles downloaded!"
	sleep $${ERROR_SLEEP}
	exit 1
fi

# ============================================
# FINAL SUMMARY
# ============================================
echo ""
echo "=== Download Summary ==="
echo "OSM data:"
if [ -d "$${CUSTOM_DIR}" ] && ls $${CUSTOM_DIR}/*.pbf >/dev/null 2>&1; then
	pbf_count=$(ls -1 $${CUSTOM_DIR}/*.pbf 2>/dev/null | wc -l)
	pbf_size=$(du -sh $${CUSTOM_DIR}/*.pbf 2>/dev/null | tail -1 | awk '{print $1}')
	echo "  $${pbf_count} file(s), $${pbf_size} total"
else
	echo "  (none)"
fi
echo ""
echo "GTFS feeds:"
if [ -d "$${GTFS_DIR}" ] && ls $${GTFS_DIR}/feed_* >/dev/null 2>&1; then
	for feed in $${GTFS_DIR}/feed_*; do
		if [ -d "$${feed}" ]; then
			feed_name=$(basename "$${feed}")
			total_size=$(du -sh "$${feed}" 2>/dev/null | awk '{print $1}')
			zip_size="N/A"
			if [ -f "$${feed}/gtfs.zip" ]; then
				zip_size=$(du -sh "$${feed}/gtfs.zip" 2>/dev/null | awk '{print $1}')
			fi
			echo "  $${feed_name}: $${total_size} total ($${zip_size} zip)"
		fi
	done
else
	echo "  (none)"
fi
echo ""
echo "Elevation data:"
if [ -d "$${CUSTOM_DIR}/elevation_data" ] && [ $${downloaded} -gt 0 ]; then
	elev_size=$(du -sh $${CUSTOM_DIR}/elevation_data 2>/dev/null | awk '{print $1}')
	echo "  $${downloaded} tiles, $${elev_size} total"
else
	echo "  (none)"
fi

# Set permissions for build job (user 1000)
chmod -R g+rw $${CUSTOM_DIR} 2>/dev/null || true
chmod -R g+rw $${GTFS_DIR} 2>/dev/null || true

echo ""
echo "=== All downloads complete ==="
sleep $${FINISH_SLEEP}
