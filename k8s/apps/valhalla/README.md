# Valhalla Routing Engine

Open-source routing engine for OpenStreetMap data with support for transit, elevation, and multiple routing profiles.

## Features

- **Multi-modal routing**: Car, bike, pedestrian, public transit
- **Elevation profiles**: Accurate elevation data for routes
- **Transit integration**: GTFS-based public transport routing
- **Isochrones**: Time/distance contour calculations
- **Map matching**: Snap GPS traces to road network

## Architecture

### Three-Phase Deployment

1. **Download Job** (`job-download.yaml`)
   - Downloads OSM PBF data from Geofabrik
   - Downloads GTFS transit feeds
   - Downloads SRTM elevation data (HGT format)
   - Merges multiple PBF files using osmium-tool
   - Lightweight Alpine containers

2. **Build Job** (`job-build.yaml`)
   - Builds routing tiles from OSM data
   - Processes elevation data
   - Builds admin/timezone databases
   - Processes transit GTFS feeds
   - Creates compressed tile tarball
   - Resource-intensive (4 CPU, 8GB RAM)

3. **Service Deployment** (`deployment.yaml`)
   - Runs Valhalla API server
   - Serves routing requests via HTTP
   - Uses pre-built tiles from PVC
   - Lightweight (1 CPU, 2GB RAM)

## Configuration

Configured via cluster settings in `k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml`:

```yaml
# Storage
VALHALLA_STORAGE_SIZE: "10Gi"  # Increase to 30Gi for Alps region

# OSM Data (comma-separated URLs)
VALHALLA_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
# For Alps: "https://.../switzerland.pbf,https://.../france.pbf,..."

# GTFS Transit Data (comma-separated URLs)
VALHALLA_GTFS_URLS: "https://opentransportdata.swiss/de/dataset/timetable-2025-gtfs2020/permalink"

# Elevation Data (lat_range:lon_range)
VALHALLA_ELEVATION_BOUNDS: "45,46,47,48:5,6,7,8,9,10,11"  # Switzerland
# For Alps: "44,45,46,47,48:4,5,6,7,8,9,10,11,12,13,14,15"
```

**IMPORTANT:** After changing cluster_settings.yaml, manually apply:
```bash
kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
```

## Deployment

### Initial Deployment

The download and build jobs are included in the kustomization but won't automatically run.

1. **Apply cluster settings** (if changed):
   ```bash
   kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
   ```

2. **Flux will create the namespace, PVC, and service deployment**
   ```bash
   flux reconcile kustomization apps --with-source
   ```

3. **Manually trigger the download job**:
   ```bash
   kubectl create job --from=job/valhalla-download valhalla-download-$(date +%Y%m%d-%H%M%S) -n valhalla-production
   ```

4. **Monitor download progress**:
   ```bash
   kubectl logs -n valhalla-production -l job=download -f
   ```

5. **Once download completes, trigger build job**:
   ```bash
   kubectl create job --from=job/valhalla-build valhalla-build-$(date +%Y%m%d-%H%M%S) -n valhalla-production
   ```

6. **Monitor build progress** (10-30 minutes):
   ```bash
   kubectl logs -n valhalla-production -l job=build -f
   ```

7. **Restart service to load new tiles**:
   ```bash
   kubectl rollout restart deployment/valhalla -n valhalla-production
   ```

### Updating Data

#### Monthly OSM Updates

```bash
# Re-run download job
kubectl create job --from=job/valhalla-download valhalla-download-$(date +%Y%m%d) -n valhalla-production

# Wait for completion, then re-run build
kubectl create job --from=job/valhalla-build valhalla-build-$(date +%Y%m%d) -n valhalla-production

# Restart service
kubectl rollout restart deployment/valhalla -n valhalla-production
```

#### Weekly Transit Updates

GTFS data updates twice weekly (Tue/Fri). To update:

```bash
# Re-download only (faster than full download)
kubectl create job --from=job/valhalla-download valhalla-gtfs-$(date +%Y%m%d) -n valhalla-production

# Re-build tiles
kubectl create job --from=job/valhalla-build valhalla-build-$(date +%Y%m%d) -n valhalla-production

# Restart service
kubectl rollout restart deployment/valhalla -n valhalla-production
```

#### Expanding to Alps Region

1. Update cluster settings:
   ```yaml
   VALHALLA_STORAGE_SIZE: "30Gi"
   VALHALLA_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf,https://download.geofabrik.de/europe/france-latest.osm.pbf,https://download.geofabrik.de/europe/austria-latest.osm.pbf,https://download.geofabrik.de/europe/germany-latest.osm.pbf,https://download.geofabrik.de/europe/italy-latest.osm.pbf"
   VALHALLA_ELEVATION_BOUNDS: "44,45,46,47,48:4,5,6,7,8,9,10,11,12,13,14,15"
   ```

2. Apply settings:
   ```bash
   kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
   ```

3. Resize PVC:
   ```bash
   kubectl patch pvc valhalla-data -n valhalla-production -p '{"spec":{"resources":{"requests":{"storage":"30Gi"}}}}'
   ```

4. Run download and build jobs as above

## API Endpoints

Available at `https://routing.wodore.com`:

- `GET /status` - Health check
- `POST /route` - Point-to-point routing
- `POST /optimized_route` - Multi-point route optimization
- `POST /isochrone` - Time/distance contours
- `POST /locate` - Snap coordinates to network
- `POST /matrix` - Distance matrix

See [Valhalla API documentation](https://valhalla.github.io/valhalla/api/) for details.

## Troubleshooting

### Job Failures

**Download job fails:**
```bash
# Check logs
kubectl logs -n valhalla-production -l job=download --tail=100

# Common issues:
# - Network timeout: Increase job timeout
# - Invalid URLs: Check cluster settings
# - Out of disk space: Increase VALHALLA_STORAGE_SIZE
```

**Build job fails (OOM killed):**
```bash
# Check if killed by OOM
kubectl describe pod -n valhalla-production -l job=build

# Solutions:
# 1. Reduce BUILD_THREADS in job-build.yaml
# 2. Build smaller regions separately
# 3. Increase job memory limits (requires more cluster RAM)
```

### Service Issues

**Service not starting:**
```bash
# Check if tiles exist
kubectl exec -n valhalla-production deployment/valhalla -- ls -lh /custom_files/

# Check service logs
kubectl logs -n valhalla-production deployment/valhalla

# Common issues:
# - Missing valhalla.json: Re-run build job
# - Missing tiles.tar: Re-run build job
# - Permission errors: Check fsGroup in deployment
```

**Slow routing requests:**
```bash
# Check memory usage
kubectl top pod -n valhalla-production

# Solutions:
# - Increase service memory limits
# - Reduce concurrent requests
# - Build with fewer road classes (config change)
```

## Resource Usage

### Current (Switzerland Only)

- **Storage**: ~3-5 GB
- **Build**: 4 CPU, 8GB RAM, 10-20 minutes
- **Service**: 1 CPU, 2GB RAM

### Future (Alps Region)

- **Storage**: ~15-20 GB
- **Build**: 4 CPU, 8GB RAM, 30-60 minutes
- **Service**: 2 CPU, 4GB RAM

## Data Sources

- **OSM Data**: [Geofabrik](https://download.geofabrik.de/)
- **Transit (CH)**: [Open Transport Data Switzerland](https://opentransportdata.swiss/)
- **Elevation**: [Viewfinder Panoramas](http://viewfinderpanoramas.org/dem3.html) (SRTM with voids filled)

## Future Enhancements

- [ ] Use swissALTI3D for higher accuracy elevation (0.5m vs 30m)
- [ ] Add CronJob for automated monthly updates
- [ ] Implement horizontal pod autoscaling for service
- [ ] Add Prometheus metrics and Grafana dashboards
- [ ] Configure traffic data for real-time routing
