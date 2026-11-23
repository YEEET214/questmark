# Bundled world map

The low-detail world map that ships inside QuestMark (see `docs/PLAN.md`,
decision D7). Nothing here is written by hand: everything is made by

```bash
dart run tool/build_world_map.dart            # zoom 0-5 (default)
dart run tool/build_world_map.dart --max-zoom 4
```

| File | What it is |
|---|---|
| `world.mbtiles` | Every OpenFreeMap vector tile of zoom 0–5 (1,365 tiles), gzipped, in an MBTiles (SQLite) file. |
| `world.json` | Its version and size. The app uses these to copy the map into its storage once, and again only after an update. |
| `offline_style.json` | OpenFreeMap's "Liberty" style, cut down to work with no network: no icons, the phone's own fonts. |

Map data © OpenStreetMap contributors, tiles © OpenMapTiles, served by
OpenFreeMap. The app shows these credits on every map.

The script downloads at most 3,000 tiles / 50 MB, 2 requests at a time,
with the app's User-Agent, as OpenFreeMap's rules for offline use require.
Run it again only when the map should be refreshed (it's a one-off).
