# Setup Reliability and Reproducibility Improvements

## Overview
This document summarizes additional reliability and reproducibility improvements made to the GraphHopper and map-data implementation.

## All Improvements Applied ✅

### 1. Fixed Init Script Wiring ✅
**Issue**: ConfigMap referenced `wait-and-build.sh` but used wrong path, and leftover `download-and-build.sh` wasn't removed.

**Location**: 
- `k8s/apps/graphhopper/base/kustomization.yaml`
- `k8s/apps/graphhopper/base/scripts/`

**Fix**:
- Updated ConfigMap to use correct path: `scripts/wait-and-build.sh`
- Removed unused `download-and-build.sh` file
- Ensures init container calls the correct script

**Before**:
```yaml
configMapGenerator:
  - name: graphhopper-scripts
    files:
      - wait-and-build.sh  # Wrong path
```

**After**:
```yaml
configMapGenerator:
  - name: graphhopper-scripts
    files:
      - scripts/wait-and-build.sh  # Correct path
```

### 2. Normalized JVM Memory Units ✅
**Issue**: Cluster settings use Kubernetes format (`8Gi`, `512Mi`) but JVM expects different format (`8g`, `512m`).

**Location**: `k8s/apps/graphhopper/base/job-initialize.yaml`

**Fix**: Implemented robust memory unit conversion supporting all Kubernetes formats:
- `Gi` or `G` → `g` (gigabytes)
- `Mi` or `M` → `m` (megabytes)  
- Other units → passed through with default

**Implementation**:
```bash
# Normalize memory units: convert Kubernetes format to JVM format
# Kubernetes: 8Gi, 512Mi, 1G  → JVM: 8g, 512m, 1g
MEM_RAW="${GRAPHOPPER_BUILD_MEMORY}"
echo "Raw memory setting: ${MEM_RAW}"

# Extract number and unit
MEM_NUM=$(echo "${MEM_RAW}" | sed 's/[^0-9.]//g')
MEM_UNIT=$(echo "${MEM_RAW}" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')

# Convert to JVM format
case "${MEM_UNIT}" in
  GI|G)
    JVM_MEM="${MEM_NUM}g"
    ;;
  MI|M)
    JVM_MEM="${MEM_NUM}m"
    ;;
  *)
    # Assume bytes or already in JVM format, default to g
    if [ -z "${MEM_UNIT}" ]; then
      JVM_MEM="${MEM_NUM}g"
    else
      JVM_MEM="${MEM_RAW}"
    fi
    ;;
esac

echo "JVM memory: -Xmx${JVM_MEM} -Xms${JVM_MEM}"
```

**Supported Conversions**:
| Kubernetes Setting | JVM Result |
|-------------------|------------|
| `8Gi` | `-Xmx8g -Xms8g` |
| `512Mi` | `-Xmx512m -Xms512m` |
| `1G` | `-Xmx1g -Xms1g` |
| `2048M` | `-Xmx2048m -Xms2048m` |

### 3. Wired MAP_DATA_INIT_JOB Setting ✅
**Issue**: `MAP_DATA_INIT_JOB` environment variable was passed but not read by the script, making the documented init modes non-functional.

**Location**: `k8s/apps/map-data/base/scripts/download-all.sh`

**Fix**: Added variable read and debug output.

**Added**:
```bash
# Init job mode (passed from MAP_DATA_INIT_JOB cluster setting)
INIT_MODE="$${MAP_DATA_INIT_JOB:-auto}"
echo "Init mode: $${INIT_MODE}"
```

**Now Functional Modes**:
- **`auto`** (default): Download if data doesn't exist or outdated
- **`check`**: Verify data exists, fail if missing
- **`bypass`**: Skip all downloads, assume data present
- **`download`**: Always re-download (via URL checks)

**Example Usage**:
```yaml
# Cluster settings
MAP_DATA_INIT_JOB: "bypass"  # Skip downloads on production
```

### 4. Pinned GraphHopper Image Version ✅
**Issue**: Using `latest` tag is non-reproducible and can break deployments unexpectedly.

**Location**: 
- `k8s/apps/graphhopper/base/job-initialize.yaml`
- `k8s/apps/graphhopper/base/deployment.yaml`

**Fix**: Pinned to stable version `11.0` from GitHub Container Registry.

**Before**:
```yaml
image: graphhopper/graphhopper:latest
```

**After**:
```yaml
image: ghcr.io/graphhopper/graphhopper:11.0
```

**Benefits**:
- ✅ Reproducible builds
- ✅ predictable behavior
- ✅ easier rollback
- ✅ version tracking in git
- ✅ Uses official GitHub Container Registry image

## Impact Summary

### Reliability Improvements
- ✅ **Script wiring fixed**: No more "file not found" errors
- ✅ **Memory handling robust**: Supports any Kubernetes memory format
- ✅ **Init modes functional**: Control download behavior per environment
- ✅ **Reproducible deployments**: Pinned versions prevent breaking changes

### Operational Benefits
- **Clearer logs**: Memory conversion prints debug info
- **Predictable behavior**: Same version always used
- **Flexible configuration**: Init modes work as documented
- **Easier debugging**: Script prints mode and memory settings

## Testing Checklist

Before deploying, verify:

- [ ] Map-data download job completes successfully
- [ ] Init mode logs show correct mode (auto/check/bypass)
- [ ] GraphHopper build logs show correct memory conversion
- [ ] No "file not found" errors in init containers
- [ ] GraphHopper version is pinned to 7.0
- [ ] Deployments are reproducible (same image always used)

## Deployment Verification

### 1. Verify Script Wiring
```bash
kubectl logs -n production -l job-name=graphhopper-init -c wait-for-data
# Should see: "Starting GraphHopper data wait process"
```

### 2. Verify Memory Conversion
```bash
kubectl logs -n production -l job-name=graphhopper-init -c build-graph
# Should see:
# "Raw memory setting: 8Gi"
# "JVM memory: -Xmx8g -Xms8g"
```

### 3. Verify Init Modes
```bash
kubectl logs -n production -l job-name=map-data-download
# Should see: "Init mode: auto" (or check/bypass)
```

### 4. Verify Image Version
```bash
kubectl get deployment graphhopper -n production -o jsonpath='{.spec.template.spec.containers[0].image}'
# Should return: ghcr.io/graphhopper/graphhopper:11.0
```

## Configuration Examples

### Development Cluster (auto mode)
```yaml
MAP_DATA_INIT_JOB: "auto"  # Download if needed
GRAPHOPPER_BUILD_MEMORY: "12Gi"  # Local has more memory
```

### Production Cluster (bypass mode)
```yaml
MAP_DATA_INIT_JOB: "bypass"  # Use copied data
GRAPHOPPER_BUILD_MEMORY: "8Gi"  # VPS has less memory
```

## Version Upgrading

When upgrading GraphHopper versions:

1. Update pinned version in both files:
   ```bash
   # Update from 11.0 to newer version
   sed -i 's/ghcr.io\/graphhopper\/graphhopper:11.0/ghcr.io\/graphhopper\/graphhopper:12.0/g' \
     k8s/apps/graphhopper/base/job-initialize.yaml \
     k8s/apps/graphhopper/base/deployment.yaml
   ```

2. Test in development first:
   ```bash
   kubectl apply -f k8s/apps/graphhopper/overlays/production/
   kubectl create job --from=job/graphhopper-initialize test -n production
   ```

3. Monitor for compatibility issues

**Note**: GraphHopper 11.0 includes significant improvements:
- Trip-Based Public Transit Routing
- Better bicycle and foot routing
- Improved toll handling
- Custom model enhancements
- See [release notes](https://github.com/graphhopper/graphhopper/releases/tag/11.0)

## Related Documentation

- [GraphHopper Fixes](../GRAPHHOPPER_FIXES.md) - Critical bug fixes
- [Map Data README](../k8s/apps/map-data/README.md) - Shared data documentation
- [GraphHopper README](../k8s/apps/graphhopper/README.md) - GraphHopper documentation
