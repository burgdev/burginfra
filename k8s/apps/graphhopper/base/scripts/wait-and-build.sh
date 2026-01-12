#!/bin/bash
set -e

# GraphHopper Data Wait Script
# Waits for map-data PVCs to be populated, then builds graphs

echo "=== GraphHopper Data Wait and Build ==="

# Configuration
OSM_DATA_DIR="$${OSM_DATA_DIR:-/osm_data}"
GTFS_DATA_DIR="$${GTFS_DATA_DIR:-/gtfs_data}"
GRAPH_DIR="$${GRAPH_DIR:-/data/.gh}"
CONFIG_FILE="$${CONFIG_FILE:-/data/config.yml}"
MAX_WAIT="$${MAX_WAIT:-3600}"  # Maximum wait time: 1 hour
CHECK_INTERVAL="$${CHECK_INTERVAL:-10}"  # Check every 10 seconds

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Function to wait for data with timestamp checking
wait_for_data() {
    local data_dir="$1"
    local data_name="$2"
    
    log_info "Waiting for ${data_name} data..."
    
    local elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        # Check if timestamp file exists
        if [ -f "${data_dir}/.data_timestamp" ]; then
            local timestamp=$(cat "${data_dir}/.data_timestamp")
            local date_str=$(date -d @$timestamp 2>/dev/null || date -r $timestamp 2>/dev/null || echo "unknown")
            log_info "${data_name} data ready (timestamp: ${date_str})"
            return 0
        fi
        
        # Check if data directory exists and has content
        if [ -d "${data_dir}" ] && [ "$(ls -A ${data_dir} 2>/dev/null)" ]; then
            log_warn "${data_name} directory exists but no timestamp yet, waiting..."
        else
            log_warn "Waiting for ${data_name} PVC to be mounted..."
        fi
        
        sleep $CHECK_INTERVAL
        elapsed=$((elapsed + CHECK_INTERVAL))
        echo -n "."
    done
    
    echo ""
    log_warn "Timeout waiting for ${data_name} data after ${MAX_WAIT}s"
    return 1
}

# Function to verify required files exist
verify_osm_data() {
    log_info "Verifying OSM data..."
    
    if [ -z "$${OSM_FILE}" ]; then
        # Find OSM file
        OSM_FILE=$(find "$${OSM_DATA_DIR}" -name "*.osm.pbf" -type f | head -n 1)
    fi

    if [ -z "$${OSM_FILE}" ] || [ ! -f "$${OSM_FILE}" ]; then
        log_error "No OSM PBF file found in $${OSM_DATA_DIR}"
        return 1
    fi

    local size=$(du -h "$${OSM_FILE}" | cut -f1)
    log_info "OSM file found: $${OSM_FILE} ($${size})"
    return 0
}

verify_gtfs_data() {
    log_info "Verifying GTFS data..."

    if [ ! -d "$${GTFS_DATA_DIR}" ]; then
        log_warn "GTFS directory not found, transit support will be disabled"
        return 0  # Not fatal
    fi

    local feed_count=$(find "$${GTFS_DATA_DIR}" -name "stops.txt" | wc -l)
    if [ $feed_count -gt 0 ]; then
        log_info "GTFS feeds found: $${feed_count} feed(s)"
        return 0
    else
        log_warn "No GTFS data found, transit support will be disabled"
        return 0  # Not fatal
    fi
}

# Main execution
main() {
    log_info "Starting GraphHopper data wait process"
    log_info "Max wait time: ${MAX_WAIT}s"
    
    # Wait for all data sources
    wait_for_data "$${OSM_DATA_DIR}" "OSM"
    wait_for_data "$${GTFS_DATA_DIR}" "GTFS"
    
    echo ""
    log_info "All data sources ready!"
    
    # Verify data
    verify_osm_data
    verify_gtfs_data
    
    # Create GraphHopper config
    log_info "Creating GraphHopper configuration..."
    create_config
    
    log_info "Data ready. GraphHopper can now build graphs."
    log_info "Run: java -jar /graphhopper-web.jar config ${CONFIG_FILE} import"
}

# Create config function
create_config() {
    # Find OSM file
    OSM_FILE=$(find "$${OSM_DATA_DIR}" -name "*.osm.pbf" -type f | head -n 1)

    if [ -z "$${OSM_FILE}" ]; then
        log_error "Cannot find OSM file"
        exit 1
    fi

    log_info "Using OSM file: $${OSM_FILE}"

    # Check if GTFS data exists
    GTFS_ENABLED="false"
    if [ -d "$${GTFS_DATA_DIR}" ] && [ "$(find $${GTFS_DATA_DIR} -name 'stops.txt' | wc -l)" -gt 0 ]; then
        GTFS_ENABLED="true"
        log_info "GTFS/transit support: ENABLED"
    else
        log_info "GTFS/transit support: DISABLED (no GTFS data)"
    fi
    
    # Create config.yml
    cat > "$${CONFIG_FILE}" << EOF
graphhopper:
  # Data reader configuration
  datareader:
    file: $${OSM_FILE}
    import_vehicle: all

  # Graph location
  graph.location: $${GRAPH_DIR}

  # Profiles to build
  profiles:
    - car
    - bike
    - foot
$(if [ "${GTFS_ENABLED}" = "true" ]; then
    echo "    - pt"
fi)

  # Contraction Hierarchies (fast queries)
  ch:
    disable: false
    profiles: car, bike, foot
$(if [ "${GTFS_ENABLED}" = "true" ]; then
    echo "    # CH not supported for public transit"
fi)

  # Landmarks (alternative to CH)
  lm:
    disable: true

  # Server configuration
  server:
    host: 0.0.0.0
    port: 8989
    min_threads: 2
    max_threads: 4

  # Data access
  graph.dataaccess: RAM_STORE

  # Encoder preferences
  encoder:
    prefer: car
$(if [ "${GTFS_ENABLED}" = "true" ]; then
    echo ""
    echo "  # Public transit configuration"
    echo "  pt:"
    echo "    # GTFS data location"
    echo "    gtfs_file: $${GTFS_DATA_DIR}/*/gtfs.zip"
    echo "    # Blocking tours"
    echo "    block_trip_search: true"
    echo "    # Use fuzzy transit search"
    echo "    fuzzy_transfer_cost: 180"
fi)

  # Speed modes
  speed_mode:
    car: traffic

  # Logging
  logging:
    level: INFO
EOF

    log_info "Configuration created: ${CONFIG_FILE}"
    log_info "Profiles: car, bike, foot$(if [ "${GTFS_ENABLED}" = "true" ]; then echo ", pt (public transit)"; fi)"
}

# Run main
main
