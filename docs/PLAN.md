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
| R14 | Map zoom in/out buttons (small, Google-Maps-like) | 4 |
| R15 | Task list: search, filter and sort; completing a task must not move it away | 4b |

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
  list, and it has **no** "show on map" button until it is given a location
  (user decision). Latitude and longitude are
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
* **Choice (revised in Phase 3):** `flutter_map` **8.3.2** +
  `flutter_map_vector_tiles` **2.11.0**, pinned to exact versions.
  * The plan originally named `vector_map_tiles`. Its latest stable release
    (8.0.0, 2024) only works with `flutter_map` 7, and its `flutter_map` 8
    support exists only as betas (9.0.0-beta.13).
  * `flutter_map_vector_tiles` is stable, supports `flutter_map` 8, and
    lists OpenFreeMap as a supported provider. Its built-in disk cache
    (in a folder the OS doesn't clear, with a lifetime per tile) covers
    the persistent-cache requirement. It has a pluggable tile-source
    interface (`resolveProvider`) and an MBTiles companion package, which
    is exactly what Phase 8's offline maps need.
  * **Risk:** it's young (first release August 2026) with a single
    maintainer. Mitigation: exact version pins, and all package use stays
    in `lib/ui/map/base_map_layer.dart`, so it could be swapped out.
  * Checked against the real OpenFreeMap "Liberty" style: one vector
    source (`openmaptiles`, data up to zoom 14), sprites and fonts load,
    and its attribution matches ours.
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
* Each task in the list that has a location gets a map button. Tasks
  without a location get **no** button at all, rather than a disabled one
  (user decision, PR #4 review). The button appears once the task is
  given a location.
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
* Branches are **never deleted on GitHub**, even after merging, so every
  feature's branch stays available for viewing the app's history.

### D13. Platforms: Android and iOS
* All chosen packages (sqflite, geolocator, flutter_map, flutter_map_vector_tiles,
  http, provider) support both platforms.
* **Limitation:** development happens on Windows, and iOS apps can only be
  built and run on a Mac with Xcode. We will write the iOS configuration
  (Info.plist permission strings, minimum iOS version), but iOS builds can
  only be verified on a Mac. Day-to-day testing uses Android plus
  `flutter test`.

### D14. Task list UI (Phase 2)
* **`TaskListController`, shared by both tabs.** It holds the task list for
  the whole app. The list page uses it now, and the map will use its
  `locatedTasks` in Phase 3, so both pages always show the same data.
* **Write through, then reload.** Every change is saved to SQLite first,
  then the list is re-read. Patching the in-memory list optimistically
  would mean repeating the SQL ordering rules in Dart, and the two could
  drift apart. A local reload takes about a millisecond, so the simpler
  approach costs nothing noticeable, and the database stays the single
  source of truth.
* **Errors:** a failed *load* is stored in the controller, and the page
  shows a "Try again" screen. A failed *change* is rethrown to the UI and
  shown in a snackbar, because only the screen that made the change knows
  what to tell the user.
* **The editor is a plain form that returns a result.** It pops a sealed
  `TaskEditorResult` (`TaskEditorSaved(title, description, dueAt)` or
  `TaskEditorDeleted`), and the list page decides what to do with it. The
  editor never touches storage, and fields it doesn't show (location, done
  state) can't be lost by accident.
* **Deleting has two routes:** swipe left (fast), or the Delete button in
  the editor, with a confirmation dialog (easier to discover). Both show a
  snackbar with **Undo**.
  * The delete runs in `Dismissible.confirmDismiss`, not in `onDismissed`.
    Flutter requires a dismissed item to leave the widget tree
    immediately, but our delete is asynchronous. Awaiting it in
    `confirmDismiss` means the list has already been rebuilt without the
    item when the animation ends, and if the delete fails the tile simply
    slides back.
  * Undo re-inserts the task as a new row, so it gets a new id. Nothing
    keeps task ids long-term, so this keeps the repository contract simple
    ("insert never takes an id").
* **Due dates are a day, not a time.** The picker stores local midnight of
  the chosen day. A task is **overdue** only once that day has fully
  passed, so a task due today is not overdue. Overdue quests show
  "Overdue · <date>" in the theme's error colour.
* **Dates** are shown as **dd-mm-yyyy** (e.g. `20-11-2026`, the user's
  choice). A single `formatDate` helper (`lib/ui/formatting.dart`) is used
  everywhere, so every screen shows the same format. It is a fixed format,
  not locale-based, and needs no `intl` package.
* **Testing:** widget tests use `FakeTaskRepository`, an in-memory fake
  with the same contract and ordering. Real database I/O doesn't run
  inside the fake-async zone of widget tests, and the SQLite repository
  is already covered by its own tests. Clocks are injected, so tests about
  "today" and "overdue" are deterministic.

### D15. Map page and quest markers (Phase 3)
* **Where the map comes from:** the OpenFreeMap "Liberty" style is loaded
  once via `StyleReader`, with our `QuestMark/1.0.0` User-Agent. The
  package sends that header with the style request and with every tile,
  sprite and font request it makes. The style bundle is cached on disk, so
  after the first load the style works offline.
* **Tile cache:** 100 MB, 30-day lifetime, in the app support folder. A
  tile already seen is drawn from disk, so repeat views cost OpenFreeMap
  nothing. If the network fails on first launch, a "Couldn't load the map"
  banner with Retry is shown. Phase 8a's bundled world map will close that
  gap.
* **Attribution:** "OpenFreeMap · © OpenMapTiles · Data © OpenStreetMap
  contributors", in `flutter_map`'s collapsible attribution button. The
  data licence (ODbL) requires it.
* **Starting view** (`InitialMapView`, pure and unit-tested): no quests →
  the whole world; one quest (or all at one spot) → centred on it at
  zoom 15; several → zoomed to fit them all (capped at zoom 15). The map
  waits for the first task load so it doesn't jump, and afterwards the
  camera only moves when the user moves it.
* **No rotation:** pinch-rotate is disabled, so north stays up. A to-do
  map doesn't need rotation, and accidental rotation is disorienting.
* **Marker states** (`QuestMarkerKind.of`, pure and unit-tested): done →
  small grey check; open and the due day has passed → red "!"; due today
  or tomorrow → orange "!"; otherwise gold "!". Days are local calendar
  days. Drawing order puts urgent markers on top: done < active <
  due soon < overdue.
* **Animation costs nothing while hidden:** open quests bob gently, but
  the animation stops when the OS "remove animations" accessibility
  setting is on, and when the map tab is hidden. HomeShell wraps each tab
  in `TickerMode`, so the kept-alive map uses no CPU or battery while
  you're on the list.
* **Tapping a marker** opens a bottom sheet with the details and
  Complete/Reopen and Edit buttons. Edit, delete and undo are shared with
  the list page through `lib/ui/tasks/task_actions.dart`, so both screens
  behave the same.
* **Accessibility:** each marker is a screen-reader button labelled e.g.
  "Quest, overdue: Buy milk".
* **Guard tests:** a test fails if any code line references
  `tile.openstreetmap.org`, and another checks that the User-Agent
  version matches `pubspec.yaml`.
* **"Tasks without locations" badge** (user request, PR #4 review):
  location is optional, so the map shows how many tasks are *not* on it.
  A small circle with "!" sits in the bottom-left corner (the attribution
  button is bottom-right). Tapping it expands it into a rounded rectangle
  reading "x tasks without locations" (correct singular/plural), and
  tapping again collapses it. It starts collapsed so it covers little of
  the map, and it's hidden when every task has a location. It counts all
  tasks without a location, completed ones included, exactly as
  requested.
* **Temporary developer tools** (user request): a bug icon in the Quests
  app bar, in **debug builds only** (`kDebugMode`). It adds or removes
  hardcoded demo quests in central Helsinki (titles start with
  "[Demo] "). They cover every marker state (gold, orange due today, red
  overdue, grey done, gold due later), plus two list-only quests for the
  badge. This lets us check the real map visually on the emulator before
  locations can be entered in Phases 6–7. To be removed before release
  (section 5).
* **Build note:** `path_provider_android` (used by the map packages)
  depends on `jni`, which compiles native code with CMake. The first
  build made Gradle download CMake 3.22.1 automatically. To keep system
  changes in the user's hands, `android/gradle.properties` now sets
  `android.builder.sdkDownload=false`, so a missing SDK component fails
  the build with a message instead of installing silently. The user
  decided to **keep** CMake 3.22.1, since it's needed to build the app.

### D16. Task list search, filters and sorting (Phase 4b, planned)
*Specified by the user during the PR #4 review. Not built yet.*

**Problem:** ticking a task moves it straight into the Completed section,
so a wrongly ticked task has to be hunted down to untick it.
**Decision:** don't move tasks at all. There is one list where completing
a task only strikes it through in place. Which tasks are shown is
controlled by filters. (A 3-second delay before moving was considered and
rejected: the task would still jump away.)

**Filters** (user's specification):
* Status, one of: **All** (default) · **Completed** · **Not completed** ·
  **Overdue**.
* **Date created**: before a date, after a date, or between a start and an
  end date.
* **Due date**: before / after / between.
* **Date completed**: before / after / between.
* The date filters combine with the status filter and with each other
  (e.g. "Not completed, due between 1 and 15 Dec"). Ranges are whole local
  calendar days and include both ends.
* **Search** by text in the title and description (requested earlier,
  in-memory, no network).

**Sorting** (user's specification), each **ascending or descending**:
* **Alphabetical** (title, case-insensitive).
* **Date created.**
* **Due date.**
* **Date completed.**
* Tasks with no value for the chosen field (no due date / not completed)
  go **last in both directions**, so they never push the relevant tasks
  off-screen.

**Design notes:**
* **New column `completed_at`** (schema v2, the first real migration). It
  is set when a task is ticked and cleared when it's unticked. Tasks
  completed before v2 have no completion date, so the "date completed"
  filters and sort treat them as unknown (they sort last).
* **Just-ticked tasks stay visible:** with a filter such as "Not
  completed", a task you just ticked stays in view, struck through, until
  you change the filter or leave the page. An **Undo** snackbar is shown
  too, so an accidental tick is always easy to reverse.
* **The filter and sort rules are a pure Dart class** (`TaskQuery`),
  applied to the in-memory list and unit-tested on its own. The
  repository's SQL "done last" ordering is dropped, because the user's
  chosen sort decides the order.
* **Scope of change:** the list page's body (sections → one list + search
  field + filter/sort controls), the repository ordering, and schema v2.
  The task tile, editor, map and details sheet are unchanged.
* **Numbered "4b"** so that the later phases keep their numbers, because
  code comments and decisions already refer to them (e.g. "Phase 8a").

---

## 4. Phases

Each phase: create branch → implement → tests green → detailed commits →
push branch → open PR → progress report → you review → merge PR into
`main` → wait for your go-ahead on the next phase.

| Phase | Status | Branch | Deliverable | Key tests |
|-------|--------|--------|-------------|-----------|
| **0. Foundation** | ✅ Done (PR #1) | `feature/00-foundation` | `provider` (later dependencies are added in the phase that first needs them, so version conflicts surface where they can be resolved), theme, bottom-nav shell with empty List and Map pages, Android/iOS permission entries | app boots, navigation switches pages |
| **1. Data layer** | ✅ Done (PR #2) | `feature/01-data-layer` | `Task` model, SQLite helper with migrations, `TaskRepository` (CRUD) | toMap/fromMap round trip, lat/lng validation, CRUD on in-memory DB, migration |
| **2. Task list UI** | ✅ Done (PR #3) | `feature/02-task-list` | List page (active/completed), add/edit/delete, tick to complete, swipe to delete | widget tests for add/edit/complete/delete |
| **3. Map + quest markers** | 🚧 In progress | `feature/03-map` | `flutter_map` + OpenFreeMap vector tiles with persistent cache and attribution; quest markers for located tasks; tap a marker → task details | marker state mapping, tile source config, marker rendering |
| **4. Show on map** | ⬜ Planned | `feature/04-show-on-map` | Map button on list items that have a location → Map tab, centred on the task, marker highlighted. Map **zoom +/− buttons** (they share the map controller) | focus controller, button hidden without location, tab switch, zoom buttons and limits |
| **4b. List search, filter & sort** | ⬜ Planned | `feature/04b-list-filters` | One list (no Completed section), search bar, filters and ascending/descending sorting as specified in D16; `completed_at` column (schema v2) | filter/sort rules (pure), migration v1→v2, ticked tasks stay in place, list widget tests |
| **5. GPS** | ⬜ Planned | `feature/05-gps` | Location service, permission flow, player marker, re-centre / follow | fake location stream moves the marker, permission-denied state |
| **6. Pin on map** | ⬜ Planned | `feature/06-pin-location` | Location picker in the task editor (long-press / drag a pin) | picker returns coordinates, editor saves them |
| **7. Address search** | ⬜ Planned | `feature/07-address-search` | Nominatim geocoding + reverse geocoding, rate limiter, SQLite cache | rate limiter spacing, cache hit avoids HTTP, JSON parsing, errors |
| **8a. Bundled world map** | ⬜ Planned | `feature/08a-world-map` | Dev script that builds the z0–5 world MBTiles; bundled asset; copy on first launch; offline rendering | asset copy, tile lookup, fallback order |
| **8b. Region download** | ⬜ Planned | `feature/08b-region-download` | Current-region prompt, Offline maps screen, estimate → throttled download → resume/cancel → list/delete | tile count maths, 3,000-tile cap, concurrency limit, resume, shared-tile deletion |
| **9. Polish** | ⬜ Planned | *to be planned later* | UI design updates (game-style map theme etc.), planned with you when we get there | — |

---

## 5. Open questions

**Before release (to do when the app is finished):**
* Remove the temporary developer tools: `lib/dev/`, the `DevToolsButton`
  in the Quests app bar, and `test/dev/`.
* Replace the template app id `com.example.questmark`.
* None blocking right now. To revisit in Phase 8a: the bundled world-map
  size, and whether zoom 0–5 fits the size goal.
