#!/bin/bash
# Shared functions for Valhalla init jobs

TARGET_DIR="${TARGET_DIR:-/custom_files}"

# Check if OSM PBF files exist
check_osm_data() {
    if ls "$TARGET_DIR"/*.pbf >/dev/null 2>&1; then
        local pbf_file=$(ls "$TARGET_DIR"/*.pbf | head -n1)
        local size=$(du -h "$pbf_file" | cut -f1)
        echo "✓ Found OSM PBF: $(basename "$pbf_file") ($size)"
        return 0
    else
        echo "✗ No OSM PBF files found"
        return 1
    fi
}

# Check if GTFS feeds exist
check_gtfs_data() {
    if [ ! -d "$TARGET_DIR/gtfs_feeds" ]; then
        echo "✗ GTFS feeds directory does not exist"
        return 1
    fi
    
    local file_count=$(find "$TARGET_DIR/gtfs_feeds" -type f 2>/dev/null | wc -l)
    if [ "$file_count" -eq 0 ]; then
        echo "✗ GTFS feeds directory is empty"
        return 1
    fi
    
    echo "✓ Found GTFS feeds: $file_count files"
    return 0
}

# Check if elevation data exists
check_elevation_data() {
    if [ ! -d "$TARGET_DIR/elevation_data" ]; then
        echo "✗ Elevation data directory does not exist"
        return 1
    fi
    
    local hgt_count=$(find "$TARGET_DIR/elevation_data" -name "*.hgt" 2>/dev/null | wc -l)
    if [ "$hgt_count" -eq 0 ]; then
        echo "✗ No elevation HGT files found"
        return 1
    fi
    
    echo "✓ Found elevation data: $hgt_count HGT tiles"
    return 0
}

# Check if Valhalla config exists
check_valhalla_config() {
    if [ ! -f "$TARGET_DIR/valhalla.json" ]; then
        echo "✗ valhalla.json not found"
        return 1
    fi
    
    echo "✓ Found valhalla.json"
    return 0
}

# Check if Valhalla tiles tarball exists
check_valhalla_tiles() {
    if [ ! -f "$TARGET_DIR/valhalla_tiles.tar" ]; then
        echo "✗ valhalla_tiles.tar not found"
        return 1
    fi
    
    local size=$(du -h "$TARGET_DIR/valhalla_tiles.tar" | cut -f1)
    echo "✓ Found valhalla_tiles.tar ($size)"
    return 0
}

# Check all download prerequisites (for download job)
check_download_prerequisites() {
    echo "=== Checking Download Job Prerequisites ==="
    local missing=0
    
    check_osm_data || missing=$((missing + 1))
    check_gtfs_data || missing=$((missing + 1))
    check_elevation_data || missing=$((missing + 1))
    
    echo ""
    if [ $missing -eq 0 ]; then
        echo "✓ All download data present"
        return 0
    else
        echo "✗ Missing $missing data type(s)"
        return 1
    fi
}

# Check all build prerequisites (for build job)
check_build_prerequisites() {
    echo "=== Checking Build Job Prerequisites ==="
    local missing=0
    
    # Build requires download data
    check_osm_data || missing=$((missing + 1))
    check_gtfs_data || missing=$((missing + 1))
    check_elevation_data || missing=$((missing + 1))
    
    # Build output check
    check_valhalla_config || missing=$((missing + 1))
    check_valhalla_tiles || missing=$((missing + 1))
    
    echo ""
    if [ $missing -eq 0 ]; then
        echo "✓ All build artifacts present"
        return 0
    elif [ $missing -le 2 ] && check_osm_data >/dev/null 2>&1 && check_gtfs_data >/dev/null 2>&1 && check_elevation_data >/dev/null 2>&1; then
        echo "→ Source data present but build artifacts missing"
        return 1
    else
        echo "✗ Missing $missing prerequisite(s)"
        return 1
    fi
}

# Handle init job mode for download job
handle_download_mode() {
    local mode="${VALHALLA_INIT_JOB:-auto}"
    
    echo "=== Download Job Mode: $mode ==="
    
    case "$mode" in
        bypass)
            echo "Mode BYPASS: Skipping download"
            if ! check_download_prerequisites; then
                echo "WARNING: bypass mode but data is missing!"
            fi
            return 1  # Signal to skip
            ;;
        
        check)
            echo "Mode CHECK: Verifying data exists"
            if check_download_prerequisites; then
                return 1  # Signal to skip (data exists)
            else
                echo "ERROR: Required data missing in check mode"
                exit 1
            fi
            ;;
        
        auto)
            echo "Mode AUTO: Download if missing"
            if check_download_prerequisites; then
                echo "→ Data already exists, skipping download"
                return 1  # Signal to skip
            else
                echo "→ Data missing, proceeding with download"
                return 0  # Signal to proceed
            fi
            ;;
        
        download)
            echo "Mode DOWNLOAD: Force download"
            return 0  # Signal to proceed
            ;;
        
        *)
            echo "ERROR: Unknown mode '$mode'"
            echo "Valid modes: download, auto, check, bypass"
            exit 1
            ;;
    esac
}

# Handle init job mode for build job
handle_build_mode() {
    local mode="${VALHALLA_INIT_JOB:-auto}"
    
    echo "=== Build Job Mode: $mode ==="
    
    case "$mode" in
        bypass)
            echo "Mode BYPASS: Skipping build"
            if ! check_build_prerequisites; then
                echo "WARNING: bypass mode but build artifacts are missing!"
            fi
            return 1  # Signal to skip
            ;;
        
        check)
            echo "Mode CHECK: Verifying build artifacts exist"
            if check_build_prerequisites; then
                return 1  # Signal to skip (artifacts exist)
            else
                echo "ERROR: Required build artifacts missing in check mode"
                exit 1
            fi
            ;;
        
        auto)
            echo "Mode AUTO: Build if missing"
            if check_build_prerequisites; then
                echo "→ Build artifacts already exist, skipping build"
                return 1  # Signal to skip
            else
                echo "→ Build artifacts missing, proceeding with build"
                return 0  # Signal to proceed
            fi
            ;;
        
        download)
            echo "Mode DOWNLOAD: Force rebuild"
            return 0  # Signal to proceed
            ;;
        
        *)
            echo "ERROR: Unknown mode '$mode'"
            echo "Valid modes: download, auto, check, bypass"
            exit 1
            ;;
    esac
}
