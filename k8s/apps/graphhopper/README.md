# GraphHopper Routing Engine

Fast and efficient open-source routing engine based on OpenStreetMap data with support for multiple routing profiles.

## Features

- **Multi-modal routing**: Car, bike, pedestrian
- **Fast routing**: Uses Contraction Hierarchies (CH) for sub-millisecond queries
- **Flexible profiles**: Separate graphs for each transport mode
- **Isochrones**: Time/distance contour calculations
- **Route optimization**: Traveling Salesman Problem (TSP) solver
- **Map matching**: Snap GPS traces to road network

## Comparison with Valhalla

| Aspect | GraphHopper | Valhalla |
|--------|-------------|----------|
| **Graph Structure** | Memory-mapped files | Tile-based hierarchy |
| **Profiles** | Separate graphs per mode | Unified graph |
| **Query Speed** | Sub-millisecond (CH) | Millisecond-range |
| **Memory Usage** | 2-4 GB (CH) | 2-4 GB |
| **Build Time** | 10-30 min (CH) | 10-30 min |
| **Transit Support** | GTFS via public transit module | Built-in GTFS support |
| **Storage** | 10-15 GB (Alps) | 15-20 GB (Alps) |

Both engines use the same OSM PBF source data but produce different output formats optimized for their respective algorithms.

## Architecture

### Two-Phase Deployment

1. **Download Phase** (initContainer in `job-initialize.yaml`)
   - Downloads OSM PBF data from Geofabrik
   - Uses intelligent caching with curl ETag/Last-Modified headers
   - Stores in `${DATA_DIR}/osm/` subdirectory
   - Runs `download-and-build.sh` script in "download" mode
   - Uses debian:12-slim container

2. **Build Phase** (main container in `job-initialize.yaml`)
   - Builds routing graphs from OSM data
   - Creates Contraction Hierarchies (CH) for fast queries
   - Builds separate graphs for car, bike, and foot profiles
   - Uses `graphhopper/graphhopper:latest` image
   - Resource-intensive (3-6 CPU, 8-12GB RAM depending on region)

3. **Service Deployment** (`deployment.yaml`)
   - Runs GraphHopper web server
   - Serves routing requests via HTTP
   - Uses pre-built graphs from PVC
   - Lightweight (0.5-1 CPU, 2-4GB RAM)
   - Multiple health probes (liveness, readiness, startup with 5min tolerance)

## Configuration

Configured via cluster settings in `k8s/clusters/flux-system/overlays/{local|burginfra}/cluster_settings.yaml`:

### Local Cluster (Development)

```yaml
# Flux control
GRAPHOPPER_FLUX_SUSPEND: "false"  # Auto-deploy enabled
GRAPHOPPER_REPLICAS: "1"          # Service running

# Resources
GRAPHOPPER_STORAGE_SIZE: "20Gi"   # Prepared for Alps expansion
GRAPHOPPER_BUILD_CPU: "6"         # Leave room for Valhalla
GRAPHOPPER_BUILD_MEMORY: "12Gi"   # Leave room for Valhalla

# Init Job Mode
GRAPHOPPER_INIT_JOB: "auto"       # Download/build if missing

# Data sources (Switzerland)
GRAPHOPPER_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
```

### Burginfra Cluster (Production)

```yaml
# Flux control
GRAPHOPPER_FLUX_SUSPEND: "true"   # Initially suspended
GRAPHOPPER_REPLICAS: "0"          # Service not running yet

# Resources (limited by VPS)
GRAPHOPPER_STORAGE_SIZE: "20Gi"   # Prepared for Alps expansion
GRAPHOPPER_BUILD_CPU: "3"         # Can build Switzerland
GRAPHOPPER_BUILD_MEMORY: "8Gi"    # Can build Switzerland

# Init Job Mode
GRAPHOPPER_INIT_JOB: "bypass"     # Skip build, use copied data

# Data sources (Switzerland - same as local)
GRAPHOPPER_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
```

### Init Job Modes

The `GRAPHOPPER_INIT_JOB` variable controls how the initialize job behaves:

- **`download`**: Always download OSM data (overwrites existing)
- **`build`**: Always build graph from downloaded data
- **`auto`**: Download/build only if graph doesn't exist, otherwise skip (default for local cluster)
- **`bypass`**: Skip all checks, downloads, and builds - assume data already exists (default for production cluster)

**Recommended workflow**:

1. Run download and build jobs on your **local cluster** (more resources: 6 CPU, 12GB RAM)
2. Copy the built PVC data to **burginfra cluster** (limited: 3 CPU, 8GB RAM)
3. Use `bypass` mode on burginfra to skip resource-intensive operations

This protects your production cluster from OOM issues during graph building.

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
   kubectl create job --from=job/graphhopper-initialize graphhopper-init-$(date +%Y%m%d-%H%M%S) -n production
   ```

4. **Monitor download progress** (initContainer):

   ```bash
   kubectl logs -n production -l job-name=graphhopper-init -c download-osm -f
   ```

5. **Monitor build progress** (main container, 10-30 minutes):

   ```bash
   kubectl logs -n production -l job-name=graphhopper-init -c build-graph -f
   ```

6. **Verify service is running**:

   ```bash
   kubectl get pods -n production -l app=graphhopper
   kubectl logs -n production deployment/graphhopper
   ```

#### On Burginfra Cluster

See "Copying Data Between Clusters" section below to transfer the built data to burginfra cluster.

### Updating Data

**Important**: Run updates on local cluster first, then copy to burginfra cluster.

#### Monthly OSM Updates

```bash
# On local cluster: Delete old graph and re-run initialize job
kubectl exec -n production deployment/graphhopper -- rm -rf /data/.gh
kubectl create job --from=job/graphhopper-initialize graphhopper-update-$(date +%Y%m%d) -n production

# Monitor logs (see Initial Deployment section)

# Copy updated data to burginfra cluster (see "Copying Data Between Clusters")

# On burginfra cluster: Restart service
kubectl rollout restart deployment/graphhopper -n production
```

#### Expanding to Alps Region

**Note**: Burginfra cluster is already configured with `GRAPHOPPER_STORAGE_SIZE: "20Gi"` for this expansion.

1. Update local cluster settings:

   ```bash
   # Edit k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
   GRAPHOPPER_OSM_URLS: "https://download.geofabrik.de/europe/switzerland-latest.osm.pbf,https://download.geofabrik.de/europe/france-latest.osm.pbf,https://download.geofabrik.de/europe/austria-latest.osm.pbf,https://download.geofabrik.de/europe/germany-latest.osm.pbf"
   ```

2. Apply settings:

   ```bash
   kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml
   ```

3. Delete and recreate PVC on local cluster:

   ```bash
   kubectl delete pvc graphhopper-data -n production
   # Flux will recreate it with same size (20Gi)
   ```

4. Run initialize job (see Initial Deployment section)

5. Copy data to burginfra cluster (see "Copying Data Between Clusters")

**Note**: GraphHopper currently uses only the first OSM file from multi-region URLs. For multi-country routing, pre-merge PBF files externally using osmium-tool, or use a single merged PBF URL.

## API Endpoints

Available at `https://routing-gh.burgdev.ch` (or `http://routing-gh.local.burgdev.ch` for local cluster):

- `GET /health` - Health check
- `GET /info` - Server information
- `POST /route` - Point-to-point routing
- `POST /navigate` - Turn-by-turn navigation
- `GET /isochrone` - Time/distance contours (if LM enabled)
- `GET /cluster` - Snap coordinates to network

See [GraphHopper API documentation](https://docs.graphhopper.com/) for details.

### Example: Route Request

```bash
curl -X POST https://routing-gh.burgdev.ch/route \
  -H "Content-Type: application/json" \
  -d '{
    "points": [[8.5417, 47.3769], [8.5392, 47.3717]],
    "profile": "car",
    "locale": "en-US",
    "calc_points": true,
    "points_encoded": false
  }'
```

## Troubleshooting

### Job Failures

**Initialize job fails during download (initContainer):**

```bash
# Check logs
kubectl logs -n production -l job-name=graphhopper-init -c download-osm --tail=100

# Common issues:
# - Network timeout: Script retries automatically with curl
# - Invalid URLs: Check GRAPHOPPER_OSM_URLS in cluster settings
# - Out of disk space: Increase GRAPHOPPER_STORAGE_SIZE
# - Init mode: Check GRAPHOPPER_INIT_JOB setting
```

**Initialize job fails during build (main container, OOM killed):**

```bash
# Check if killed by OOM
kubectl describe pod -n production -l job-name=graphhopper-init

# Check memory usage
kubectl top pod -n production

# Check GraphHopper logs for errors
kubectl logs -n production -l job-name=graphhopper-init -c build-graph --tail=100

# Solutions:
# 1. Use local cluster for builds (more memory: 12GB vs 8GB)
# 2. Reduce region size (build Switzerland instead of Alps)
# 3. Disable CH in config.yml (slower queries, less memory)
# 4. Use bypass mode on burginfra and copy pre-built data from local
```

**Initialize job skips execution unexpectedly:**

```bash
# Check init job mode
kubectl get configmap -n flux-system cluster-settings -o yaml | grep GRAPHOPPER_INIT_JOB

# If mode is "bypass", jobs will skip if graph exists
# Change to "auto" or "download" to force execution

# Check if graph already exists in PVC
kubectl exec -n production deployment/graphhopper -- ls -lh /data/.gh/
```

### Service Issues

**Service not starting:**

```bash
# Check if graph exists
kubectl exec -n production deployment/graphhopper -- ls -lh /data/.gh/

# Check service logs
kubectl logs -n production deployment/graphhopper

# Check pod status
kubectl describe pod -n production -l app=graphhopper

# Common issues:
# - Missing .gh directory: Re-run initialize job or copy from local cluster
# - Missing config.yml: Re-run initialize job
# - Permission errors: Check securityContext (runAsUser: 1000, fsGroup: 1000)
# - PVC mount issues: Check PVC status and StorageClass
# - Startup probe timeout: Increase timeout in deployment.yaml (currently 300s)
```

**Slow routing requests:**

```bash
# Check memory usage
kubectl top pod -n production

# Check if CH is enabled
kubectl exec -n production deployment/graphhopper -- cat /data/config.yml | grep -A5 "ch:"

# Solutions:
# - Ensure CH is enabled in config.yml (ch.disable: false)
# - Increase service memory limits
# - Reduce concurrent requests
# - Build with fewer profiles (remove foot or bike)
```

**Incorrect routing results:**

```bash
# Check which profiles were built
kubectl exec -n production deployment/graphhopper -- cat /data/config.yml | grep -A10 "profiles:"

# Verify graph integrity
kubectl exec -n production deployment/graphhopper -- ls -lh /data/.gh/

# Rebuild graph if needed
kubectl exec -n production deployment/graphhopper -- rm -rf /data/.gh
kubectl create job --from=job/graphhopper-initialize graphhopper-rebuild -n production
```

## Resource Usage

### Current (Switzerland Only)

- **Storage**: ~3-5 GB (OSM PBF + built graphs)
- **Initialize job**:
  - Download phase: < 1 CPU, 2GB RAM, 5-15 minutes (depends on connection)
  - Build phase (local): 6 CPU, 12GB RAM, 10-20 minutes
  - Build phase (burginfra): 3 CPU, 8GB RAM, 15-30 minutes
- **Service**: 0.5-1 CPU, 2-4GB RAM (steady state)

### Future (Alps Region)

- **Storage**: ~10-15 GB (requires 20Gi PVC)
- **Initialize job**:
  - Download phase: < 1 CPU, 2GB RAM, 15-30 minutes
  - Build phase (local): 6 CPU, 12GB RAM, 30-60 minutes
  - Build phase (burginfra): Not recommended (insufficient resources)
- **Service**: 1-2 CPU, 3-4GB RAM (larger graph set)

## Data Sources

- **OSM Data**: [Geofabrik](https://download.geofabrik.de/) (updated daily)
- **Elevation**: GraphHopper can use SRTM data (optional, not currently configured)

## Copying Data Between Clusters

To avoid running memory-intensive init jobs on the burginfra cluster, build data on your local cluster and copy it to burginfra.

### 1. Build on Local Cluster

```bash
# Ensure local cluster has GRAPHOPPER_INIT_JOB: "auto" (default)
kubectl apply -f k8s/clusters/flux-system/overlays/local/cluster_settings.yaml

# Run initialize job (see Initial Deployment section)
kubectl create job --from=job/graphhopper-initialize graphhopper-init-$(date +%Y%m%d) -n production

# Monitor and wait for completion (10-30 minutes)
kubectl logs -n production -l job-name=graphhopper-init -f
```

### 2. Copy Data to Burginfra Cluster

```bash
# On LOCAL cluster: Create temporary pod to access PVC
KUBECONFIG=~/.kube/config-localhost kubectl run -n production graphhopper-copy-src \
  --image=alpine:latest --restart=Never --overrides='{"spec":{"containers":[{"name":"copy","image":"alpine:latest","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"graphhopper-data"}}]}}'

# Wait for pod to be ready
KUBECONFIG=~/.kube/config-localhost kubectl wait --for=condition=Ready pod/graphhopper-copy-src -n production --timeout=60s

# Copy data from local cluster to your machine
KUBECONFIG=~/.kube/config-localhost kubectl cp production/graphhopper-copy-src:/data ./graphhopper-data

# On BURGINFRA cluster: Create temporary pod
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl run -n production graphhopper-copy-dst \
  --image=alpine:latest --restart=Never --overrides='{"spec":{"containers":[{"name":"copy","image":"alpine:latest","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"graphhopper-data"}}]}}'

# Wait for pod to be ready
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl wait --for=condition=Ready pod/graphhopper-copy-dst -n production --timeout=60s

# Copy data from your machine to burginfra cluster
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl cp ./graphhopper-data production/graphhopper-copy-dst:/data

# Cleanup both clusters
KUBECONFIG=~/.kube/config-localhost kubectl delete pod -n production graphhopper-copy-src
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl delete pod -n production graphhopper-copy-dst
rm -rf ./graphhopper-data
```

### 3. Use Bypass Mode on Burginfra Cluster

Ensure `GRAPHOPPER_INIT_JOB: "bypass"` in burginfra cluster settings to skip init jobs entirely:

```bash
# Verify setting in k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml
# Should already be set to: GRAPHOPPER_INIT_JOB: "bypass"

# Apply if changed
KUBECONFIG=~/.kube/config-infra-vps1.burgdev.ch kubectl apply -f k8s/clusters/flux-system/overlays/burginfra/cluster_settings.yaml

# Start the service by setting replicas to 1
# Edit cluster settings: GRAPHOPPER_REPLICAS: "1"
# Then apply again
```

## Running Multiple Routing Engines

This infrastructure runs both Valhalla and GraphHopper on the same cluster for comparison and redundancy.

### Resource Allocation

**Burginfra cluster (8 CPU, 16GB RAM):**

**Steady State:**
- Valhalla: 1 CPU, 2GB RAM
- GraphHopper: 0.5 CPU, 2GB RAM
- System overhead: 1 CPU, 2GB RAM
- **Available for other work: 5.5 CPU, 10GB RAM**

**Build Time (on local cluster):**
- Valhalla: 8 CPU, 14GB RAM, 10-20 min
- GraphHopper: 6 CPU, 12GB RAM, 10-20 min
- Can run sequentially or in parallel with resource limits

### API Comparison

| Feature | Valhalla | GraphHopper |
|---------|----------|-------------|
| URL | `https://routing.burgdev.ch` | `https://routing-gh.burgdev.ch` |
| Port | 8002 | 8989 |
| Profiles | car, bike, foot, transit | car, bike, foot |
| Response Format | JSON | JSON |
| Isochrones | Yes | Yes (if LM enabled) |
| Transit | GTFS built-in | Via public transit module |

Both engines can be used simultaneously for A/B testing, redundancy, or to compare routing results.

## Configuration Management

### GraphHopper Config File

The `config.yml` file is auto-generated by the initialize job. Key settings:

```yaml
graphhopper:
  datareader:
    file: /data/osm/switzerland-latest.osm.pbf
    import_vehicle: all

  graph.location: /data/.gh

  profiles:
    - car
    - bike
    - foot

  ch:
    disable: false
    profiles: car, bike, foot

  server:
    host: 0.0.0.0
    port: 8989
```

To customize, edit the `create_config()` function in `download-and-build.sh`.

### Profile Customization

To remove or add profiles:

1. Edit `download-and-build.sh`:
   ```bash
   # In create_config() function
   profiles:
     - car
     - bike
     # Remove foot if not needed
   ```

2. Rebuild graph:
   ```bash
   kubectl exec -n production deployment/graphhopper -- rm -rf /data/.gh
   kubectl create job --from=job/graphhopper-initialize graphhopper-rebuild -n production
   ```

## Development and Testing

### Local Testing

The `download-and-build.sh` script can be tested locally without Kubernetes:

```bash
cd k8s/apps/graphhopper/base/scripts

# Set environment variables
export INIT_MODE=auto
export OSM_URLS="https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
export DATA_DIR="/tmp/graphhopper-test"
export VERBOSE=true

# Run script
./download-and-build.sh
```

### Performance Tuning

**Reduce memory usage:**
- Disable Landmarks (LM): Set `lm.disable: true` in config.yml
- Reduce profile count: Remove foot or bike from profiles list
- Use MMAP instead of RAM_STORE: Set `graph.dataaccess: MMAP`

**Improve query speed:**
- Enable Contraction Hierarchies (CH): Ensure `ch.disable: false`
- Increase Java heap: Set larger `-Xmx` value
- Use faster storage: Use SSD-based StorageClass

## Future Enhancements

- [ ] Add SRTM elevation data for better routing
- [ ] Enable Landmarks (LM) for alternative path queries
- [ ] Configure public transit module
- [ ] Add CronJob for automated monthly updates
- [ ] Implement horizontal pod autoscaling for service
- [ ] Add Prometheus metrics and Grafana dashboards
- [ ] Add custom encoder options for specific vehicle types
- [ ] Unsuspend Flux on burginfra cluster when ready for production

## Additional Resources

- [GraphHopper Documentation](https://docs.graphhopper.com/)
- [GraphHopper GitHub](https://github.com/graphhopper/graphhopper)
- [GraphHopper API Examples](https://github.com/graphhopper/graphhopper/blob/master/docs/web/api.md)
- [OSM Data Sources](https://download.geofabrik.de/)
