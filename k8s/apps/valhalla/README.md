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

# Init Job Mode (controls download behavior)
VALHALLA_INIT_JOB: "auto"  # Options: download|auto|check|bypass

# OSM Data (comma-separated URLs)
VALHALLA_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
# For Alps: "https://.../switzerland.pbf,https://.../france.pbf,..."

# GTFS Transit Data (comma-separated URLs)
VALHALLA_GTFS_URLS: "https://opentransportdata.swiss/de/dataset/timetable-2025-gtfs2020/permalink"

# Elevation Data (lat_range:lon_range)
VALHALLA_ELEVATION_BOUNDS: "45,46,47,48:5,6,7,8,9,10,11"  # Switzerland
# For Alps: "44,45,46,47,48:4,5,6,7,8,9,10,11,12,13,14,15"
```

### Init Job Modes

The `VALHALLA_INIT_JOB` variable controls how both the download and build jobs behave:

- **`download`**: Always download/build all data, overwriting existing files
- **`auto`**: Download/build only if files don't exist, otherwise skip (default for local cluster)
- **`check`**: Only verify that required files exist, fail if missing (useful for validation)
- **`bypass`**: Skip all checks, downloads, and builds - assume data already exists (default for production cluster)

**Recommended workflow**:

1. Run download and build jobs on your **local cluster** (more memory, less critical)
2. Copy the built PVC data to **production cluster**
3. Use `bypass` mode on production to skip resource-intensive operations

This protects your production cluster from OOM issues during data processing.

**IMPORTANT:** After changing cluster_settings.yaml, manually apply:

```bash
kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
```

## Deployment

### Initial Deployment

The download and build jobs are included in the kustomization but won't automatically run. **Run these on your local cluster first**, then copy data to production.

#### On Local Cluster

1. **Apply cluster settings** (if changed):

   ```bash
   kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
   ```

2. **Flux will create the namespace, PVC, and jobs**

   ```bash
   flux reconcile kustomization apps --with-source
   ```

3. **Manually trigger the download job**:

   ```bash
   kubectl create job --from=job/valhalla-download valhalla-download-$(date +%Y%m%d-%H%M%S) -n production
   ```

4. **Monitor download progress**:

   ```bash
   kubectl logs -n production -l job=download -f
   ```

5. **Once download completes, trigger build job**:

   ```bash
   kubectl create job --from=job/valhalla-build valhalla-build-$(date +%Y%m%d-%H%M%S) -n production
   ```

6. **Monitor build progress** (10-30 minutes):

   ```bash
   kubectl logs -n production -l job=build -f
   ```

7. **Verify service is running**:

   ```bash
   kubectl get pods -n production -l app=valhalla
   ```

#### On Production Cluster

See "Copying Data Between Clusters" section below to transfer the built data to production.

### Updating Data

**Important**: Run updates on local cluster first, then copy to production.

#### Monthly OSM Updates

```bash
# On local cluster: Re-run download job
kubectl create job --from=job/valhalla-download valhalla-download-$(date +%Y%m%d) -n production

# Wait for completion, then re-run build
kubectl create job --from=job/valhalla-build valhalla-build-$(date +%Y%m%d) -n production

# Copy updated data to production cluster (see "Copying Data Between Clusters")

# On production cluster: Restart service
kubectl rollout restart deployment/valhalla -n production
```

#### Weekly Transit Updates

GTFS data updates twice weekly (Tue/Fri). To update:

```bash
# On local cluster: Re-download and rebuild
kubectl create job --from=job/valhalla-download valhalla-gtfs-$(date +%Y%m%d) -n production
kubectl create job --from=job/valhalla-build valhalla-build-$(date +%Y%m%d) -n production

# Copy updated data to production cluster

# On production cluster: Restart service
kubectl rollout restart deployment/valhalla -n production
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
   kubectl patch pvc valhalla-data -n production -p '{"spec":{"resources":{"requests":{"storage":"30Gi"}}}}'
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
kubectl logs -n production -l job=download --tail=100

# Common issues:
# - Network timeout: Increase job timeout
# - Invalid URLs: Check cluster settings
# - Out of disk space: Increase VALHALLA_STORAGE_SIZE
# - Init mode: Check VALHALLA_INIT_JOB setting
```

**Build job fails (OOM killed):**

```bash
# Check if killed by OOM
kubectl describe pod -n production -l job=build

# Solutions:
# 1. Use local cluster for builds (more memory available)
# 2. Reduce server_threads in job-build.yaml (currently 2)
# 3. Build smaller regions separately
# 4. Use bypass mode on production and copy pre-built data
```

**Jobs skip execution unexpectedly:**

```bash
# Check init job mode
kubectl get configmap -n flux-system cluster-settings -o yaml | grep VALHALLA_INIT_JOB

# If mode is "bypass" or "check", jobs will skip if data exists
# Change to "auto" or "download" to force execution
```

### Service Issues

**Service not starting:**

```bash
# Check if tiles exist
kubectl exec -n production deployment/valhalla -- ls -lh /custom_files/

# Check service logs
kubectl logs -n production deployment/valhalla

# Common issues:
# - Missing valhalla.json: Re-run build job or copy from local cluster
# - Missing tiles.tar: Re-run build job or copy from local cluster
# - Permission errors: Check fsGroup in deployment (should be 1000)
# - PVC mount issues: Check PVC status
```

**Slow routing requests:**

```bash
# Check memory usage
kubectl top pod -n production

# Solutions:
# - Increase service memory limits
# - Reduce concurrent requests
# - Build with fewer road classes (requires config change)
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

## Copying Data Between Clusters

To avoid running memory-intensive init jobs on production, build data on your local cluster and copy it to production.

### 1. Build on Local Cluster

```bash
# Ensure local cluster has VALHALLA_INIT_JOB: "auto" (default)
kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml

# Run download and build jobs (see Initial Deployment section)
kubectl create job --from=job/valhalla-download valhalla-download-$(date +%Y%m%d) -n production
kubectl create job --from=job/valhalla-build valhalla-build-$(date +%Y%m%d) -n production
```

### 2. Copy Data to Production

```bash
# On LOCAL cluster: Create temporary pod to access PVC
KUBECONFIG=~/.kube/config-localhost kubectl run -n production valhalla-copy \
  --image=alpine:latest --restart=Never --command -- sleep 3600

# Wait for pod to be ready
KUBECONFIG=~/.kube/config-localhost kubectl wait --for=condition=Ready pod/valhalla-copy -n production --timeout=60s

# Copy data from local cluster to your machine
KUBECONFIG=~/.kube/config-localhost kubectl cp production/valhalla-copy:/custom_files ./valhalla-data

# On PRODUCTION cluster: Create temporary pod
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl run -n production valhalla-copy \
  --image=alpine:latest --restart=Never --command -- sleep 3600

# Wait for pod to be ready
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl wait --for=condition=Ready pod/valhalla-copy -n production --timeout=60s

# Copy data from your machine to production cluster
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl cp ./valhalla-data production/valhalla-copy:/custom_files

# Cleanup both clusters
KUBECONFIG=~/.kube/config-localhost kubectl delete pod -n production valhalla-copy
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl delete pod -n production valhalla-copy
rm -rf ./valhalla-data
```

### 3. Use Bypass Mode on Production

Ensure `VALHALLA_INIT_JOB: "bypass"` in production cluster settings to skip init jobs entirely:

```bash
# Verify setting in k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
# VALHALLA_INIT_JOB: "bypass"

# Apply if changed
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
```

## Future Enhancements

- [ ] Use swissALTI3D for higher accuracy elevation (0.5m vs 30m)
- [ ] Consider [planetutils](https://github.com/interline-io/planetutils) for faster planet-scale OSM processing
- [ ] Add CronJob for automated monthly updates
- [ ] Implement horizontal pod autoscaling for service
- [ ] Add Prometheus metrics and Grafana dashboards
- [ ] Configure traffic data for real-time routing
