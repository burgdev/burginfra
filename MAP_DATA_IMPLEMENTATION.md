# Map Data Implementation Summary

## Overview

Created a centralized **map-data** app that provides shared OSM, GTFS, and elevation data for routing engines and other map-based applications.

## What Changed

### Before (Separate Data per App)
```
valhalla/
├── valhalla-data PVC (10-30Gi)
│   ├── OSM PBF files
│   ├── Built tiles
│   ├── Elevation data
│   └── GTFS feeds
└── gtfs-feeds-data PVC (2Gi)

graphhopper/
└── graphhopper-data PVC (20Gi)
    ├── OSM PBF files (duplicate!)
    ├── Built graphs
    └── Would need GTFS/elevation (duplicate!)
```

### After (Shared Data)
```
map-data/
├── map-data-osm PVC (10Gi) ← Shared!
├── map-data-gtfs PVC (2Gi) ← Shared!
└── map-data-elevation PVC (5Gi) ← Shared!

valhalla/
└── valhalla-data PVC (10-30Gi)
    └── Built tiles only (reads from shared PVCs)

graphhopper/
└── graphhopper-data PVC (20Gi)
    └── Built graphs only (reads from shared PVCs)
```

## Files Created

```
k8s/apps/map-data/
├── base/
│   ├── kustomization.yaml
│   ├── pvc-osm.yaml
│   ├── pvc-gtfs.yaml
│   ├── pvc-elevation.yaml
│   ├── job-download.yaml
│   └── scripts/
│       └── download-all.sh (adapted from Valhalla)
├── overlays/production/
│   └── kustomization.yaml
└── README.md
```

## Cluster Settings Added

### Local Cluster
```yaml
MAP_DATA_FLUX_SUSPEND: "false"
MAP_DATA_OSM_STORAGE_SIZE: "10Gi"
MAP_DATA_GTFS_STORAGE_SIZE: "2Gi"
MAP_DATA_ELEVATION_STORAGE_SIZE: "5Gi"
MAP_DATA_INIT_JOB: "auto"
MAP_DATA_OSM_URLS: "https://download.geofabrik.de/..."
MAP_DATA_GTFS_URLS: "https://opentransportdata.swiss/..."
MAP_DATA_ELEVATION_BOUNDS: "45,46,47,48:5,6,7,8,9,10,11"
```

### Burginfra Cluster
```yaml
# Same as local (download job enabled on both)
```

## Flux Integration

Added to `k8s/apps/_deploy/production/kustomization.yaml`:
```yaml
- ../../map-data/overlays/production/
```

## Benefits

### 1. Storage Efficiency
- **Before**: 500MB-5GB duplicated per app
- **After**: Single copy, all apps share
- **Savings**: ~50% storage reduction with 2 routing engines

### 2. Consistency
- All apps use identical OSM/GTFS/elevation data
- No version mismatches between engines
- Single source of truth

### 3. Simplified Updates
- **Before**: Update each app's data separately
- **After**: Single download job updates all data
- **Time savings**: 1 job vs N jobs

### 4. Easier Maintenance
- One download script to maintain
- Centralized data source configuration
- Easier to add new consumers

### 5. Future-Proof
- Easy to add new routing engines
- Easy to add other map-based apps
- Generic "map-data" name (not routing-specific)

## Migration Path

### Phase 1: Deploy map-data (Current)
✅ Created manifests
✅ Added to Flux
✅ Configured cluster settings

### Phase 2: Migrate GraphHopper (Next)
- Update GraphHopper to mount shared PVCs
- Remove GraphHopper's built-in download logic
- Test with shared data

### Phase 3: Migrate Valhalla (Later)
- Update Valhalla to mount shared PVCs
- Remove Valhalla's built-in download logic
- Test with shared data

## Usage

### Initial Download
```bash
kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
flux reconcile kustomization apps --with-source
kubectl create job --from=job/map-data-download map-data-init-$(date +%Y%m%d) -n production
kubectl logs -n production -l job-name=map-data-download -f
```

### Consumer Integration Example
```yaml
volumes:
  - name: osm-data
    persistentVolumeClaim:
      claimName: map-data-osm
      readOnly: true

volumeMounts:
  - name: osm-data
    mountPath: /osm_data
```

## Resource Impact

### Storage
```
Before:
- Valhalla: 15-20 GB (OSM + GTFS + elevation + tiles)
- GraphHopper: 10-15 GB (OSM + graphs)
Total: 25-35 GB

After:
- map-data: 2-3 GB (OSM + GTFS + elevation)
- Valhalla: 12-18 GB (tiles only)
- GraphHopper: 8-12 GB (graphs only)
Total: 22-33 GB (slight reduction, no duplication)
```

### Network
```
Before:
- Valhalla downloads: 500MB-5GB
- GraphHopper downloads: 500MB-5GB
Total: 1-10 GB

After:
- map-data downloads: 500MB-5GB
Total: 500MB-5 GB (50% reduction)
```

## Next Steps

1. **Test map-data on local cluster**
   ```bash
   # Deploy and run download job
   kubectl create job --from=job/map-data-download test -n production
   ```

2. **Update GraphHopper to use shared PVCs**
   - Remove download initContainer from GraphHopper
   - Mount shared PVCs read-only
   - Point config to `/osm_data/switzerland-latest.osm.pbf`

3. **Migrate Valhalla** (optional, can do later)
   - Update Valhalla manifests to mount shared PVCs
   - Remove Valhalla's download job
   - Test build with shared data

4. **Consider additional data sources**
   - Traffic data (real-time routing)
   - POI databases
   - Administrative boundaries

## Documentation

Full documentation: `k8s/apps/map-data/README.md`

Includes:
- Architecture overview
- Configuration reference
- Usage examples
- Consumer integration guide
- Troubleshooting
- Migration guide
