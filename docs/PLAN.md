# QuestMark — Development Plan & Design Decisions

A to-do app where tasks can have a location and appear on a world map as
"quest markers", like in an open-world video game. The map also shows the
phone's live GPS position.

This document is the living plan. Each phase is built on its own feature
branch, ends with passing tests and detailed commits, and is merged into
`main` and pushed. The decision log (section 3) records *why* each choice was
made.

---

## 1. Requirements (from the brief)

| # | Requirement | Covered in phase |
|---|-------------|------------------|
| R1 | Flutter + Dart, Android **and** iOS | all |
| R2 | Tasks stored locally in SQLite | 1 |
| R3 | Page 1: tasks as a list | 2 |
| R4 | Page 2: map with tasks drawn as quest markers | 3 |
| R5 | List items have a button that opens the map centred on that task | 4 |
| R6 | Track phone GPS and show it on the map (no routing) | 5 |
| R7 | Place a task by tapping a point on the map | 6 |
| R8 | Place a task by searching an address (OSM) | 7 |
| R9 | OSM-based map with careful, low-volume network use | 3, 7, 8 |
| R10 | Low-detail world map packaged with the app | 8a |
| R11 | Detailed regions downloadable separately; offer the user's current region first, and download only with their permission | 8b |
| R12 | Unit tests for every feature | all |
| R13 | A branch per feature, detailed commits, merge to `main`, push | all |

---

## 2. Architecture overview

```
lib/
  main.dart                 app entry, dependency wiring
  app.dart                  MaterialApp, theme, bottom navigation (List | Map)
  models/                   plain Dart data classes (Task, GeoPoint, Region, …)
  data/                     SQLite: database helper, migrations, repositories
  services/                 location (GPS), geocoding (Nominatim), map tiles/regions
  state/                    ChangeNotifiers the UI listens to
  ui/
    tasks/                  list page, task editor
    map/                    map page, quest marker widgets, location picker
    offline/                region download prompt + manager
assets/
  map/                      bundled low-detail world tiles + map style
test/                       mirrors lib/ one-to-one
```

Layering rule: **UI → state → repositories/services → SQLite/HTTP/GPS.**
The UI never talks to SQLite, HTTP or GPS directly. Each service is defined
as an abstract class, so tests can swap in a fake. This is what makes
"unit tests for every feature" practical: we can test the map logic without
a real GPS chip and test address search without calling real servers.

---

## 3. Decision log

### D1. State management: `provider` + `ChangeNotifier`
* **Options considered:** setState only, provider, Riverpod, BLoC.
* **Choice:** `provider` with `ChangeNotifier`.
* **Why:** The app's state is small (a task list, the current GPS position,
  download progress, which task the map should centre on). `provider` is
  the approach the Flutter team documents, has very little boilerplate, and
  is easy to explain in a report. Plain setState would not let the list page
  and map page share one task list, which R5 ("show on map") needs.

### D2. Database: `sqflite` (+ `sqflite_common_ffi` for tests)
* **Choice:** `sqflite` on the phone (works on both Android and iOS). In
  unit tests, `sqflite_common_ffi` runs the same SQL against an in-memory
  database on the PC.
* **Why:** The brief requires SQLite. `sqflite` is the standard, mature
  plugin. The FFI variant means the repository tests run with plain
  `flutter test`, with no emulator needed.
* **Alternatives rejected:** Drift (a typed ORM with code generation). It's
  nice, but it adds a build step and hides the SQL, which matters for a
  course project. Hive/Isar are not SQLite.
* **Migrations:** The schema has a version number and an `onUpgrade` that
  applies changes step by step from day one, so later phases can add tables
  (geocode cache, regions) without wiping user data.

### D3. Task data model
```
tasks(
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  title       TEXT NOT NULL,
  description TEXT,
  is_done     INTEGER NOT NULL DEFAULT 0,   -- SQLite has no bool
  created_at  INTEGER NOT NULL,             -- epoch millis (UTC)
  due_at      INTEGER,                      -- optional
  address     TEXT,                         -- human-readable, optional
  latitude    REAL,                         -- optional
  longitude   REAL                          -- optional
)
```
* Location is **optional**. A task without coordinates appears only in the
  list, and its "show on map" button is disabled. Latitude and longitude are
  either both set or both null; the model enforces this.
* `address` is stored next to the coordinates. This is a cache: once an
  address has been geocoded, we never ask Nominatim for it again (see D6).
* Times are stored as epoch milliseconds (integers), which sort and compare
  cheaply in SQL.

**Implementation notes (Phase 1):**
* **Our own `GeoPoint` type, not the map library's `LatLng`.** This keeps
  the models and the data layer independent of `flutter_map`, so they can
  be tested without it, and swapping the map library would only touch the
  UI. `GeoPoint` validates its range (lat −90..90, lng −180..180, finite).
  Because a location is one `GeoPoint?`, "latitude without longitude"
  can't be represented at all.
* **Immutable `Task` with `copyWith`.** Nullable fields in `copyWith` take a
  function (`location: () => null`), because a plain `null` argument can't
  tell "leave unchanged" apart from "clear". This is the same pattern
  Flutter uses in its own APIs.
* **Normalisation in the constructor:** the title is trimmed and must not be
  empty; a blank description or address becomes `null`; times become UTC
  truncated to milliseconds. SQLite stores milliseconds, so without the
  truncation a task created with `DateTime.now()` (which carries
  microseconds) would not equal itself after being saved and loaded.
* **Validation in two layers:** the Dart model validates first, and SQL
  `CHECK` constraints repeat the key rules (non-blank title, `is_done` is
  0/1, coordinate ranges, both-or-neither coordinates). The constraints
  protect the data if a future bug or migration bypasses the model.
* **Repository interface + sqflite implementation.** The state layer
  depends on `TaskRepository`, an `abstract interface class`, so Phase 2
  widget tests can use an in-memory fake. Error contract: inserting a task
  that already has an id, or updating one without, throws `ArgumentError`;
  updating an id that doesn't exist throws `TaskNotFoundException`;
  `delete` returns whether something was deleted.
* **List order is defined in SQL:** active before done, then tasks with a
  due date (earliest first), then newest created first. It is backed by an
  index on `(is_done, created_at)`.
* **Migrations as an ordered list of SQL steps.** The schema version is the
  list's length. A fresh install runs every step, and an upgrade runs only
  the missing ones, so both paths always produce the same schema. sqflite
  wraps them in a transaction, so a failed migration rolls back. Tests
  verify that both upgrade and rollback keep existing data. Steps that have
  shipped are never edited, only appended.

### D4. Where the map comes from (re-researched)

**Finding: OSM's own tile server cannot be used for any downloading.**
The OSMF Tile Usage Policy
(<https://operations.osmfoundation.org/policies/tiles/>) states:
* "Bulk downloading is any pre-emptive fetching of tiles other than those a
  user is actively viewing."
* "Offline use is not permitted on `tile.openstreetmap.org`." Any
  "download for offline" button or background job is explicitly listed as
  prohibited, as is "building tile archives (e.g. `.mbtiles`) for later
  distribution".
* There is **no exception for low zoom levels or small areas**, so even
  packaging a low-detail world map made from those tiles breaks the policy.
* The policy itself says: "If you require offline maps, use self-hosted
  tiles or a provider that explicitly allows offline/prefetching."

**Choice: OpenFreeMap** (<https://openfreemap.org>), a free, open-source
service that serves map tiles made from OpenStreetMap data.
* It **explicitly allows offline downloads**: "Offline downloads are
  allowed up to 3,000 tiles or 50 MB per download, with at most 4 parallel
  requests and a unique User-Agent."
* No API key or account is needed.
* It is still OpenStreetMap data, so the brief's "map done with OSM" holds.
  Attribution: "© OpenMapTiles, data © OpenStreetMap contributors".

**Consequence: vector tiles, not raster images.** OpenFreeMap serves
*vector* tiles: the roads, buildings and labels as shapes, which the app
draws itself. This turns out to suit our needs well:
* **Overzoom.** Vector tiles exist up to zoom 14, and the app can draw them
  at any closer zoom from that data. A downloaded region therefore needs no
  zoom 15–19 tiles, which keeps downloads several times smaller than raster.
* **Styling.** We control the map's look (colours, label fonts), so it can
  be styled to feel like a game map in the polish phase.
* **One look everywhere.** Online browsing, the bundled world map and
  downloaded regions all use the same tiles and style.
* **Cost:** drawing vector tiles takes more CPU than showing images. The
  Flutter vector-tile plugins are less mature than raster ones, so in
  Phase 3 we pin the package versions and check performance on a real phone
  early.

**Alternatives considered:**
* *OSM raster tiles + caching only.* Allowed for normal browsing, but it
  can't meet R10/R11 at all.
* *Commercial providers (MapTiler, Thunderforest) with an API key.* They
  allow offline use on some plans, but need an account, a key in the app,
  and have quota limits.
* *Self-hosting PMTiles extracts (Protomaps).* Fully under our control, but
  needs a server, which is out of scope for this project.

### D5. Map widget: `flutter_map` + vector-tile plugin
* **Choice:** `flutter_map` with `vector_map_tiles` (MapLibre/OpenMapTiles
  style support). The exact versions that work together are pinned in
  Phase 3.
* **Why:** `flutter_map` is pure Dart and works the same on Android and iOS.
  Markers are ordinary Flutter widgets, so animated quest markers are easy,
  and we control exactly how tiles are fetched and stored.
* **Rejected:** `google_maps_flutter` (not OSM). The MapLibre native SDK is
  more powerful, but its markers are harder to customise and it is a much
  heavier dependency.
* **Network rules for online browsing:** a stable `QuestMark/<version>`
  User-Agent, tiles kept in a persistent cache (a tile already seen is never
  fetched again), and the attribution shown on the map.

### D6. Address search: Nominatim, used carefully
The Nominatim policy allows at most **1 request per second**, forbids
autocomplete (search-as-you-type), and requires a User-Agent. Our design:
* Search runs only when the user **presses Search**, not on each keystroke.
* A client-side **rate limiter** (a request queue that keeps ≥1.1 s between
  calls) is built into the geocoding service and unit tested.
* Results are **cached in SQLite** (`geocode_cache(query → results, time)`),
  so the same search never hits the network twice.
* Queries are normalised (trimmed, lower-cased) before the cache lookup.
* When a task is placed by pinning the map, reverse geocoding (coordinates
  → address) runs once, on save, and only when the task has no address yet.

### D7. Offline maps: two levels

**Level 1: the low-detail world map, packaged with the app (R10).**
* Zoom levels 0–5 of the whole world: 1 + 4 + 16 + 64 + 256 + 1024 =
  **1,365 tiles**. That is a single download within OpenFreeMap's
  3,000-tile limit.
* A one-off developer script (`tool/`) fetches them once and packs them into
  a single file (MBTiles = SQLite) under `assets/map/`. The app copies this
  file to app storage on first launch, because the tile plugins can't read
  straight from Flutter assets.
* Below zoom 6, the world map always renders, even with no network.
* *Size check:* we measure the file in Phase 8a. If it is too big for the
  app bundle (goal: under ~25 MB), we drop to zoom 0–4 (341 tiles). If that
  is still too big, we fall back to the public-domain Natural Earth outlines
  (~2 MB GeoJSON).

**Level 2: detailed regions, downloaded on request (R11).**
* **Offering the current region.** On the first GPS fix (and whenever the
  user is outside every downloaded region), the app shows a non-blocking
  prompt: *"Download the detailed map for your area? (≈ N tiles, ≈ X MB)"*
  with **Download / Not now / Don't ask again**. Nothing is downloaded
  without the user saying yes.
* **Region size.** A region is a square centred on the user, zooms 6–14,
  sized automatically so the total tile count stays under 3,000 (roughly
  60–80 km across, depending on latitude). The tile maths is pure Dart and
  unit tested.
* The user can also open an **Offline maps** screen, select another area on
  the map, see the estimate, and download it under the same limits.
* **Download rules:** at most 4 parallel requests (we use 2), the same
  User-Agent, resume after interruption, cancel at any time.
* **Storage:** tiles go into an app-managed MBTiles/SQLite store with a
  `regions` table, so regions can be listed, their sizes shown, and deleted
  individually. A tile shared by two regions is kept until both are deleted.
* **Rendering order:** downloaded region tiles → online tiles (cached) →
  bundled world map.

### D8. GPS: `geolocator`
* **Choice:** `geolocator` (Android and iOS) with a position *stream*
  (`distanceFilter` ≈ 5 m), so the app gets updates only when the phone has
  actually moved. This saves battery and avoids needless redraws.
* Permission flow: explain → request → handle "denied forever" with a button
  that opens the system settings. Android: `ACCESS_FINE_LOCATION` and
  `ACCESS_COARSE_LOCATION`; iOS: `NSLocationWhenInUseUsageDescription`.
* Foreground only. Background tracking isn't needed and would require much
  stricter Play Store / App Store permissions.
* The map has a "re-centre on me" button and an optional follow mode.

### D9. Quest-marker visual language
| State | Marker |
|-------|--------|--------|-------------|-----------|
| Active task | golden **!** in a shield/diamond, gentle bobbing animation |
| Task due soon / overdue | orange / red tint |
| Completed task | grey **✓**, smaller, no animation |
| Player (GPS) | blue arrow/dot with an accuracy circle |

Off-screen direction arrows were **dropped** (user decision). The user can
zoom out to see all quests.

### D10. "Show on map" from the list (R5)
* Each task in the list that has a location gets a map button.
* Tapping it switches to the Map tab and animates the camera to centre on
  the task at a sensible zoom (~16), with that marker highlighted.
* Implemented as a shared `MapFocusController` (a ChangeNotifier holding a
  "focus request"), so the list page never touches the map widget directly.
  This keeps it testable: tests check that the request is issued and that
  the map consumes it.

### D11. Testing strategy
* **Unit tests:** models (serialisation, validation), repositories
  (in-memory SQLite via FFI), rate limiter, geocoding parser (fake HTTP
  client), tile/region maths, download scheduler (fake HTTP), focus
  controller.
* **Widget tests:** list page, task editor, map page markers (with fake
  tile source and fake location service), region prompt.
* Every phase adds its own tests, and `flutter test` + `flutter analyze`
  must pass before merging.

### D12. Version control workflow
* One branch per feature: `feature/<phase-number>-<short-name>`, e.g.
  `feature/01-data-layer`.
* Detailed commits on the branch: what was done, why, and how it was tested.
* When the feature is finished and green, push the branch and **open a pull
  request** into `main` on GitHub. The PR description summarises the
  feature, the design choices made and how it was tested.
* The user reviews the PR. After their approval, it is merged with a merge
  commit (`gh pr merge --merge`, the same as `--no-ff`), so each feature
  stays visible as one unit in the history. Then local `main` is updated.
* Why PRs: they give one place to review the full diff of a feature, keep a
  written record of each feature on GitHub, and make sure nothing reaches
  `main` without the user seeing it.

### D13. Platforms: Android and iOS
* All chosen packages (sqflite, geolocator, flutter_map, vector_map_tiles,
  http, provider) support both platforms.
* **Limitation:** development happens on Windows, and iOS apps can only be
  built and run on a Mac with Xcode. We will write the iOS configuration
  (Info.plist permission strings, minimum iOS version), but iOS builds can
  only be verified on a Mac. Day-to-day testing uses Android plus
  `flutter test`.

---

## 4. Phases

Each phase: create branch → implement → tests green → detailed commits →
push branch → open PR → progress report → you review → merge PR into
`main` → wait for your go-ahead on the next phase.

| Phase | Status | Branch | Deliverable | Key tests |
|-------|--------|--------|-------------|-----------|
| **0. Foundation** | ✅ Done (PR #1) | `feature/00-foundation` | `provider` (later dependencies are added in the phase that first needs them, so version conflicts surface where they can be resolved), theme, bottom-nav shell with empty List and Map pages, Android/iOS permission entries | app boots, navigation switches pages |
| **1. Data layer** | 🚧 In progress | `feature/01-data-layer` | `Task` model, SQLite helper with migrations, `TaskRepository` (CRUD) | toMap/fromMap round trip, lat/lng validation, CRUD on in-memory DB, migration |
| **2. Task list UI** | ⬜ Planned | `feature/02-task-list` | List page (active/completed), add/edit/delete, tick to complete, swipe to delete | widget tests for add/edit/complete/delete |
| **3. Map + quest markers** | ⬜ Planned | `feature/03-map` | `flutter_map` + OpenFreeMap vector tiles with persistent cache and attribution; quest markers for located tasks; tap a marker → task details | marker state mapping, tile source config, marker rendering |
| **4. Show on map** | ⬜ Planned | `feature/04-show-on-map` | Map button on list items → Map tab, centred on the task, marker highlighted | focus controller, button disabled without location, tab switch |
| **5. GPS** | ⬜ Planned | `feature/05-gps` | Location service, permission flow, player marker, re-centre / follow | fake location stream moves the marker, permission-denied state |
| **6. Pin on map** | ⬜ Planned | `feature/06-pin-location` | Location picker in the task editor (long-press / drag a pin) | picker returns coordinates, editor saves them |
| **7. Address search** | ⬜ Planned | `feature/07-address-search` | Nominatim geocoding + reverse geocoding, rate limiter, SQLite cache | rate limiter spacing, cache hit avoids HTTP, JSON parsing, errors |
| **8a. Bundled world map** | ⬜ Planned | `feature/08a-world-map` | Dev script that builds the z0–5 world MBTiles; bundled asset; copy on first launch; offline rendering | asset copy, tile lookup, fallback order |
| **8b. Region download** | ⬜ Planned | `feature/08b-region-download` | Current-region prompt, Offline maps screen, estimate → throttled download → resume/cancel → list/delete | tile count maths, 3,000-tile cap, concurrency limit, resume, shared-tile deletion |
| **9. Polish** | ⬜ Planned | *to be planned later* | UI design updates (game-style map theme etc.), planned with you when we get there | — |

---

## 5. Open questions
* None blocking right now. To revisit in Phase 8a: the bundled world-map
  size, and whether zoom 0–5 fits the size goal.
