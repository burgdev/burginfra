# Bunny CDN-Tag headers at the burginfra edge

**Date:** 2026-10-27 · **PR:** (this branch, `cdn-tag-headers`)
**Counterpart:** wodore-backend PR #433 (`tile_server/tile-router.conf.template`
+ `ApiCdnCacheMiddleware`; full taxonomy: wodore-backend
`_work/261026_cdn_tags.md` — the single source of truth this mirrors).

## What changed

Additive-only (64 insertions, 0 deletions). No cache keys, TTLs, or CORS
behavior touched.

1. **Martin nginx-cache tier** (`k8s/apps/wodore/apps/martin/base/nginx-cache-config.conf`)
   - `map $request_uri $cdn_tile_tag` at http level — copied semantics-verbatim
     from the backend tile-router template: meta group (`sprite|font|catalog|healthz`
     → `tiles tiles:meta`) first, then raster facades
     (`/raster/tiles/<facade>/…` → `tiles tiles:raster:<facade>`), then the
     generic first-path-segment rule (`/<source>/…` → `tiles tiles:<source>`).
     Order matters — first match wins; without it `/raster/…` would tag as
     source `raster`.
   - `add_header CDN-Tag $cdn_tile_tag always;` in the three tile-serving
     locations (`/raster/`, the MLT regex location, `location /`). Repeated
     per location because nginx `add_header` inheritance is all-or-nothing per
     level. `always` → header also on error/stale responses; empty map value
     → header skipped (composites `a,b` and unknown shapes are untagged,
     purge-immune).
2. **Django media nginx sidecar** (`k8s/apps/wodore/apps/backend/base/nginx-media.yaml`)
   - `map $request_uri $cdn_media_tag`: `/media/symbols(/|\.|\?|$)` →
     `media media:symbols` (symbols change with category/POI edits — the actual
     purge use case), else `/media(/|\.|\?|$)` → `media`; anything else → `""`
     (untagged). Map sits at file top (conf.d include is http context).
   - `add_header CDN-Tag $cdn_media_tag always;` in `location /media`.

Both maps key on `$request_uri` — the ORIGINAL URI — so the `/raster/`
rewrite and the MLT proxy_pass URI construction cannot skew the lookup.
Delimiters after a name are `(/|\.|\?|$)`: bare `/catalog` matches, query
strings and extensions ride along, `/mediafoo` does not match.

## Deliberate non-tags

- `location = /nginx-health` — not proxied, internal probe.
- `location = /health` — burginfra-specific path, not in the taxonomy (the
  meta rule covers martin's own `/healthz` which flows through `location /`).
  Also: adding an `add_header` there would cancel its inherited server-level
  `X-Cache-Status` (all-or-nothing inheritance) for zero purge value.
- `/raster/<non-tiles>` (e.g. `/raster/other-thing`) → `tiles tiles:raster`
  via the generic rule — same fallthrough the backend tile-router emits;
  verbatim parity kept.
- Imagor output, admin — untagged per backend decisions (no burginfra change).

## Verification (nginx:1.27-alpine, live containers)

Rendered via `envsubst '${NAMESPACE}'`; test-only swaps: resolver → docker
DNS and service names → a local always-200 origin (everything else
byte-identical). `nginx -t` clean on both confs (martin needs the resolver
swap: `nginx -t` resolves the resolver hostname itself, which only exists
in-cluster).

| URL | Status | CDN-Tag |
| --- | --- | --- |
| `/huts/5/10/10` | 502* | `tiles tiles:huts` |
| `/huts/5/10/10.mlt` | 502* | `tiles tiles:huts` (same tag as MVT sibling) |
| `/huts,geoplaces/5/10/10` | 502* | *(none — composite, purge-immune)* |
| `/geoplaces_view.json` | 502* | `tiles tiles:geoplaces_view` |
| `/raster/tiles/world_topo/8/200/200.webp` | 502* | `tiles tiles:raster:world_topo` |
| `/raster/tiles/world_topo.json` | 502* | `tiles tiles:raster:world_topo` |
| `/raster/other-thing` | 502* | `tiles tiles:raster` (generic fallthrough, parity) |
| `/catalog`, `/catalog?v=2` | 502* | `tiles tiles:meta` |
| `/healthz`, `/sprite/…`, `/font/…` | 502* | `tiles tiles:meta` |
| `/contours/12/2100/1450.pbf` | 502* | `tiles tiles:contours` |
| `/health` | 502* | *(none; X-Cache-Status preserved)* |
| `/media/x.jpg` | 404 | `media` |
| `/media/symbols/foo.svg` | 404 | `media media:symbols` |
| `/media/symbols/sub/deep.svg` | 404 | `media media:symbols` |
| `/media`, `/media/huts/1/photo.jpg` | 404 | `media` |
| `/mediafoo`, `/static/other.txt` | 404 | *(none)* |

\* upstream intentionally unreachable in the harness; `always` still emits
the header — exactly the mechanism Bunny needs on 5xx/stale. 404s in the
media harness likewise prove the `always` flag; the map result itself is
response-independent.

`kustomize build` clean for martin+backend × staging+production. Martin
ConfigMap hash changes (`c6gft2b469` → `dm7btmtb47`) → volume reference
rewrites → cache pod rolls on apply. Flux `${}` invariant intact (only
`${NAMESPACE}` braced).

## Rollout

- Martin: configMapGenerator hash suffix rolls the pod automatically.
- Media: plain ConfigMap, but the cluster runs Reloader with
  `autoReloadAll: true` (k8s/infrastructure/reloader) → backend pod rolls
  automatically on the ConfigMap change.
- A Bunny tag purge does NOT flush this nginx proxy_cache tier — deploy-time
  edge purges stay separate (accepted, per the backend _work doc).

## How to purge (after deploy)

```sh
curl -X POST https://api.bunny.net/pullzone/<id>/purgeCache \
  -H "AccessKey: <key>" -H 'Content-Type: application/json' \
  -d '{"CacheTag": "* tiles:huts *"}'      # one martin source
# other tags: tiles:raster:world_topo, tiles:meta, media, media:symbols, api, api:<app>, static
```

Wildcard-wrapped because responses carry space-separated multi-tags.
Backend tags (`api api:<app>`, `static`) already flow through the hub zone
via Django middleware — no burginfra work needed for them.
