# GraphHopper Implementation Summary - January 2026

## Current Status: 🔴 CRITICAL ISSUES

### Deployment Failures

**GraphHopper Deployment**: `CrashLoopBackOff` (201 restarts over 3d20h)
- **Error**: Corrupted GTFS storage database
- **Root Cause**: `java.io.IOException: Wrong index checksum, store was not closed properly and could be corrupted.`
- **Location**: `com.graphhopper.gtfs.GtfsStorage.loadExisting()`
- **Pod**: `graphhopper-747694fd-hcb5d`

**Map-Data Job**: Failed
- **Job**: `map-data-download-rklq7`
- **Status**: Error (unable to retrieve logs)
- **Age**: 3d22h

**GraphHopper Initialize Job**: Failed
- **Job**: `graphhopper-initialize-9tnd2`
- **Status**: Error (0/1 completions)
- **Age**: 3d22h

### PVC Status

All PVCs are bound and appear healthy:
- `graphhopper-data`: 10Gi (fast-local-data-v3)
- `graphhopper-srtm-cache`: 2Gi (fast-local-data-v3)
- `map-data-osm`: 10Gi (fast-local-data-v3)
- `map-data-gtfs`: 2Gi (fast-local-data-v3)
- `map-data-elevation`: 5Gi (fast-local-data-v3)

## Architecture Overview

### Components

1. **Map-Data App** (`k8s/apps/map-data/`)
   - Centralized OSM, GTFS, and elevation data downloader
   - PVCs: `map-data-osm`, `map-data-gtfs`, `map-data-elevation`
   - Job: `map-data-download` (download-all.sh script)
   - Init modes: auto, check, bypass, download

2. **GraphHopper App** (`k8s/apps/graphhopper/`)
   - Version: 11.0 (ghcr.io/simonneutert/graphhopper:11.0)
   - Profiles: car, bike, foot, pt (public transit)
   - PVCs: `graphhopper-data`, `graphhopper-srtm-cache`
   - Shared mounts: `map-data-osm`, `map-data-gtfs` (read-only)

### Deployment Flow

```
1. Map-Data Download Job (map-data-download)
   ├── Downloads OSM PBF files → map-data-osm PVC
   ├── Downloads GTFS feeds → map-data-gtfs PVC
   └── Downloads elevation data → map-data-elevation PVC

2. GraphHopper Initialize Job (graphhopper-initialize)
   ├── wait-for-data initContainer
   │   └── Waits for .data_timestamp files in map-data PVCs
   └── build-graph container
       ├── Creates config.yml with GTFS support
       └── Builds routing graphs → graphhopper-data PVC

3. GraphHopper Deployment (graphhopper)
   └── Serves routing API on port 8989
```

## Cluster Settings

### Local Cluster (Development)

```yaml
# Map-Data
MAP_DATA_FLUX_SUSPEND: "false"
MAP_DATA_INIT_JOB: "auto"
MAP_DATA_OSM_STORAGE_SIZE: "10Gi"
MAP_DATA_GTFS_STORAGE_SIZE: "2Gi"
MAP_DATA_ELEVATION_STORAGE_SIZE: "5Gi"
MAP_DATA_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"

# GraphHopper
GRAPHOPPER_FLUX_SUSPEND: "false"
GRAPHOPPER_REPLICAS: "1"
GRAPHOPPER_STORAGE_SIZE: "20Gi" (currently 10Gi in cluster settings)
GRAPHOPPER_INIT_JOB: "auto"
GRAPHOPPER_BUILD_CPU: "6"
GRAPHOPPER_BUILD_MEMORY: "12Gi"
```

## Critical Fixes Applied (From Previous Sessions)

### 1. Map-Data Permissions
**Fixed**: Job runs as root initially to install packages, then chowns to 1000:1000
**File**: `k8s/apps/map-data/base/job-download.yaml`

### 2. Script References
**Fixed**: ConfigMap now references correct script path `scripts/wait-and-build.sh`
**File**: `k8s/apps/graphhopper/base/kustomization.yaml`

### 3. Memory Conversion
**Fixed**: JVM memory now properly converts Kubernetes format (8Gi) to JVM format (8g)
**File**: `k8s/apps/graphhopper/base/job-initialize.yaml`

### 4. Init Modes
**Fixed**: MAP_DATA_INIT_JOB variable is now read and functional
**File**: `k8s/apps/map-data/base/scripts/download-all.sh`

### 5. Missing Functions
**Fixed**: Added log_error function to wait-and-build.sh
**File**: `k8s/apps/graphhopper/base/scripts/wait-and-build.sh`

## Immediate Action Required

### Fix Corrupted GTFS Storage

The GraphHopper deployment is failing because of a corrupted GTFS database in the PVC. To fix:

```bash
# Option 1: Delete corrupted GTFS database and rebuild
kubectl exec -n production graphhopper-747694fd-hcb5d -- rm -rf /data/gtfs_storage_*

# Option 2: Delete entire graph data and rebuild
kubectl delete pvc graphhopper-data -n production
# Flux will recreate it

# Option 3: Delete everything and start fresh
kubectl delete pvc -n production -l app=graphhopper
kubectl delete pvc -n production -l app=map-data
```

### Redeploy from Scratch

```bash
# 1. Delete all GraphHopper and map-data resources
kubectl delete deployment -n production graphhopper
kubectl delete job -n production -l app=graphhopper
kubectl delete job -n production map-data-download
kubectl delete pvc -n production -l app=graphhopper
kubectl delete pvc -n production -l app=map-data

# 2. Reconcile Flux to recreate resources
flux reconcile kustomization apps --with-source

# 3. Run map-data download job
kubectl create job --from=job/map-data-download map-data-init-$(date +%Y%m%d) -n production
kubectl logs -n production -l job-name=map-data-download -f

# 4. Run GraphHopper initialize job
kubectl create job --from=job/graphhopper-initialize graphhopper-init-$(date +%Y%m%d) -n production
kubectl logs -n production -l job-name=graphhopper-init -c wait-for-data -f
kubectl logs -n production -l job-name=graphhopper-init -c build-graph -f

# 5. Verify deployment
kubectl get pods -n production -l app=graphhopper
kubectl logs -n production deployment/graphhopper -f
```

## File Structure

```
k8s/apps/
├── map-data/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── pvc-osm.yaml
│   │   ├── pvc-gtfs.yaml
│   │   ├── pvc-elevation.yaml
│   │   ├── job-download.yaml
│   │   └── scripts/
│   │       └── download-all.sh
│   ├── overlays/production/
│   │   └── kustomization.yaml
│   └── README.md
│
└── graphhopper/
    ├── base/
    │   ├── kustomization.yaml
    │   ├── pvc.yaml
    │   ├── job-initialize.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── ingress.yaml
    │   └── scripts/
    │       └── wait-and-build.sh
    ├── overlays/production/
    │   └── kustomization.yaml
    └── README.md
```

## Key Configuration Files

### GraphHopper Deployment (`deployment.yaml`)
- Image: `ghcr.io/simonneutert/graphhopper:11.0`
- Replicas: Controlled by `GRAPHOPPER_REPLICAS` cluster setting
- Resources: 250m CPU, 2Gi RAM (requests), 4Gi RAM (limits)
- Health checks: /health endpoint with 5min startup tolerance
- Security: Runs as user 1000:1000, non-root

### GraphHopper Initialize Job (`job-initialize.yaml`)
- Two containers: wait-for-data (debian:12-slim) + build-graph (ghcr.io/simonneutert/graphhopper:11.0)
- Memory conversion: Converts Kubernetes format (12Gi) to JVM format (12g)
- Config generation: Creates config.yml with GTFS/transit support
- Profiles: car, bike, foot, pt

### Map-Data Job (`job-download.yaml`)
- Image: debian:12-slim
- Script: download-all.sh with intelligent caching
- Init modes: auto, check, bypass, download
- Timestamp tracking: Writes .data_timestamp files

## API Endpoints

- **GraphHopper**: `https://routing-gh.burgdev.ch` (or `http://routing-gh.local.burgdev.ch`)
- **Health**: `GET /health`
- **Route**: `POST /route`
- **Info**: `GET /info`
- **Navigate**: `POST /navigate`
- **Isochrone**: `GET /isochrone` (if LM enabled)

## Resource Usage

### Local Cluster (8 CPU, 16GB RAM)
- Map-data download: < 1 CPU, 2GB RAM, 5-15 min
- GraphHopper build: 6 CPU, 12GB RAM, 10-20 min
- GraphHopper service: 0.25-0.5 CPU, 2-4GB RAM

### Storage Requirements
- Map-data PVCs: ~17GB total (10Gi + 2Gi + 5Gi)
- GraphHopper PVCs: ~12GB total (10Gi + 2Gi)
- OSM PBF (Switzerland): ~500MB
- GTFS feeds: ~100MB
- Built graphs: ~3-5GB

## Comparison with Valhalla

| Aspect | GraphHopper | Valhalla |
|--------|-------------|----------|
| **Graph Structure** | Memory-mapped files | Tile-based hierarchy |
| **Profiles** | Separate graphs per mode | Unified graph |
| **Query Speed** | Sub-millisecond (CH) | Millisecond-range |
| **Transit Support** | GTFS via pt module | Built-in GTFS |
| **Storage** | 10-15 GB (Alps) | 15-20 GB (Alps) |
| **Build Time** | 10-30 min (CH) | 10-30 min |
| **Memory** | 2-4 GB (CH) | 2-4 GB |

## Troubleshooting Guide

### Map-Data Job Fails
```bash
# Check logs
kubectl logs -n production -l job-name=map-data-download

# Common issues:
# - Network timeout: Script retries automatically
# - Invalid URLs: Check MAP_DATA_OSM_URLS in cluster settings
# - Permission errors: Fixed (runs as root initially)
# - Init mode: Check MAP_DATA_INIT_JOB setting
```

### GraphHopper Initialize Job Fails
```bash
# Check wait-for-data logs
kubectl logs -n production -l job-name=graphhopper-init -c wait-for-data

# Check build-graph logs
kubectl logs -n production -l job-name=graphhopper-init -c build-graph

# Common issues:
# - Data not ready: Check map-data job completed
# - OOM killed: Use local cluster (more memory)
# - Invalid config: Check wait-and-build.sh script
# - Memory conversion: Check logs for "JVM memory:" line
```

### GraphHopper Deployment Crashes
```bash
# Check logs
kubectl logs -n production deployment/graphhopper

# Common issues:
# - Corrupted GTFS storage: Delete /data/gtfs_storage_* files
# - Missing graph: Re-run initialize job
# - Missing config: Re-run initialize job
# - Permission errors: Check securityContext (1000:1000)
# - PVC mount issues: Check PVC status
```

### Corrupted GTFS Database (Current Issue)
```bash
# Error: Wrong index checksum, store was not closed properly

# Solution 1: Delete GTFS storage only
kubectl delete pvc -n production graphhopper-data
kubectl create job --from=job/graphhopper-initialize graphhopper-rebuild-$(date +%Y%m%d) -n production

# Solution 2: Delete everything and redeploy (see "Redeploy from Scratch" above)
```

## Best Practices

### Resource Limits
- **DO NOT** set CPU limits (only requests)
- **ALWAYS** set memory limits to prevent node OOM
- Build jobs: Tight limits (8-12Gi)
- Services: Allow headroom (1.5-2× requests)

### Init Modes
- **Development** (`auto`): Download/build if missing
- **Testing** (`check`): Verify data exists, fail if missing
- **Production** (`bypass`): Use copied data from dev cluster

### Updates
- Run updates on local cluster (more resources)
- Copy built data to burginfra cluster
- Use `bypass` mode on burginfra to skip builds

## Future Enhancements

- [ ] Fix corrupted GTFS storage issue
- [ ] Add automated monthly updates via CronJob
- [ ] Add Prometheus metrics and Grafana dashboards
- [ ] Implement horizontal pod autoscaling
- [ ] Add SRTM elevation data support
- [ ] Enable Landmarks (LM) for alternative queries
- [ ] Deploy to burginfra cluster after testing
- [ ] Add API authentication/rate limiting

## Related Documentation

- **Original Implementation**: `GRAPHHOPPER_IMPLEMENTATION.md` (archived)
- **Critical Fixes**: `GRAPHHOPPER_FIXES.md` (archived)
- **Map-Data Implementation**: `MAP_DATA_IMPLEMENTATION.md` (archived)
- **Setup Improvements**: `SETUP_IMPROVEMENTS.md` (archived)
- **Implementation Complete**: `IMPLEMENTATION_COMPLETE.md` (archived)

## Additional Resources

- [GraphHopper Documentation](https://docs.graphhopper.com/)
- [GraphHopper GitHub](https://github.com/graphhopper/graphhopper)
- [GraphHopper API Examples](https://github.com/graphhopper/graphhopper/blob/master/docs/web/api.md)
- [OSM Data Sources](https://download.geofabrik.de/)

---

**Status**: 🔴 Critical Issues - Deployment failing due to corrupted GTFS storage
**Last Updated**: 2026-01-16
**Next Action**: Redeploy from scratch (see "Immediate Action Required" section)
