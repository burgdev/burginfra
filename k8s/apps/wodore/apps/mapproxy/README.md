# MapProxy — "Europe Topo" raster basemap (Phase 1: static pilot)

Serves the border-merged "Europe Topo" raster basemap: swisstopo
pixelkarte clipped to the Switzerland+Liechtenstein polygon (top),
BEV "Austrian Map online" (ÖK render) clipped to the Austria polygon
(middle), OpenTopoMap as the worldwide fallback (bottom) — merged at
the MapProxy cache level with pixel-perfect country cuts.

Austria note: the topo overlay is BEV's ÖK tiles (z5–z16). The BEV
data catalog declares the product CC BY 4.0, while the www.bev.gv.at
product page still carries legacy no-redistribution wording — written
confirmation has been requested from BEV Kundenservice. The frontend
raster source must cap `maxzoom: 16` so z17+ overzooms instead of
falling through to OpenTopoMap.

- XYZ endpoint (top-left origin, usable directly as a MapLibre raster
  source, no `scheme: 'tms'`):
  `https://tiles.<host>/mapproxy/tiles/europe_topo/webmercator/{z}/{x}/{y}.png`
- Demo UI: `https://tiles.<host>/mapproxy/demo/`

## Phase 1 scope

- Static config: tile sources are hardcoded in `mapproxy.yaml` (no
  backend-driven sync yet).
- On-demand caching: tiles are fetched from upstream and cached in the
  `wd-mapproxy-cache` PVC on first request. No seeding job yet — that
  is a follow-up.

## Config-change semantics

MapProxy reads its config once at startup. The config is embedded via
`configMapGenerator`, so the ConfigMap name is hash-suffixed and any
config edit produces a new hash, replacing the ConfigMap and rolling
the pod.

## Licensing

Only cacheable sources are configured: swisstopo pixelkarte (OGD
terms), BEV Austrian Map online (CC BY 4.0 per the BEV data catalog,
DOI 10.48677/2fe7eed6-ab55-4926-a4a1-80df6dedc55c — product-page
wording conflict flagged to BEV Kundenservice for written
confirmation), basemap.at ortho (CC BY 4.0), OpenTopoMap (CC-BY-SA).
Boundary polygons are Natural Earth 10m country polygons (public
domain).
