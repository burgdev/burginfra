# GraphHopper Implementation Summary

## Overview

GraphHopper routing engine has been successfully added to the burginfra Kubernetes cluster, running alongside the existing Valhalla routing engine. Both engines share the same OSM PBF data source but maintain independent storage and routing graphs.

## Architecture Decisions

### 1. Separate PVCs
- **Valhalla**: `valhalla-data` (10-30Gi) + `gtfs-feeds-data` (2Gi)
- **GraphHopper**: `graphhopper-data` (20Gi)
- **Rationale**: Clean separation, independent updates, matches existing pattern

### 2. Build-on-Local, Copy-to-Production Strategy
- **Local cluster**: Build graphs with more resources (6 CPU, 12GB RAM)
- **Burginfra cluster**: Copy pre-built graphs via temporary pods
- **Rationale**: Protects production VPS from OOM during builds

### 3. Initial Coverage: Switzerland
- Start with Switzerland only (3-5 GB)
- Can expand to Alps region later (10-15 GB)
- Both engines configured identically for comparison

## Resource Allocation

### Local Cluster (Development)
```
Valhalla build:  8 CPU, 14GB RAM, 10-20 min
GraphHopper build: 6 CPU, 12GB RAM, 10-20 min
Total: ~30-40 min sequential
```

### Burginfra Cluster (Production - 8 CPU, 16GB RAM)
```
Steady State:
  Valhalla service:    1 CPU, 2GB RAM
  GraphHopper service: 0.5 CPU, 2GB RAM
  System overhead:     1 CPU, 2GB RAM
  Available:          5.5 CPU, 10GB RAM
```

## Files Created

```
k8s/apps/graphhopper/
├── base/
│   ├── kustomization.yaml          # Kustomize base config
│   ├── pvc.yaml                     # GraphHopper data PVC (20Gi)
│   ├── job-initialize.yaml          # Download + build job
│   ├── deployment.yaml              # GraphHopper service deployment
│   ├── service.yaml                 # ClusterIP service (port 8989)
│   ├── ingress.yaml                 # routing-gh.burgdev.ch
│   └── scripts/
│       └── download-and-build.sh    # OSM download and graph build script
├── overlays/
│   └── production/
│       └── kustomization.yaml       # Production overlay
└── README.md                        # Comprehensive documentation
```

## Cluster Settings Added

### Local Cluster
```yaml
GRAPHOPPER_FLUX_SUSPEND: "false"
GRAPHOPPER_REPLICAS: "1"
GRAPHOPPER_STORAGE_SIZE: "20Gi"
GRAPHOPPER_INIT_JOB: "auto"
GRAPHOPPER_BUILD_CPU: "6"
GRAPHOPPER_BUILD_MEMORY: "12Gi"
GRAPHOPPER_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
```

### Burginfra Cluster
```yaml
GRAPHOPPER_FLUX_SUSPEND: "true"   # Initially disabled
GRAPHOPPER_REPLICAS: "0"
GRAPHOPPER_STORAGE_SIZE: "20Gi"
GRAPHOPPER_INIT_JOB: "bypass"     # Use copied data
GRAPHOPPER_BUILD_CPU: "3"
GRAPHOPPER_BUILD_MEMORY: "8Gi"
GRAPHOPPER_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
```

## API Endpoints

- **Valhalla**: `https://routing.burgdev.ch`
- **GraphHopper**: `https://routing-gh.burgdev.ch`

## Deployment Steps

### 1. Deploy to Local Cluster

```bash
# Apply cluster settings
kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml

# Reconcile Flux
flux reconcile kustomization apps --with-source

# Trigger initialize job
kubectl create job --from=job/graphhopper-initialize graphhopper-init-$(date +%Y%m%d) -n production

# Monitor logs
kubectl logs -n production -l job-name=graphhopper-init -c download-osm -f
kubectl logs -n production -l job-name=graphhopper-init -c build-graph -f
```

### 2. Deploy to Burginfra Cluster

```bash
# On local: Build graphs
# (See step 1)

# Copy data to burginfra (follow README instructions)

# Apply cluster settings on burginfra
kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml

# Update replicas to 1 in cluster settings, then apply
kubectl rollout restart deployment/graphhopper -n production
```

## Key Differences from Valhalla

| Aspect | Valhalla | GraphHopper |
|--------|----------|-------------|
| **Output** | Tile tarball | Memory-mapped graph files |
| **Structure** | Hierarchical tiles | Flat graph directory |
| **Jobs** | Download + Build (separate containers in same job) | Download + Build (same pattern) |
| **Profiles** | Unified graph | Separate graphs per profile |
| **Storage** | 15-20 GB (Alps) | 10-15 GB (Alps) |
| **Transit** | Built-in GTFS support | Via public transit module |
| **Init Modes** | auto, download, check, bypass | auto, download, build, bypass |

## Next Steps

1. **Test on local cluster**:
   - Deploy and build GraphHopper
   - Verify API endpoints
   - Compare routing results with Valhalla

2. **Deploy to burginfra**:
   - Build on local cluster
   - Copy graphs to production
   - Enable service with `GRAPHOPPER_REPLICAS: "1"`

3. **Optional enhancements**:
   - Add SRTM elevation data
   - Enable Landmarks (LM) for alternative queries
   - Add automated monthly updates via CronJob
   - Add Prometheus metrics

## Documentation

See `k8s/apps/graphhopper/README.md` for comprehensive documentation including:
- Detailed architecture explanation
- Configuration options
- Troubleshooting guide
- Data copying instructions
- API usage examples
- Performance tuning tips

## Flux Integration

GraphHopper is now included in the Flux production bundle:
- File: `k8s/apps/_deploy/production/kustomization.yaml`
- Syncs automatically when committed to git
- Initially suspended on burginfra cluster

## Status

✅ Complete implementation
✅ Cluster settings configured
✅ Flux integration added
✅ Comprehensive documentation created
⏳ Pending deployment to local cluster for testing
⏳ Pending deployment to burginfra cluster after testing
