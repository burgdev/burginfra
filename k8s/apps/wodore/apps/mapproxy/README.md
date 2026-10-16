# MapProxy — "World Topo/Satellite" raster basemaps (Phase 1: static pilot)

Serves the border-merged raster basemaps: swisstopo pixelkarte clipped
to the Switzerland+Liechtenstein polygon, BEV "Austrian Map online"
(ÖK render) clipped to the Austria polygon, Plan IGN v2 clipped to the
France polygon, LINZ Basemaps topo-raster (Topo50/250 Gridless mosaic)
and aerial clipped to the New Zealand polygon, with OpenTopoMap
(world_topo) resp. Esri World Imagery (world_satellite) as the
worldwide fallback — merged at the MapProxy cache level with
pixel-perfect country cuts.

Austria note: the topo overlay is BEV's ÖK tiles (z5–z16). The BEV
data catalog declares the product CC BY 4.0, while the www.bev.gv.at
product page still carries legacy no-redistribution wording — written
confirmation has been requested from BEV Kundenservice. The frontend
raster source must cap `maxzoom: 16` so z17+ overzooms instead of
falling through to OpenTopoMap.

- XYZ endpoint (top-left origin, usable directly as a MapLibre raster
  source, no `scheme: 'tms'`), via the martin nginx-cache facade:
  `https://tiles.<host>/raster/tiles/world_topo/webmercator/{z}/{x}/{y}.webp`
  (append `?v=N` — see the cache-busting runbook below)
- Demo UI: `https://tiles.<host>/mapproxy/demo/` (internal path; the
  public host routes `/raster/*` through the nginx cache tier)

## Phase 1 scope

- Static config: tile sources are hardcoded in `mapproxy.yaml` (no
  backend-driven sync yet).
- API-key sources: the LINZ Basemaps key (`MAP_LINZ_API_KEY`, OpenBao
  `kv/apps/wodore/staging` → VSO `wd-backend-envvars`, `MAP_*` includes
  filter in the backend staging overlay) reaches wd-mapproxy via
  `secretKeyRef` and is expanded into the tile URLs by MapProxy 7.0.0
  env-var substitution at config load. **The file spells it `$$MAP_LINZ_API_KEY`**
  (flux escape for a literal `$`): `${...}` gets silently emptied by flux
  `postBuild.substitute` and a bare `$VAR` blocks the apply entirely. Environments
  without the key degrade to the OpenTopoMap/Esri fallback (`on_error`).
- On-demand caching: tiles are fetched from upstream and cached in the
  `wd-mapproxy-cache` PVC on first request. No seeding job yet — that
  is a follow-up.

## Config-change semantics

MapProxy reads its config once at startup. The config is embedded via
`configMapGenerator`, so the ConfigMap name is hash-suffixed and any
config edit produces a new hash, replacing the ConfigMap and rolling
the pod.

## Tile-source changes: cache-busting runbook

A source swap does **not** invalidate cached tiles. Three cache layers
must be considered, and only the first is handled by a config deploy:

1. **MapProxy PVC cache** — keyed by cache name + grid + tile coord.
   Rename the cache (`world_topo_cache` → `world_topo_cache_v2`) to
   start a fresh directory; `refresh_before` is too slow to flush a
   source swap.
2. **nginx tier** (`wd-martin-cache`, 7d proxy cache on PVC) — the
   cache key includes the query string, so a frontend version bump
   (`?v=N+1`) busts it. Config deploys do NOT purge it; emergency
   manual purge: `kubectl exec` into the cache pod, wipe
   `/var/cache/nginx/tiles`, `nginx -s reload`.
3. **Browser cache** (`Cache-Control: public, immutable`, 7d) — only a
   URL change busts an `immutable` entry: same `?v=N+1` bump.

**Runbook for any world_topo / world_satellite source change:**

1. Edit the source in `mapproxy.yaml`; rename the affected cache
   (`_v2` → `_v3` …) and repoint the layer.
2. Same release: bump the matching frontend raster version constant
   (`NEXT_PUBLIC_RASTER_TOPO_VERSION` / `..._SATELLITE_VERSION`) so the
   tile URL template gets `?v=N+1` — this is what flushes the nginx
   tier and every browser at once.
3. Frontend: keep the raster source `attribution` current (see
   Licensing) and the `maxzoom` cap aligned with the source's real
   top level (BEV z16).
4. Verify from outside the cluster: fetch a known tile through
   `https://tiles.<host>/raster/...` and pixel-compare against the new
   upstream reference (low RMS = flipped).
5. Sanity-check the upstream's WMTS capabilities when it has one
   (basemap.at, data.geopf.fr) — layer identifiers churn
   (e.g. SCAN25TOUR was retired without a redirect). MapProxy 7.0.0
   has no capabilities-driven source type, so URLs are hand-pinned
   and need this manual check; BEV's `maps.bev.gv.at/tiles/karte/`
   has no capabilities endpoint at all.

## Licensing

Only cacheable sources are configured: swisstopo pixelkarte (OGD
terms), BEV Austrian Map online (CC BY 4.0 per the BEV data catalog,
DOI 10.48677/2fe7eed6-ab55-4926-a4a1-80df6dedc55c — product-page
wording conflict flagged to BEV Kundenservice for written
confirmation), IGN Plan IGN v2 + BD ORTHO (Licence Ouverte/Etalab
2.0, served keyless), basemap.at ortho (CC BY 4.0), LINZ Basemaps
topo-raster + aerial (CC BY 4.0 — LINZ confirmed server-side caching
is fine, attribution only; they suggest re-fetching cached tiles
about every 6 months, well within the 4-week `refresh_before`),
OpenTopoMap (CC-BY-SA), Esri World Imagery (attribution required,
reconsider for commercial scale-up). Boundary polygons are Natural
Earth 10m country polygons (public domain).
