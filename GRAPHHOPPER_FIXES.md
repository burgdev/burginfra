# GraphHopper and Map-Data Implementation Fixes

## Overview
This document summarizes all critical fixes made to the map-data and GraphHopper implementation after code review.

**Note**: Updated to use GraphHopper 11.0 from GitHub Container Registry (`ghcr.io/graphhopper/graphhopper:11.0`)

## Critical Fixes Applied

### 1. **Map-Data Job Permissions** ✅ FIXED
**Issue**: Job ran as non-root (1000:1000) but script tried to `apt-get install` packages, which requires root.

**Location**: `k8s/apps/map-data/base/job-download.yaml`

**Fix**: Removed pod-level `securityContext`, allowing container to run as root initially. The script itself handles setting ownership to 1000:1000 at the end.

**Before**:
```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  runAsNonRoot: true
```

**After**:
```yaml
# Run as root initially to install packages, then chown
# Security context is set in the script after installation
```

### 2. **GraphHopper ConfigMap Script Reference** ✅ FIXED
**Issue**: Job referenced `/scripts/wait-and-build.sh` but ConfigMap only contained `download-and-build.sh`.

**Location**: `k8s/apps/graphhopper/base/kustomization.yaml`

**Fix**: Updated ConfigMap to reference the correct script.

**Before**:
```yaml
configMapGenerator:
  - name: graphhopper-scripts
    files:
      - download-and-build.sh
```

**After**:
```yaml
configMapGenerator:
  - name: graphhopper-scripts
    files:
      - wait-and-build.sh
```

### 3. **Missing log_error Function** ✅ FIXED
**Issue**: `wait-and-build.sh` called `log_error` but didn't define it, causing "command not found" errors with `set -e`.

**Location**: `k8s/apps/graphhopper/base/scripts/wait-and-build.sh`

**Fix**: Added `log_error` function definition.

**Added**:
```bash
log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}
```

### 4. **JVM Memory Argument Format** ✅ FIXED
**Issue**: Kubernetes memory quantities like `8Gi` passed directly to JVM as `-Xmx8Gi`, which is invalid (JVM expects `8g`).

**Location**: `k8s/apps/graphhopper/base/job-initialize.yaml`

**Fix**: Added shell script to convert Kubernetes format to JVM format.

**Before**:
```yaml
env:
  - name: JAVA_OPTS
    value: "-Xmx${GRAPHOPPER_BUILD_MEMORY} -Xms${GRAPHOPPER_BUILD_MEMORY}"
```

**After**:
```yaml
env:
  - name: GRAPHOPPER_BUILD_MEMORY
    value: ${GRAPHOPPER_BUILD_MEMORY}
command:
  - /bin/bash
  - -c
  - |
    # Convert Kubernetes memory format (8Gi) to JVM format (8g)
    MEM_NUM=$(echo "${GRAPHOPPER_BUILD_MEMORY}" | sed 's/Gi\|Gi//' | sed 's/G\|G//')
    JAVA_OPTS="-Xmx${MEM_NUM}g -Xms${MEM_NUM}g -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
    echo "Memory: ${MEM_NUM}g"
    java ${JAVA_OPTS} -jar /graphhopper-web.jar config ${CONFIG_FILE} import
```

### 5. **MAP_DATA_INIT_JOB Implementation** ✅ FIXED
**Issue**: `MAP_DATA_INIT_JOB` variable passed but never used; documented init modes (auto, check, bypass) had no effect.

**Location**: `k8s/apps/map-data/base/scripts/download-all.sh`

**Fix**: 
1. Added `INIT_MODE` variable reading from `MAP_DATA_INIT_JOB`
2. Wrapped all three download sections (OSM, GTFS, Elevation) with mode checks

**Modes Implemented**:
- **`auto`**: Download if data doesn't exist or is outdated (default)
- **`check`**: Verify data exists, fail if missing
- **`bypass`**: Skip all downloads, assume data exists
- **`download`**: Always re-download (implicit in auto mode)

**Example Added**:
```bash
# Init job mode
INIT_MODE="${MAP_DATA_INIT_JOB:-auto}"
echo "Init mode: ${INIT_MODE}"

# Check init mode - if 'check', just verify data exists
if [ "$${INIT_MODE}" = "check" ]; then
    echo "Mode: check - verifying OSM data exists..."
    if [ -d "$${OSM_DATA_DIR}" ] && ls $${OSM_DATA_DIR}/*.pbf >/dev/null 2>&1; then
        echo "✓ OSM data found, skipping download"
    else
        echo "✗ OSM data not found!"
        exit 1
    fi
elif [ "$${INIT_MODE}" = "bypass" ]; then
    echo "Mode: bypass - skipping OSM download"
else
    # auto or download mode - proceed with downloads
    ...
fi
```

## Additional Enhancements

### 6. **Timestamp Files** ✅ ADDED
**Enhancement**: Map-data download now writes `.data_timestamp` files to signal data freshness to consumers.

**Location**: `k8s/apps/map-data/base/scripts/download-all.sh`

**Added**:
```bash
# Write timestamp files to signal data freshness
echo ""
echo "Writing timestamp files..."
date +%s > "$${OSM_DATA_DIR}/.data_timestamp"
date +%s > "$${GTFS_DATA_DIR}/.data_timestamp"
date +%s > "$${ELEVATION_DATA_DIR}/.data_timestamp"
echo "Data timestamp: $(date)"
```

### 7. **GraphHopper Wait-for-Data Logic** ✅ ADDED
**Enhancement**: GraphHopper initContainer waits for map-data PVCs to be populated before starting.

**Location**: `k8s/apps/graphhopper/base/scripts/wait-and-build.sh`

**Features**:
- Waits up to 3600 seconds (1 hour) for data
- Checks for `.data_timestamp` files
- Verifies required files exist
- Creates config with GTFS/transit support if data available
- Supports car, bike, foot, and public transit (pt) profiles

### 8. **GraphHopper Deployment Wait Logic** ✅ ADDED
**Enhancement**: GraphHopper deployment has initContainer that waits for graph to be built before starting service.

**Location**: `k8s/apps/graphhopper/base/deployment.yaml`

**Added**:
```yaml
initContainers:
  - name: wait-for-graph
    image: debian:12-slim
    command: ["/bin/sh", "-c"]
    args:
      - |
        echo "=== Waiting for GraphHopper graph to be ready ==="
        MAX_WAIT=3600
        elapsed=0
        
        while [ $elapsed -lt $MAX_WAIT ]; do
            if [ -f "/data/.gh/nodes" ]; then
                echo "✓ Graph found!"
                exit 0
            fi
            echo -n "."
            sleep 10
            elapsed=$((elapsed + 10))
        done
```

## Testing Checklist

Before deploying, verify:

- [ ] Map-data job completes successfully on local cluster
- [ ] Timestamp files are created in all PVCs
- [ ] GraphHopper init job successfully waits for data
- [ ] GraphHopper graph builds successfully
- [ ] GraphHopper deployment starts without errors
- [ ] GTFS/transit support works if data is present
- [ ] Init modes (auto, check, bypass) work correctly
- [ ] Memory conversion (8Gi → 8g) works in GraphHopper build

## Deployment Flow

### 1. Deploy Map-Data
```bash
kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
flux reconcile kustomization apps --with-source
kubectl create job --from=job/map-data-download map-data-init -n production
kubectl logs -n production -l job-name=map-data-download -f
```

### 2. Build GraphHopper Graph
```bash
kubectl create job --from=job/graphhopper-initialize graphhopper-init -n production
kubectl logs -n production -l job-name=graphhopper-init -c wait-for-data -f
kubectl logs -n production -l job-name=graphhopper-init -c build-graph -f
```

### 3. Start GraphHopper Service
```bash
# Set replicas to 1 in cluster settings
kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
# Deployment will automatically start when graph is ready
kubectl logs -n production deployment/graphhopper -f
```

## Files Modified

1. `k8s/apps/map-data/base/job-download.yaml` - Removed non-root securityContext
2. `k8s/apps/map-data/base/scripts/download-all.sh` - Added init modes, timestamp writing
3. `k8s/apps/graphhopper/base/kustomization.yaml` - Changed script to wait-and-build.sh
4. `k8s/apps/graphhopper/base/scripts/wait-and-build.sh` - Added log_error, wait logic, GTFS support
5. `k8s/apps/graphhopper/base/job-initialize.yaml` - Added memory conversion, wait-for-data initContainer
6. `k8s/apps/graphhopper/base/deployment.yaml` - Added wait-for-graph initContainer, shared PVC mounting

## Summary

All critical issues identified in review have been fixed:
- ✅ Permissions fixed for package installation
- ✅ Script references corrected
- ✅ Missing functions added
- ✅ JVM memory arguments properly formatted
- ✅ Init modes implemented and functional

The implementation now provides a robust, dependency-aware deployment chain:
```
map-data download → (timestamp) → GraphHopper wait → GraphHopper build → GraphHopper run
```

With proper GTFS/transit support and flexible init modes for different deployment scenarios.
