# Valhalla Download Scripts

This directory contains scripts for downloading and preparing data for Valhalla routing.

## Files

- **`download-all.sh`** - Main script that downloads OSM data, GTFS transit feeds, and elevation data
- **`test-download-local.sh`** - Wrapper script for local testing

## Flux Variable Substitution

The `download-all.sh` script uses `$${VAR}` syntax (double dollar signs) instead of the standard `${VAR}` syntax. This is necessary because:

1. **In Kubernetes**: Flux/Kustomize processes the script when creating the ConfigMap
2. **Variable substitution**: Flux would try to substitute `${VAR}` with its own variables
3. **Double-dollar escape**: `$${VAR}` becomes `${VAR}` in the actual script that runs in the pod

## Local Testing

To test the script locally, you **cannot run it directly** because the `$${VAR}` syntax is not valid bash. Instead, use the wrapper:

```bash
# Run with defaults (Switzerland)
./test-download-local.sh

# Run with custom environment variables
CUSTOM_DIR=/tmp/valhalla OSM_URLS=https://example.com/map.osm.pbf ./test-download-local.sh
```

The wrapper automatically converts `$${VAR}` to `${VAR}` before execution.

## Environment Variables

All variables have sensible defaults for Switzerland:

| Variable | Default | Description |
|----------|---------|-------------|
| `CUSTOM_DIR` | `/custom_files` | Directory for OSM data and elevation |
| `GTFS_DIR` | `/gtfs_feeds` | Directory for GTFS transit feeds |
| `OSM_URLS` | Switzerland from Geofabrik | Comma-separated OSM PBF URLs |
| `GTFS_URLS` | Swiss transport data | Comma-separated GTFS feed URLs |
| `ELEVATION_BOUNDS` | `45,46,47,48:5,6,7,8,9,10,11` | Latitude:Longitude ranges for SRTM tiles |
| `ERROR_SLEEP` | `30` | Seconds to sleep on error (for debugging) |
| `FINISH_SLEEP` | `0` | Seconds to sleep after completion |

## What the Script Does

1. **Installs dependencies**: wget, osmium-tool, unzip, file, tree
2. **Downloads OSM data**: 
   - Downloads one or more PBF files
   - Merges multiple files if needed using osmium
3. **Downloads GTFS feeds**:
   - Downloads transit data feeds
   - Extracts zip files into separate feed directories
4. **Downloads elevation data**:
   - Downloads SRTM HGT tiles based on latitude/longitude bounds
   - Tries AWS S3 first, falls back to viewfinderpanoramas.org
5. **Sets permissions**: Makes files readable by the Valhalla build job (group 1000)

## Elevation Bounds Format

The `ELEVATION_BOUNDS` format is: `lat1,lat2,...:lon1,lon2,...`

Example for Switzerland (45-48°N, 5-11°E):
```
ELEVATION_BOUNDS="45,46,47,48:5,6,7,8,9,10,11"
```

This downloads tiles: N45E005, N45E006, ..., N48E011 (28 tiles total)

## OSM URL Examples

Single region:
```
OSM_URLS="https://download.geofabrik.de/europe/switzerland-latest.osm.pbf"
```

Multiple regions (will be merged):
```
OSM_URLS="https://download.geofabrik.de/europe/switzerland-latest.osm.pbf,https://download.geofabrik.de/europe/austria-latest.osm.pbf"
```
