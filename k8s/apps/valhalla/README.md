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

1. **Download Job** (initContainer in `job-initialize.yaml`)
   - Downloads OSM PBF data from Geofabrik
   - Downloads GTFS transit feeds
   - Downloads SRTM elevation data (HGT format)
   - Merges multiple PBF files using osmium-tool
   - Runs `download-all.sh` script (367 lines)
   - Features intelligent caching with ETag/Last-Modified headers
   - Uses Alpine container (debian:12-slim)

2. **Build Job** (main container in `job-initialize.yaml`)
   - Builds routing tiles from OSM data
   - Processes elevation data
   - Builds admin/timezone databases
   - Processes transit GTFS feeds
   - Creates compressed tile tarball
   - Uses `ghcr.io/valhalla/valhalla-scripted:latest` image
   - Resource-intensive (3-8 CPU, 8-16GB RAM depending on cluster)

3. **Service Deployment** (`deployment.yaml`)
   - Runs Valhalla API server
   - Serves routing requests via HTTP
   - Uses pre-built tiles from PVC
   - Lightweight (1 CPU, 2GB RAM)
   - Multiple health probes (liveness, readiness, startup with 5min tolerance)

## Configuration

Configured via cluster settings in `k8s/clusters/flux-system/overlays/{local|burginfra}/cluster_settings.yaml`:

### Local Cluster (Development)

```yaml
# Flux control
VALHALLA_FLUX_SUSPEND: "false"  # Auto-deploy enabled
VALHALLA_REPLICAS: "1"          # Service running

# Resources
VALHALLA_STORAGE_SIZE: "10Gi"
VALHALLA_BUILD_CPU: "8"         # More cores available
VALHALLA_BUILD_MEMORY: "14Gi"   # More memory available

# Init Job Mode
VALHALLA_INIT_JOB: "auto"       # Download/build if missing

# Data sources (Switzerland)
VALHALLA_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
VALHALLA_GTFS_URLS: "https://opentransportdata.swiss/de/dataset/timetable-2026-gtfs2020/permalink"
VALHALLA_ELEVATION_BOUNDS: "45,46,47,48:5,6,7,8,9,10,11"
```

### Burginfra Cluster (Production)

```yaml
# Flux control
VALHALLA_FLUX_SUSPEND: "true"   # Currently suspended (under development)
VALHALLA_REPLICAS: "0"          # Service not running

# Resources (limited by VPS)
VALHALLA_STORAGE_SIZE: "30Gi"   # Prepared for Alps expansion
VALHALLA_BUILD_CPU: "3"         # VPS has 8 cores total
VALHALLA_BUILD_MEMORY: "8Gi"    # VPS has 16GB total

# Init Job Mode
VALHALLA_INIT_JOB: "bypass"     # Skip build, use copied data

# Data sources (Switzerland - same as local)
VALHALLA_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
VALHALLA_GTFS_URLS: "https://opentransportdata.swiss/de/dataset/timetable-2026-gtfs2020/permalink"
VALHALLA_ELEVATION_BOUNDS: "45,46,47,48:5,6,7,8,9,10,11"
```

### Init Job Modes

The `VALHALLA_INIT_JOB` variable controls how the initialize job behaves:

- **`download`**: Always download/build all data, overwriting existing files
- **`auto`**: Download/build only if files don't exist, otherwise skip (default for local cluster)
- **`check`**: Only verify that required files exist, fail if missing (useful for validation)
- **`bypass`**: Skip all checks, downloads, and builds - assume data already exists (default for production cluster)

**Recommended workflow**:

- **`download`**: Always download/build all data, overwriting existing files
- **`auto`**: Download/build only if files don't exist, otherwise skip (default for local cluster)
- **`check`**: Only verify that required files exist, fail if missing (useful for validation)
- **`bypass`**: Skip all checks, downloads, and builds - assume data already exists (default for production cluster)

**Recommended workflow**:

1. Run download and build jobs on your **local cluster** (more resources: 8 CPU, 14GB RAM)
2. Copy the built PVC data to **burginfra cluster** (limited: 3 CPU, 8GB RAM)
3. Use `bypass` mode on burginfra to skip resource-intensive operations

This protects your production cluster from OOM issues during data processing.

**IMPORTANT:** After changing cluster_settings.yaml, manually apply:

```bash
kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
```

## Deployment

### Initial Deployment

The initialize job (`job-initialize.yaml`) combines both download and build phases in a single pod with initContainer + main container pattern. **Run this on your local cluster first**, then copy data to burginfra cluster.

#### On Local Cluster

1. **Apply cluster settings**:

   ```bash
   kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
   ```

2. **Flux will create the namespace, PVC, deployment, and job template**

   ```bash
   flux reconcile kustomization apps --with-source
   ```

3. **Manually trigger the initialize job** (combines download + build):

   ```bash
   kubectl create job --from=job/valhalla-initialize valhalla-init-$(date +%Y%m%d-%H%M%S) -n production
   ```

4. **Monitor download progress** (initContainer):

   ```bash
   kubectl logs -n production -l job-name=valhalla-init -c download-data -f
   ```

5. **Monitor build progress** (main container, 10-30 minutes):

   ```bash
   kubectl logs -n production -l job-name=valhalla-init -c build-tiles -f
   ```

6. **Verify service is running**:

   ```bash
   kubectl get pods -n production -l app=valhalla
   kubectl logs -n production deployment/valhalla
   ```

#### On Burginfra Cluster

See "Copying Data Between Clusters" section below to transfer the built data to burginfra cluster.

### Updating Data

**Important**: Run updates on local cluster first, then copy to burginfra cluster.

#### Monthly OSM Updates

```bash
# On local cluster: Re-run initialize job
kubectl create job --from=job/valhalla-initialize valhalla-update-$(date +%Y%m%d) -n production

# Monitor logs (see Initial Deployment section)

# Copy updated data to burginfra cluster (see "Copying Data Between Clusters")

# On burginfra cluster: Restart service
kubectl rollout restart deployment/valhalla -n production
```

#### Weekly Transit Updates

GTFS data updates twice weekly (Tue/Fri). To update:

```bash
# On local cluster: Re-run initialize job
kubectl create job --from=job/valhalla-initialize valhalla-gtfs-$(date +%Y%m%d) -n production

# Copy updated data to burginfra cluster

# On burginfra cluster: Restart service
kubectl rollout restart deployment/valhalla -n production
```

#### Expanding to Alps Region

**Note**: Burginfra cluster is already configured with `VALHALLA_STORAGE_SIZE: "30Gi"` for this expansion.

1. Update local cluster settings:

   ```bash
   # Edit k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
   VALHALLA_STORAGE_SIZE: "30Gi"
   VALHALLA_BUILD_CPU: "8"
   VALHALLA_BUILD_MEMORY: "14Gi"
   VALHALLA_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf,https://download.geofabrik.de/europe/france-latest.osm.pbf,https://download.geofabrik.de/europe/austria-latest.osm.pbf,https://download.geofabrik.de/europe/germany-latest.osm.pbf,https://download.geofabrik.de/europe/italy-latest.osm.pbf"
   VALHALLA_ELEVATION_BOUNDS: "44,45,46,47,48:4,5,6,7,8,9,10,11,12,13,14,15"
   ```

2. Apply settings:

   ```bash
   kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
   ```

3. Delete and recreate PVC on local cluster:

   ```bash
   kubectl delete pvc valhalla-data -n production
   # Flux will recreate it with new size
   ```

4. Run initialize job (see Initial Deployment section)

5. Copy data to burginfra cluster (see "Copying Data Between Clusters")

## API Endpoints

Available at `https://routing.burgdev.ch` (or `http://routing.local.burgdev.ch` for local cluster):

- `GET /status` - Health check
- `POST /route` - Point-to-point routing
- `POST /optimized_route` - Multi-point route optimization
- `POST /isochrone` - Time/distance contours
- `POST /locate` - Snap coordinates to network
- `POST /matrix` - Distance matrix

See [Valhalla API documentation](https://valhalla.github.io/valhalla/api/) for details.

## Troubleshooting

### Job Failures

**Initialize job fails during download (initContainer):**

```bash
# Check logs
kubectl logs -n production -l job-name=valhalla-init -c download-data --tail=100

# Common issues:
# - Network timeout: Script retries automatically with sleep
# - Invalid URLs: Check VALHALLA_OSM_URLS, VALHALLA_GTFS_URLS in cluster settings
# - Out of disk space: Increase VALHALLA_STORAGE_SIZE
# - Init mode: Check VALHALLA_INIT_JOB setting
```

**Initialize job fails during build (main container, OOM killed):**

```bash
# Check if killed by OOM
kubectl describe pod -n production -l job-name=valhalla-init

# Check memory usage
kubectl top pod -n production

# Solutions:
# 1. Use local cluster for builds (more memory: 14GB vs 8GB)
# 2. Reduce region size (build Switzerland instead of Alps)
# 3. Use bypass mode on burginfra and copy pre-built data from local
```

**Initialize job skips execution unexpectedly:**

```bash
# Check init job mode
kubectl get configmap -n flux-system cluster-settings -o yaml | grep VALHALLA_INIT_JOB

# If mode is "bypass" or "check", jobs will skip if data exists
# Change to "auto" or "download" to force execution

# Check if data already exists in PVC
kubectl exec -n production deployment/valhalla -- ls -lh /custom_files/
```

### Service Issues

**Service not starting:**

```bash
# Check if tiles exist
kubectl exec -n production deployment/valhalla -- ls -lh /custom_files/

# Check service logs
kubectl logs -n production deployment/valhalla

# Check pod status
kubectl describe pod -n production -l app=valhalla

# Common issues:
# - Missing valhalla.json or tiles.tar: Re-run initialize job or copy from local cluster
# - Permission errors: Check securityContext (runAsUser: 1000, fsGroup: 1000)
# - PVC mount issues: Check PVC status and StorageClass
# - Startup probe timeout: Increase timeout in deployment.yaml (currently 300s)
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

- **Storage**: ~3-5 GB (OSM PBF + GTFS + elevation + built tiles)
- **Initialize job**:
  - Download phase: < 1 CPU, 2GB RAM, 5-15 minutes (depends on connection)
  - Build phase (local): 8 CPU, 14GB RAM, 10-20 minutes
  - Build phase (burginfra): 3 CPU, 8GB RAM, 20-40 minutes
- **Service**: 1 CPU, 2GB RAM (steady state)

### Future (Alps Region)

- **Storage**: ~15-20 GB (requires 30Gi PVC)
- **Initialize job**:
  - Download phase: < 1 CPU, 2GB RAM, 15-30 minutes
  - Build phase (local): 8 CPU, 14GB RAM, 30-60 minutes
  - Build phase (burginfra): Not recommended (insufficient resources)
- **Service**: 2 CPU, 4GB RAM (larger tile set)

## Data Sources

- **OSM Data**: [Geofabrik](https://download.geofabrik.de/) (updated daily)
- **Transit (CH)**: [Open Transport Data Switzerland](https://opentransportdata.swiss/) (GTFS, updated Tue/Fri)
- **Elevation**: [NASA SRTM](https://aws.amazon.com/public-datasets/terrain/) (30m resolution, with Viewfinder Panoramas void filling)

## Copying Data Between Clusters

To avoid running memory-intensive init jobs on the burginfra cluster, build data on your local cluster and copy it to burginfra.

### 1. Build on Local Cluster

```bash
# Ensure local cluster has VALHALLA_INIT_JOB: "auto" (default)
kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml

# Run initialize job (see Initial Deployment section)
kubectl create job --from=job/valhalla-initialize valhalla-init-$(date +%Y%m%d) -n production

# Monitor and wait for completion (10-30 minutes)
kubectl logs -n production -l job-name=valhalla-init -f
```

### 2. Copy Data to Burginfra Cluster

```bash
# On LOCAL cluster: Create temporary pod to access PVC
KUBECONFIG=~/.kube/config-localhost kubectl run -n production valhalla-copy-src \
  --image=alpine:latest --restart=Never --overrides='{"spec":{"containers":[{"name":"copy","image":"alpine:latest","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"valhalla-data"}}]}}'

# Wait for pod to be ready
KUBECONFIG=~/.kube/config-localhost kubectl wait --for=condition=Ready pod/valhalla-copy-src -n production --timeout=60s

# Copy data from local cluster to your machine
KUBECONFIG=~/.kube/config-localhost kubectl cp production/valhalla-copy-src:/data ./valhalla-data

# On BURGINFRA cluster: Create temporary pod
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl run -n production valhalla-copy-dst \
  --image=alpine:latest --restart=Never --overrides='{"spec":{"containers":[{"name":"copy","image":"alpine:latest","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"valhalla-data"}}]}}'

# Wait for pod to be ready
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl wait --for=condition=Ready pod/valhalla-copy-dst -n production --timeout=60s

# Copy data from your machine to burginfra cluster
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl cp ./valhalla-data production/valhalla-copy-dst:/data

# Cleanup both clusters
KUBECONFIG=~/.kube/config-localhost kubectl delete pod -n production valhalla-copy-src
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl delete pod -n production valhalla-copy-dst
rm -rf ./valhalla-data
```

### 3. Use Bypass Mode on Burginfra Cluster

Ensure `VALHALLA_INIT_JOB: "bypass"` in burginfra cluster settings to skip init jobs entirely:

```bash
# Verify setting in k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
# Should already be set to: VALHALLA_INIT_JOB: "bypass"

# Apply if changed
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml

# Start the service by setting replicas to 1
# Edit cluster settings: VALHALLA_REPLICAS: "1"
# Then apply again
```

## Development and Testing

### Local Testing of Download Script

The `download-all.sh` script can be tested locally without Kubernetes:

```bash
cd k8s/apps/valhalla/base/scripts

# Use the wrapper script for local testing
./test-download-local.sh
```

This script:
- Converts `${VAR}` Flux escaping to `${VAR}` for bash execution
- Sets default values for all required environment variables
- Runs the download logic with verbosity enabled
- Useful for debugging download issues without deploying

### Flux Variable Escaping

Scripts use `${VAR}` syntax (double dollar) to prevent Flux from substituting variables at deployment time. This allows:

1. **Cluster-specific values**: Variables like `${VALHALLA_OSM_URLS}` are substituted from cluster settings
2. **Bash default values**: Syntax like `${OSM_URLS:-default}` works for local testing
3. **Security**: Sensitive values aren't embedded in the ConfigMap

## Architecture Details

### Storage Architecture

The service uses two PVCs:

1. **`valhalla-data`** (10-30Gi): Main storage
   - OSM PBF files (raw and merged)
   - Built routing tiles
   - Elevation data (HGT files)
   - Admin and timezone databases
   - Compressed tile tarball for fast loading

2. **`gtfs-feeds-data`** (2Gi): Transit feed storage
   - GTFS transit data
   - Transit database built from GTFS

Both use `fast-local-data-v3` StorageClass with ReadWriteOnce access mode.

### Security Configuration

**Pod security context:**
```yaml
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
fsGroupChangePolicy: "OnRootMismatch"
runAsNonRoot: true
```

**Container security:**
```yaml
allowPrivilegeEscalation: false
readOnlyRootFilesystem: false  # Required for tile building
```

### Ingress Configuration

```yaml
Host: routing.${ENV_SUBDOMAIN}${WODORE_HOST}
TLS: cert-manager with ${CERT_ISSUER_PROD}
Timeouts: 300s for read/send
Body size: 10m
```

**Examples:**
- Local: `http://routing.local.burgdev.ch`
- Burginfra: `https://routing.burgdev.ch`

## Future Enhancements

- [ ] Use swissALTI3D for higher accuracy elevation (0.5m vs 30m)
- [ ] Consider [planetutils](https://github.com/interline-io/planetutils) for faster planet-scale OSM processing
- [ ] Add CronJob for automated monthly updates
- [ ] Implement horizontal pod autoscaling for service
- [ ] Add Prometheus metrics and Grafana dashboards
- [ ] Configure traffic data for real-time routing
- [ ] Unsuspend Flux on burginfra cluster when ready for production
