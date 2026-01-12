# Map Data Downloader

Shared OSM, GTFS, and elevation data downloader for routing engines and other map-based applications.

## Overview

This app provides a centralized data download service that fetches and maintains:
- **OSM PBF files**: OpenStreetMap data for routing engines
- **GTFS feeds**: Public transport schedule data
- **SRTM elevation data**: Terrain elevation for routing

Data is stored in separate PVCs that can be mounted by any application that needs it:
- Valhalla (routing engine)
- GraphHopper (routing engine)
- Future routing or map-based services

## Architecture

### Shared PVCs

Three separate PVCs are created, each optimized for its data type:

```
map-data-osm (10Gi)
├── switzerland-latest.osm.pbf
└── merged.osm.pbf (if multiple regions)

map-data-gtfs (2Gi)
└── feed_1/
    ├── gtfs.zip
    ├── stops.txt
    ├── routes.txt
    └── ...

map-data-elevation (5Gi)
└── N47/
    ├── N47E008.hgt
    ├── N47E009.hgt
    └── ...
```

### Download Job

A single Job (`map-data-download`) downloads all three data types:

1. **OSM Data**: Downloads PBF files from Geofabrik, merges if needed
2. **GTFS Data**: Downloads and extracts transit feeds
3. **Elevation Data**: Downloads SRTM HGT tiles from AWS S3 or Viewfinder Panoramas

Features:
- **Intelligent caching**: Uses ETag/Last-Modified headers to avoid re-downloading unchanged files
- **Automatic retry**: Sleeps on error and continues
- **Multi-region support**: Can merge multiple PBF files
- **Permission management**: Sets ownership to 1000:1000 for routing engines

## Configuration

Configured via cluster settings in `k8s/clusters/flux-system/overlays/{local|burginfra}/cluster_settings.yaml`:

### Local Cluster

```yaml
MAP_DATA_FLUX_SUSPEND: "false"
MAP_DATA_OSM_STORAGE_SIZE: "10Gi"
MAP_DATA_GTFS_STORAGE_SIZE: "2Gi"
MAP_DATA_ELEVATION_STORAGE_SIZE: "5Gi"
MAP_DATA_INIT_JOB: "auto"
MAP_DATA_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
MAP_DATA_GTFS_URLS: "https://data.opentransportdata.swiss/..."
MAP_DATA_ELEVATION_BOUNDS: "45,46,47,48:5,6,7,8,9,10,11"
```

### Burginfra Cluster

```yaml
MAP_DATA_FLUX_SUSPEND: "false" # Download job enabled
MAP_DATA_OSM_STORAGE_SIZE: "10Gi"
MAP_DATA_GTFS_STORAGE_SIZE: "2Gi"
MAP_DATA_ELEVATION_STORAGE_SIZE: "5Gi"
MAP_DATA_INIT_JOB: "auto"
# ... (same URLs as local)
```

### Init Job Modes

- **`auto`**: Download data if it doesn't exist (default)
- **`download`**: Always download/re-download all data

## Usage

### Initial Download

```bash
# Apply cluster settings
kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml

# Reconcile Flux to create resources
flux reconcile kustomization apps --with-source

# Trigger download job
kubectl create job --from=job/map-data-download map-data-download-$(date +%Y%m%d) -n production

# Monitor progress
kubectl logs -n production -l job-name=map-data-download -f
```

### Updating Data

#### Monthly OSM Updates

```bash
# Re-run download job
kubectl create job --from=job/map-data-download map-data-update-$(date +%Y%m%d) -n production
```

The script will automatically skip unchanged files using ETag headers.

#### Weekly GTFS Updates

GTFS data updates twice weekly (Tue/Fri). Same command as above - the script handles caching.

#### Expanding Coverage

To add more regions (e.g., expand from Switzerland to Alps):

1. Update cluster settings:
   ```yaml
   MAP_DATA_OSM_URLS: "https://...switzerland.pbf,https://...france.pbf,https://...austria.pbf"
   MAP_DATA_ELEVATION_BOUNDS: "44,45,46,47,48:4,5,6,7,8,9,10,11,12,13,14,15"
   ```

2. Resize PVCs if needed:
   ```bash
   kubectl patch pvc map-data-osm -n production -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
   ```

3. Re-run download job

## Consumer Integration

Applications can mount these PVCs read-only to access the data:

### Example: Valhalla

```yaml
volumes:
  - name: osm-data
    persistentVolumeClaim:
      claimName: map-data-osm
      readOnly: true
  - name: gtfs-data
    persistentVolumeClaim:
      claimName: map-data-gtfs
      readOnly: true
  - name: elevation-data
    persistentVolumeClaim:
      claimName: map-data-elevation
      readOnly: true

volumeMounts:
  - name: osm-data
    mountPath: /osm_data
  - name: gtfs-data
    mountPath: /gtfs_data
  - name: elevation-data
    mountPath: /elevation_data
```

### Example: GraphHopper

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

## Data Sources

- **OSM**: [Geofabrik](https://download.geofabrik.de/) (updated daily)
- **GTFS**: [Open Transport Data Switzerland](https://opentransportdata.swiss/) (updated Tue/Fri)
- **Elevation**: [NASA SRTM via AWS S3](https://elevation-tiles-prod.s3.amazonaws.com/) with [Viewfinder Panoramas](http://viewfinderpanoramas.org/dem3.html) fallback

## Troubleshooting

### Download Fails

```bash
# Check logs
kubectl logs -n production -l job-name=map-data-download --tail=100

# Common issues:
# - Network timeout: Script retries automatically
# - Invalid URLs: Check MAP_DATA_* settings
# - Out of disk space: Increase PVC sizes
# - Permission errors: Check securityContext
```

### PVCs Not Created

```bash
# Check PVC status
kubectl get pvc -n production | grep map-data

# Manual creation if needed
kubectl apply -f k8s/apps/map-data/base/pvc-*.yaml
```

### Data Not Updating

```bash
# Check if files are up-to-date
kubectl exec -n production <any-pod-using-pvc> -- ls -lh /osm_data/

# Force re-download by changing init mode
# Edit cluster settings: MAP_DATA_INIT_JOB: "download"
# Re-run job
```

## Storage Requirements

### Current (Switzerland Only)

- **OSM**: ~500 MB (single PBF)
- **GTFS**: ~100-200 MB (zip + extracted)
- **Elevation**: ~1-2 GB (30-50 HGT tiles)
- **Total**: ~2-3 GB

### Future (Alps Region)

- **OSM**: ~5-8 GB (merged PBF)
- **GTFS**: ~500 MB-1 GB (multiple feeds)
- **Elevation**: ~4-6 GB (200-300 HGT tiles)
- **Total**: ~10-15 GB

## Migration Notes

### Migrating Valhalla

Valhalla currently has its own PVCs and download logic. To migrate:

1. Deploy map-data app
2. Run download job to populate shared PVCs
3. Update Valhalla manifests to mount shared PVCs
4. Remove Valhalla's own PVCs and download job
5. Test Valhalla build with shared data

### Migrating GraphHopper

GraphHopper was just created and should directly use shared PVCs - no migration needed.

## Benefits of Centralized Data

1. **Storage Efficiency**: Download once, use multiple times
2. **Consistency**: All apps use identical data
3. **Simplified Updates**: Single job updates all data
4. **Easier Maintenance**: One download script to maintain
5. **Flexibility**: Easy to add new consumers

## Future Enhancements

- [ ] Add S3 backup/restore capability
- [ ] Implement data versioning
- [ ] Add automatic update scheduling via CronJob
- [ ] Create data validation checks
- [ ] Add Prometheus metrics for download status
- [ ] Implement differential updates for OSM data

## Related Documentation

- [Valhalla README](../valhalla/README.md) - Valhalla routing engine
- [GraphHopper README](../graphhopper/README.md) - GraphHopper routing engine
