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
| R16 | Completed tasks hidden on the map by default; a toggle button shows them | 4 |
| R17 | Recycle bin: deleted tasks are kept 30 days and can be restored, then deleted permanently | 4c |
| R18 | "Delete all completed tasks" moves them all to the recycle bin, after a Yes/No confirmation | 4c |
| R19 | Settings page (gear item in the Quests "⋮" menu, below Recycle bin) with dark mode and a high contrast mode | 9a |

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

### D6. Address search: Nominatim, used carefully (as built: D24)
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

### D7. Offline maps: two levels (as built: D25, D26, D27)

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
* On start-up the map centres on the user (D19).
* As built, with the details of the prompt and follow mode: D22.

### D9. Quest-marker visual language
| State | Marker |
|-------|--------|
| Active task | golden **!** in a shield/diamond, gentle bobbing animation |
| Task due soon / overdue | orange / red tint |
| Completed task | grey **✓**, smaller, no animation |
| Player (GPS) | blue arrow/dot with an accuracy circle |

**Completed quests are hidden on the map by default** (user decision, PR #4
review). A toggle button on the map shows or hides them; see D17.

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
* **Only the user deletes branches**, manually, after merging a PR.
  Claude never deletes branches, on GitHub or locally.
* Docs-only changes, such as plan updates, use a `docs/<short-name>`
  branch with their own PR.

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

### D16. Task list search, filters and sorting (Phase 4b)
*Specified by the user during the PR #4 review. Built in Phase 4b; see
"As built" at the end of this section.*

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

**As built (Phase 4b):**
* **Default sort: due date, ascending.** The most urgent quests come
  first, and quests without a due date come last. Ties: newest created
  first, then highest id, so the order is always stable.
* **The repository's order is now simply "newest created first".** It is
  only a stable default. All visible ordering comes from `TaskQuery`, so
  ticking a task never moves it.
* **`TaskQuery`** (`lib/models/task_query.dart`) is an immutable value
  holding the search, status, three `DayRange`s and the sort. Its `apply()`
  is pure. **`DayRange`** stores local calendar days, with optional
  `from`/`to` ends that are both inclusive; `from` after `to` is rejected.
* **`TaskListViewController`** (app-wide) holds the query and the
  "kept visible" ids. It's app-wide so the filter sheet (a separate route)
  can reach it, and the query survives tab switches during a session.
  * Changing any filter, including the search text, releases kept tasks.
    Changing only the sort doesn't.
  * Leaving the Quests tab releases them too.
  * Kept tasks skip only the *status* filter; search and dates still
    apply.
* **Layout:**
  * A rounded search field under the app bar; it filters as you type,
    since the search runs on the phone's own list and needs no network.
  * Status chips (All / Not completed / Completed / Overdue).
  * Removable chips for active date filters, e.g. "Due: 01-12-2026 –
    10-12-2026 ✕". Tapping one reopens the sheet.
  * App bar: a **sort** menu (four fields + Ascending/Descending, with
    check marks) and a **filter** button (with a dot when date filters
    are active).
* **Date filter sheet:** each of the three dates has a **From** and a
  **To** button. From only = on or after; To only = on or before; both =
  between. The pickers can't produce an invalid range. The sheet edits a
  draft, and nothing changes until **Apply**.
* **Completing from the list** shows "Completed "x"" with **Undo**.
  Reopening shows no snackbar, since it is the "undo" direction itself.
* Done tasks show **"Completed dd-mm-yyyy"** in their subtitle when the
  date is known.
* "No quests match" (with **Clear filters**) is shown when filters hide
  everything, as opposed to "No quests yet" when there are no tasks at
  all.

### D17. Completed quests hidden on the map by default (Phase 4, planned)
*User decision during the PR #4 review.*
* By default the map shows **only open quests**, so finished quests don't
  clutter it.
* A small **toggle button** on the map (next to the zoom buttons) shows or
  hides completed quests. Its icon and tooltip say which state it's in
  ("Show completed" / "Hide completed").
* **Built in Phase 4:** the choice lasts while the app is open and resets
  to "hidden" on restart. This matches the "hidden by default" decision;
  remembering it is easy to add later if wanted.
* "Show on map" on a completed quest still works while completed quests
  are hidden: the focused quest is always drawn.
* Completed quests, when shown, keep the grey check marker (D9).
* The "tasks without locations" badge is unaffected: it still counts all
  tasks without a location.

### D18. Recycle bin and "Delete all completed tasks" (Phase 4c)
*User decision during the PR #4 review. Built in Phase 4c; see "As built"
at the end of this section.*
* **Deleting no longer destroys a task.** It moves the task to the
  **recycle bin**, where it stays for **30 days**. In the bin the user can
  **restore** it (it returns exactly as it was, with the same id) or
  **delete it permanently** (with a confirmation).
* **Implementation: a soft delete.** A new `deleted_at` column (schema v3)
  marks a task as deleted. Normal queries, and therefore the list and the
  map, skip deleted tasks. The bin lists them, newest deleted first,
  showing how many days each has left.
* **Purge:** tasks deleted more than 30 days ago are removed permanently
  when the app starts and when the bin is opened. There is no background
  job, so no battery cost and no extra permissions.
* **Undo stays.** The swipe/delete snackbar now reads "Moved to recycle
  bin" with **Undo**, which simply clears `deleted_at`. This replaces
  Phase 2's re-insert with a new id: the task keeps its id.
* **"Delete all completed tasks"**, in the Quests page's menu:
  * First a confirmation dialog: **"Are you sure? This will move all
    completed tasks to the recycle bin."** with **Yes** and **No**
    buttons. **Yes** moves every completed task to the bin; **No** closes
    the dialog and does nothing.
  * Afterwards a snackbar says how many tasks were moved.
  * If there are no completed tasks, the action is disabled.
* **The bin is opened** from the Quests page's menu ("Recycle bin"), on its
  own page.
* **Ordering with 4b:** 4b adds schema v2 (`completed_at`); 4c adds v3
  (`deleted_at`). They are separate migrations appended in order (the
  append-only rule in D3).

**As built (Phase 4c):**
* **Schema v3:** `deleted_at INTEGER` plus an index on it, so the "not
  deleted" filter on every list query and the purge stay cheap.
* **Repository:** `delete` is gone, so no caller can destroy a task by
  accident. In its place there are explicit operations: `moveToBin`,
  `moveCompletedToBin` (one SQL `UPDATE`, so all-or-nothing),
  `restoreFromBin`, `deletePermanently`, `emptyBin` and `purgeBin`.
  * `getAll`/`getWithLocation` skip binned tasks; `getBin` lists them,
    most recently deleted first.
  * `getById` still finds binned tasks.
  * Moving an already-binned task keeps its original deletion time.
* **`TaskListController`:** keeps `binTasks` next to `tasks`. `load()`
  purges anything binned more than 30 days ago (`binRetention`), which is
  the "on app start" purge. The bin page calls `purgeExpiredBin()` when
  opened.
* **Undo** after swipe or editor delete reads "Moved "x" to the recycle
  bin", and simply restores the task with the same id. Phase 2's
  re-insert with a new id is gone.
* **Quests page "⋮" menu** (always shown, even with no quests, so the bin
  is always reachable):
  * **"Delete all completed tasks"** is disabled when there are none. Its
    dialog: title "Delete all completed tasks?", message **"Are you sure?
    This will move all completed tasks to the recycle bin."**, buttons
    **No** / **Yes**. Afterwards: "Moved N completed tasks to the
    recycle bin".
  * **"Recycle bin"** opens the bin page.
* **Recycle bin page:** each quest shows "Deleted dd-mm-yyyy · N days
  left" (rounded up, so less than a day reads "1 day left"), with
  **Restore** and **Delete permanently** buttons. Deleting permanently
  asks first ("This can't be undone"). An empty bin explains the 30-day
  rule.
* **Added beyond the request:** an **"Empty recycle bin"** button (with
  confirmation). It's the usual counterpart to a bin, and it's disabled
  when the bin is empty.
* The editor's delete dialog now says the quest "will be moved to the
  recycle bin. You can restore it from there for 30 days."
* The temporary dev tools' "Remove demo quests" deletes demo quests
  permanently, including any in the bin, so test data doesn't fill the
  bin.

### D19. Map starts centred on the user (Phase 5; as built: D22)
*User decision, after PR #4.* When the app starts, the map's camera is
chosen in this order:
1. **Current GPS position**, if location services are on and permission is
   granted: centre on the user at street level (zoom ~15).
2. **Last known location**, if there's no current fix (location services
   off, permission denied, or no fix yet): centre there.
3. **Neither available:** the current behaviour (D15): fit all quests, or
   show the whole world if there are none.

**Design notes:**
* **Our own saved "last known location".** The OS's cached position
  (`geolocator.getLastKnownPosition`) is often unavailable when location
  services are turned off, which is exactly the case we need it for. So
  the app also saves every GPS fix it receives (throttled, e.g. at most
  once a minute) in SQLite, and uses that as the fallback.
* **Don't block the map waiting for GPS.** A first fix can take seconds.
  The map opens straight away with the best view available (last known
  location, else fit the quests). When the first GPS fix arrives, the
  camera glides to the user, **but only if the user hasn't touched the
  map yet**. This is the one exception to D15's "the camera only moves
  when the user moves it".
* **Privacy:** the saved location never leaves the phone (local SQLite,
  like everything else), and only the latest position is kept, not a
  history.
* Fits with Phase 4: "show on map" requests still take priority over the
  start-up view.

### D20. Show on map, zoom buttons, completed toggle (Phase 4)
* **`MapFocusController`** (shared app state, `provider`) carries "Show on
  map" requests from the list to the map. A request holds the task id and
  its point.
  * The map consumes each request exactly once (`takeRequest`).
  * A request made before the map exists (first visit to the Map tab)
    becomes the map's starting view, so it's never lost.
  * The highlight is separate from the request. It stays until the user
    taps empty map or focuses another quest.
* **Camera moves** glide over 600 ms (ease in/out), using our own small
  tween over `MapController.move`, because `flutter_map` 8 has no built-in
  animated move. With the OS "remove animations" setting, moves are
  instant. A request is acted on after the current frame, when the Map tab
  is visible and laid out.
* **Highlighted marker:** drawn 1.4x larger with a white halo, above all
  other markers. Its screen-reader label ends in ", selected".
* **List button:** a trailing "Show on map" icon (`travel_explore`) on
  tiles with a location only. It appears as soon as a task gets a location.
* **Map controls** (`MapControls`, bottom-right above the attribution
  button), in Google Maps style: a 40 x 40 completed-quests toggle, and a
  "+ / −" pair of 40 x 40 buttons in one rounded panel. Each zoom step is
  one level, animated. "+" is disabled at zoom 19 and "−" at zoom 1. The
  current zoom is tracked through `onPositionChanged`; updates that arrive
  during layout are deferred to after the frame.
* **The starting view** is computed from the *visible* quests, so hidden
  completed quests don't pull the camera away.
* **Test note:** `flutter_map` doesn't build markers that are off screen,
  so map tests place quests close together. Its single-tap callback fires
  only after the double-tap window, so tests advance time after a tap.

### D21. Undo snackbars: 4 seconds, and never covering "New quest"
*User request during the PR #8 review.*
* **Every snackbar with "Undo" disappears after 4 seconds.** Flutter keeps
  a snackbar that has an action button on screen until it's tapped
  (`SnackBar.persist` defaults to true when there's an action), so they
  appeared to stay forever. All Undo snackbars now come from one helper
  (`undoSnackBar`, `persist: false`, 4 s), so they behave the same
  everywhere.
* **The "New quest" button moves up above a snackbar, and back down when
  it's gone.** Flutter does this automatically, but only for a snackbar in
  the *same* Scaffold. Flutter shows snackbars only in the outermost
  Scaffold, which is the app shell's, while the button lives in the
  Quests page's own Scaffold. The Quests page therefore has its own
  `ScaffoldMessenger`, so its snackbars appear inside the page. Actions
  that show snackbars use a context *below* that messenger (the tile's
  context), not the page State's own context, which sits above it.
* A full-app widget test covers the real nesting. It was confirmed to
  fail without the fix.

### D22. GPS as built (Phase 5)
Builds D8 and D19. Code: `LocationService` (interface, `geolocator`
behind it), `LocationController` (app state), `LastLocationRepository`
(SQLite, schema v4), and the map's player dot, my-location button and
permission prompt.
* **The app never asks for permission by itself.** At start-up it only
  *checks*. While permission can still be asked, the map shows a small
  card: "See where you are among your quests … never leaves your phone",
  with **Allow** / **Not now**. The OS dialog appears only after
  **Allow** (D8's "explain → request"). "Not now", or refusing in the OS
  dialog, hides the card for the rest of the app session; the
  my-location button can still ask. *Why:* a bare OS dialog at launch,
  before the user has even seen the map, is the most common reason people
  refuse, and Android stops showing the dialog after two refusals.
* **"Blocked" and "location off"** are handled by the my-location button
  (crossed-out icon): tapping it explains the problem and offers **Open
  settings** (the app's settings page, or the phone's location settings).
  No card is shown for these, because the app can't fix them itself.
* **My-location button** (top of the map controls, Google-Maps style):
  * Tap: centre on the user at street level (zoom 15, or keep a closer
    zoom) and **follow** them: the camera moves with each new fix.
  * **Dragging or pinching the map ends follow mode.** The zoom buttons
    don't: they zoom around the centre, which is the user.
  * Icons: filled crosshair = following, empty = available, crossed out =
    unavailable. Before the first fix: "Finding your location…".
* **Player marker:** a blue dot with a white ring, inside a pale accuracy
  circle drawn in metres (not drawn above 2 km: that circle would only
  cover the screen). It's drawn *below* the quest markers, so a quest at
  the user's position can still be tapped. No heading arrow: the GPS
  heading is only meaningful while moving, so it would mostly point
  nowhere.
* **The dot disappears** when location becomes unavailable (switched off,
  permission withdrawn). The map never shows a stale position as if it
  were live; the saved position is used only for the starting camera.
* **Start-up (D19):** a pending "Show on map" request → live fix → saved
  last-known position → fit the quests. Because the map is built at app
  start (kept alive in the `IndexedStack`), there's normally no live fix
  yet. The first fix then glides the camera to the user, unless the user
  has already dragged the map, used a map button or "Show on map".
* **Saving the last-known position:** the first fix, then at most once a
  minute, plus once when the app goes to the background (so the latest
  position isn't lost). One row only (`last_location`, `id = 1`), never
  a history.
* **Foreground only:** the GPS stream stops when the app goes to the
  background and restarts when it returns. Permission and the location
  setting are re-checked then, because the user may have changed them in
  the system settings. The phone's location switch is also watched while
  the app is open.
* **Robustness:** if the GPS stream fails while everything looks allowed,
  it's retried after 5 s, never in a tight loop. Location errors never
  crash the app; they only change the status.
* Updates only after moving ≥ 5 m (`distanceFilter`), high accuracy.
* **Build note:** `android/gradle.properties` now sets
  `kotlin.incremental=false`. Kotlin's incremental compiler failed
  ("Could not close incremental caches") because the plugins' sources (pub
  cache on C:) and the project (D:) are on different drives. This is
  project-local and only makes Kotlin compiles slightly slower.

### D23. Placing a quest on the map (Phase 6)
Two ways, both ending in the normal task editor:
* **"Pick on map" in the editor.** The editor has a location row, laid
  out like the due-date row: "No location" with a **Pick on map**
  button, or the address / "Pinned on the map" with the coordinates
  underneath and an ✕ to remove it. Tapping the row opens the picker.
* **Long-press on the world map** → the new-quest editor opens with
  that point already filled in (R7: "place a task by tapping a point on
  the map"). A short vibration confirms the long-press. A plain tap
  still clears the highlight (D20), so the two don't clash.

**The picker** (full screen):
* **The pin stays in the middle and the map moves under it**, as in
  most map apps, instead of dragging a small marker. A finger dragging a
  marker hides it, and small drags are hard to aim. The pin's tip marks
  the exact point (a small dot sits under it).
* Tapping or long-pressing a spot glides it under the pin.
* A card at the top says what to do and shows the coordinates under the
  pin, updating as the map moves.
* My-location and zoom buttons, the same as on the world map (shared
  `MapControls` and `ensureLocationAccess`). The completed-quests toggle
  is left out, because the picker shows no quests.
* **Starts at** the quest's current location, else the user's position
  (live or last known), else the whole world.
* **"Use this location"** returns the point under the pin; the back
  button cancels and changes nothing.

**Details:**
* Picked points are **rounded to 6 decimals** (≈ 0.1 m) and the
  longitude is wrapped into −180…180 (the map can be panned past the
  date line).
* **Changing the location clears the address**, because the old address
  would describe the old point. Picking the same point keeps it.
  Phase 7 fills in addresses (reverse geocoding on save, D6).
* The base map is provided app-wide (`MapBaseLayer`), so the picker
  draws the same map, and tests replace it with an empty one.
* The camera glide moved into a shared `CameraAnimator`, so the world
  map and the picker move the camera the same way.

**Changed during the PR #10 review (user requests):**
* **After removing a location, "Pick on map" reopens at the removed
  location**, not at the user's position. Re-pinning is usually a small
  adjustment, so panning back from wherever the user is would be
  annoying. If the same point is picked again, its address comes back
  too. Saving without picking still saves "no location".
* **The map credits are always on top.** flutter_map's attribution
  widget must be drawn inside the map, so the map buttons covered its
  open popup. It's replaced by our own `MapAttribution` (an "i" button
  that opens a "Map credits" card with the same three lines), placed last
  on both map pages so nothing covers it.
* Found while doing that: flutter_map's attribution widget had been the
  thing stretching the map to fill the page. Without it, the map shrank
  to nothing while the base map was still loading. Both map pages now
  use `StackFit.expand`, so the map always fills the page.

### D24. Address search and lookup as built (Phase 7)
Builds D6. Code: `NominatimGeocoder` (HTTP), `RateLimiter`,
`CachingGeocodingService` + `SqfliteGeocodeCache` (schema v5), the search
card in the location picker, and the background address lookup in
`TaskListController`.

**Where the user searches:** in the location picker (D23), not in a
separate screen. A search field sits at the top: type an address and
press Search (keyboard or the → button). The results (at most 5) show a
short label and the full name; tapping one glides the map there. So one
screen does both: search for the address, then fine-tune by moving the
map. In the editor, the button is now **Add location** (it's no longer
only "pick on map"), and the picker is titled **Choose location**.

**Nominatim policy, and how it's met:**
* **≤ 1 request per second, none in parallel:** every request goes
  through one shared `RateLimiter` (start-to-start ≥ 1.1 s, one at a
  time, a failure doesn't block the queue).
* **No autocomplete:** a search runs only when the user presses Search,
  never while typing (tested).
* **Identifying User-Agent:** `QuestMark/1.0.0` (`AppInfo`, now shared
  with the map tiles).
* **Caching:** answers are kept in SQLite for 30 days, keyed by the
  normalised query (trimmed, lower-case, single spaces) or by the point
  rounded to 5 decimals (≈ 1 m). "No results" and "no address" are cached
  too; errors are not, so they can be retried. Old rows are removed when
  new ones are written, so the table can't grow forever. If the cache
  fails, geocoding still works, just uncached.
* Attribution: the results are OSM data, already credited on the maps.

**Addresses (reverse geocoding):**
* Choosing a search result gives the quest that result's address, as
  long as the pin is still within 5 m of it. If the user then moves the
  map elsewhere, the address is dropped (it would describe the wrong
  place).
* A quest saved with a location but **no address** (placed by moving the
  map, or by long-press) gets its address looked up **after** saving, in
  the background: the save never waits for the network. If the lookup
  fails (offline), the quest keeps showing coordinates and the next save
  tries again. A lookup never overwrites anything: if the quest was moved,
  given an address or binned in the meantime, the result is dropped.
* **Short labels:** Nominatim's full names are very long ("Oodi, 4,
  Töölönlahdenkatu, Kluuvi, Eteläinen suurpiiri, Helsinki, …, Suomi /
  Finland"). The app stores a short one: place name, "street number",
  town ("Oodi, Töölönlahdenkatu 4, Helsinki"). The full name is shown
  under each search result to tell similar places apart. The "street
  number" order suits Finland and most of Europe; the US order ("number
  street") could be added if needed.

**Errors** are shown in the search card in plain words: no connection,
service busy (HTTP 429), service unavailable, unreadable answer.

**Privacy note (user decision, PR #11 review):** under the search field
the picker says "Searches and quest locations are sent to OpenStreetMap's
Nominatim service to find addresses. Your own location is never sent."
(The last sentence was added at the user's request.) It's true: the GPS
position is never sent, so the location card's "never leaves your phone"
stays true for it.

**Changed in Phase 8b (user decision, D26):** downloaded map areas are
named with Nominatim, so for "my area" a rough position (rounded to about
1 km) is sent. The note now ends "Your own location is only sent, rounded
to about 1 km, to name a map area you download.", and the location card
says the same.

**Not done (possible later):** biasing results towards the visible map
area (Nominatim's `viewbox`). It would make cache hits rarer, so it was
left out for now; adding the town to the query works well.

### D25. The bundled world map as built (Phase 8a)
Builds level 1 of D7.

**Size check (D7's open question), and the user's decision:**
* **Zoom 0–5 is too big:** the builder hit OpenFreeMap's 50 MB
  per-download cap after 1,154 of the 1,365 tiles and stopped (nothing was
  written). Low-zoom tiles are large, about 160 KB each even gzipped,
  because each one covers a huge area.
* **Zoom 0–4 ships:** 341 tiles, **28.7 MB** (zoom 2–3: 16 MB, zoom 4:
  13 MB). The user chose it over zoom 0–3 (~14 MB, continents and
  countries only), accepting that it's a little over the ~25 MB goal.
* **Cost on the phone:** about +28.5 MB of app download (the tiles are
  already compressed), plus a 28.7 MB copy in app storage, because SQLite
  can only open real files. About 57 MB in total. To revisit in Phase 9
  if it matters (e.g. drop the zoom-4 tiles of open ocean).

**The builder** (`tool/build_world_map.dart`, run once on a PC; unit
tested against a fake server):
* reads the Liberty style and its TileJSON, then downloads every tile of
  zoom 0..N, 2 at a time, with `QuestMark/1.0.0`;
* checks the tile count (≤ 3,000) *before* downloading, and stops at
  50 MB; any failure stops all requests and writes nothing;
* retries 429 / 5xx with a growing delay; 404 means "no tile here";
* writes `assets/map/world.mbtiles` (tiles gzipped, TMS rows),
  `world.json` (version, size) and `offline_style.json`.

**The offline style:** Liberty, cut down to what works with no network:
only the OpenFreeMap vector source (served from the file), no shaded
relief (a separate raster source), no `sprite` (icons) and no `glyphs`
(map fonts). Labels then use the phone's own fonts. At zoom 0–4 the
difference is small.

**In the app:**
* **First launch:** the map is copied from the assets into app storage
  (`world_map_<version>.mbtiles`, next to the database), written to a
  temporary name and renamed when complete. Later launches reuse it. An
  app update with a new map replaces it and deletes the old one.
* **Online (normal):** zoom 0–4 come from the file, **with no network
  requests at all**; closer zooms come from OpenFreeMap and its disk
  cache, as before. If the file lacks a low-zoom tile, the network is
  asked instead.
* **Never online yet (no cached style):** the bundled offline style is
  drawn from the file alone, so the whole world shows even on the very
  first launch without a connection. Zooming in enlarges the zoom-4
  tiles. A small "Offline world map · Retry" banner sits at the bottom;
  Retry switches to the online map once the connection is back, and a
  failed retry keeps the offline map on screen.
* Only if there's neither a connection nor a world map is the old "Couldn't
  load the map" banner shown.
* The vector-tile package is now used in two files:
  `lib/ui/map/base_map_layer.dart` and `lib/ui/map/world_map_tiles.dart`
  (CLAUDE.md updated). Reading the MBTiles file (`MbTilesArchive`) and
  copying it (`WorldMapInstaller`) live in `lib/data`.

**For Phase 8b:** with the world map ending at zoom 4, downloaded regions
should cover zoom **5**–14 (not 6–14 as first planned in D7), so offline
there's no zoom level that nothing covers. The tile-count maths changes
slightly.

**A bug found while running the builder:** `sqflite` resolves a relative
path against its own databases folder, so the first zoom 0–4 run wrote
the file under `.dart_tool/`. It was moved into place (no second
download), and the builder now makes the path absolute, with a test.

### D26. Region downloads as built (Phase 8b)
Builds level 2 of D7 (R11). The user's choices: **sizes Small / Medium /
Large**, **place names from Nominatim**, **the Offline maps button on the
map**, and a **one-off tile-size sample** before the estimates were written.

**Tile sizes measured** (23-11-2026; 96 tiles, 3.8 MB, 1 at a time,
`QuestMark/1.0.0`), gzipped, averages:

| Area | zoom 14 | zoom 12 | zoom 10 |
|---|---|---|---|
| Central London | 69 KB | 109 KB | 142 KB |
| Dundee | 8 KB | 26 KB | 46 KB |
| Rural Highlands | 2 KB | 2 KB | 23 KB |

So a large area fits easily in the countryside, but in a big city 3,000
detailed tiles would be ~200 MB, four times OpenFreeMap's 50 MB limit.

**Sizes.** Counted in zoom-14 tiles across, so the 3,000-tile limit holds
everywhere on Earth. In km the same square is wider near the equator.

| Size | Tiles across | Width at Dundee | Tiles (zoom 5-14) |
|---|---|---|---|
| Small | 15 | ~20 km | ~350 |
| Medium (default) | 29 | ~39 km | ~1,170 |
| Large | 45 | ~61 km | ≤ ~2,860 (tested) |

A region is that square at zoom 14, plus every zoom 5-13 tile overlapping
it. Zoom 0-4 are left out (the bundled world map has them, D25).

**Middle first, and the 50 MB limit.** Tiles are downloaded in rings from
the centre outwards, every zoom of a ring before the next ring. The download
stops just under 50 MB (counted over the whole region, resumes included).
What's on the phone is then a smaller but complete square around the
centre ("Ready offline: the middle 18 km. Stopped at OpenFreeMap's 50 MB
limit"), which can't be resumed (that would be a second download of the
same area). The estimate is a range, countryside to big city, e.g. "≈ 39 km
across · 1,167 tiles · 3.7–50 MB".

**Downloading** (`RegionDownloader`, `OpenFreeMapTileFetcher`):
* the tile URL comes from OpenFreeMap's TileJSON (it changes weekly);
  2 requests at a time, `QuestMark/1.0.0`; never tile.openstreetmap.org;
* tiles are kept as downloaded (gzipped), and their size is the real
  download size (no automatic unzipping);
* 429 / 5xx and lost connections are retried after 2, 6 and 15 s; after
  that, or for any other error, the download pauses with the reason
  ("Paused: no connection");
* **Pause / Resume / Delete** in Offline maps. Resume skips tiles the
  region already has. A download running when the app is closed shows as
  "Paused: the app was closed"; the app **never resumes by itself**.
* One download at a time.

**Storage** (`OfflineRegionStore`): its own SQLite file,
`offline_maps.db`, apart from the quests: `tiles` (each tile once),
`region_tiles` (which region has which tile), `regions` (name, centre,
size, status, progress, bytes) and `settings`. A tile another region already
has is shared instead of downloaded again; deleting a region removes only
tiles no other region uses, then `VACUUM` gives the space back.

**Drawing:** zoom 0-4 from the world map, zoom 5-14 from downloaded
regions, everything else from OpenFreeMap and its cache (D7's order). With
no connection and no cached style, the bundled offline style draws the
regions too.

**Offering the user's area.** A card at the top of the map, after a GPS fix
and only when the user is outside every region (finished or not):
"Download the map for your area?" with the size, the estimate, and
**Download / Not now** (until restart) **/ Don't ask again** (a switch in
Offline maps turns it back on). The location card comes first when both
apply.

**Offline maps screen** (download button with the map buttons): the
regions with state, date, size and width; progress while downloading;
Pause, Resume, Rename, Delete (Yes/No); total space used; "Download an
area" opens a map with a square to frame the area, the size choice and the
estimate.

**Names and privacy (user decision).** A region is named after its town
(Nominatim reverse lookup at town level, cached). The centre is **rounded
to 2 decimals (~1 km)** before it is sent. For "my area" that is the user's
rough position, so the privacy texts changed:
* picker: "Searches and quest locations are sent to OpenStreetMap's
  Nominatim service to find addresses. Your own location is only sent,
  rounded to about 1 km, to name a map area you download."
* location card: "QuestMark shows your position on the map while the app is
  open. It stays on your phone, except a rough position (about 1 km) to name
  a map area you download."
* the download card and the area picker say where the name comes from.

Until a name is found the region is "My area" or "Map area"; renaming it
wins over a name that arrives later.

**Known limit (fixed in D27):** the map package copied every tile it drew
into its disk cache (100 MB cap), downloaded ones included.

### D27. Offline: enlarged stand-in tiles, and the app's own tile cache (PR #13 review)
**User report:** offline, outside downloaded areas, zooming past 4 made the
map go white, with only a glimpse of the map while zooming. Expected: the
low-detail map simply enlarged (water still blue, rough coastlines).

**Why it happened:** the map package asks for each zoom level's own tiles.
Offline they fail, and the package draws them empty. It only shows the
enlarged parent tile *while* a tile is loading (the glimpse), never after a
failure, and that can't be changed from outside the package.

**Fix: stand-in tiles.** When a tile can't be had, the app makes one: it
takes the nearest less detailed tile that is on the phone (a downloaded
region's, a cached one, or the world map's zoom-4 tile), cuts out the part
under the wanted tile and enlarges it (`overzoomMvt`, pure Dart, in a
background isolate). Shapes are scaled, moved and clipped to the tile plus
a small margin; names and classes are copied, so the style draws it as
usual. Tested on the real bundled tiles.

**Why the app now keeps its own tile cache** (`map_cache.db`, 100 MB, 30
days): the package's disk cache would have saved a stand-in as the real
tile for 30 days, so after reconnecting the user would still see the
low-detail version. The package's cache isn't reachable from outside, so
the vector tiles no longer go through it. This also fixes D26's known limit
(downloaded tiles were being copied into that cache). The package cache now
only holds the shaded-relief images and is lowered to 20 MB, so it clears
out the tiles it held before.

**Tile order now** (`LocalFirstTileProvider`):
1. zoom 0-4: the world map;
2. zoom 5-14: downloaded regions;
3. the app's cache, if under 30 days old;
4. OpenFreeMap; what arrives is cached;
5. network failed: the cached copy even if old, else a stand-in, which is
   **never cached**.

When the network answers again after a stand-in was shown, the map reloads
once (a new memory-cache key), so the real tiles replace the stand-ins.
The bundled offline style (no style cached yet) uses the same order without
the network.

**Also from the review: deleting an area** can take a few seconds (SQLite
deletes the tiles and then compacts the file). The area now shows
"Deleting…" with a moving bar, and its menu is hidden, until it's gone.

### D28. Settings: dark mode and high contrast mode (Phase 9a)
**User decisions (start of Phase 9):** no change to how the map looks (no
game-style map theme); the map buttons stay as they are. Add **dark mode**
and a **high contrast mode** on a **Settings page**, opened from a gear item
in the Quests page's "⋮" menu, below "Recycle bin".

**Settings page:**
* **Theme:** System default (follows the phone, as before, and the
  default) / Light / Dark mode, as radio buttons, so all three choices are
  visible at once.
* **High contrast mode:** a switch, off by default.
* Changes apply at once and are saved.

**Storage:** a `settings` table (key → text value) in the app database,
**schema v6**. The settings are loaded in `main.dart` *before* the first
frame, so the app never shows the wrong theme for a moment. A broken read
or write never stops the app: the defaults (or the change, for this session)
still apply. `SettingsController` (ChangeNotifier) sits above `MaterialApp`.

**High contrast theme** (`buildQuestTheme(..., highContrast: true)`):
* Material 3's highest contrast level for the colours generated from the
  quest gold (`ColorScheme.fromSeed(contrastLevel: 1.0)`);
* the background pure white (light) or pure black (dark), with text in the
  opposite colour (21:1);
* secondary text and outlines in the full text colour, thicker dividers;
* buttons tested to meet WCAG AAA (7:1) in light and dark.

On iOS, the phone's own "Increase Contrast" setting also switches it on,
through `MaterialApp`'s `highContrastTheme` (Android doesn't pass its
high-contrast setting on to Flutter apps, so there it's the in-app switch). **Not changed:** the map tiles and the quest marker
colours (the map look stays as it is); the map buttons follow the theme
like the rest of the app.

### D29. Polish: map speed, the long-press tip, the map cache in Settings (Phase 9b)
**User decisions:** keep the map labels as they are (no `LabelMode.tile`);
keep the 100 MB browse cache, but show its size in Settings with a way to
clear it; a one-time long-press tip; the release step (removing the debug
tools, the app id) in a separate commit, so it can be reverted.

**Map speed, with no change to the look:**
* The map page kept the zoom in its state and rebuilt itself (markers,
  buttons) on **every frame of a zoom**, only to grey out "+" / "−" at the
  limits. It now tracks only whether each button is enabled, so it
  rebuilds only when one changes.
* 64 MB of decoded tiles kept in memory (the package's default is 24 MB),
  so zooming back and forth re-reads less; 4 decoding workers instead of 3.
* For each tile, the downloaded regions and the browse cache are looked up
  at the same time, not one after the other.
* Not done (user decision): labels drawn into the tiles, and a lighter map
  style. Both would change the look. How smooth it is should be judged on
  a **release build** (`flutter run --release`): debug builds are several
  times slower at drawing.

**Long-press tip:** a small card on the map, "Tip: long-press the map to
add a quest at that spot", with "Got it". It sits above the bottom-left
badge and left of the map buttons, so it never covers the cards at the top.
It goes for good after "Got it" or the first long-press, and is remembered
in the settings table.

**Map cache in Settings:** a "Storage" section: "Map cache: 34 MB of up to
100 MB", what it's for, and **Clear**. Clear asks first (browsed maps
download again; downloaded areas and the world map are kept), then shows
"Clearing…" with a moving bar. The size is read again each time Settings
opens. `MapCacheController` sits between the page and the cache.

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
| **3. Map + quest markers** | ✅ Done (PR #4) | `feature/03-map` | `flutter_map` + OpenFreeMap vector tiles with persistent cache and attribution; quest markers for located tasks; tap a marker → task details | marker state mapping, tile source config, marker rendering |
| **4. Show on map** | ✅ Done (PR #6) | `feature/04-show-on-map` | Map button on list items that have a location → Map tab, centred on the task, marker highlighted. Map **zoom +/− buttons** (they share the map controller). **Completed quests hidden on the map by default, with a show/hide toggle** (D17) | focus controller, button hidden without location, tab switch, zoom buttons and limits, completed toggle |
| **4b. List search, filter & sort** | ✅ Done (PR #7) | `feature/04b-list-filters` | One list (no Completed section), search bar, filters and ascending/descending sorting as specified in D16; `completed_at` column (schema v2) | filter/sort rules (pure), migration v1→v2, ticked tasks stay in place, list widget tests |
| **4c. Recycle bin** | ✅ Done (PR #8) | `feature/04c-recycle-bin` | Deleting moves a task to a recycle bin for 30 days (restore or delete permanently); automatic purge after 30 days; "Delete all completed tasks" with a Yes/No confirmation (D18); `deleted_at` column (schema v3) | soft delete/restore, purge at 30 days, migration v2→v3, bin screen, confirmation Yes/No paths |
| **5. GPS** | ✅ Done (PR #9) | `feature/05-gps` | Location service, permission flow, player marker, re-centre / follow. **Map starts centred on the user** (D19): GPS → last known location → fit the quests | fake location stream moves the marker, permission-denied state, start-up view fallback order, saved last location |
| **6. Pin on map** | ✅ Done (PR #10) | `feature/06-pin-location` | Location picker in the task editor (pin fixed in the middle, the map moves under it), plus long-press on the world map for a new quest there (D23) | picker returns coordinates, editor saves them |
| **7. Address search** | ✅ Done (PR #11) | `feature/07-address-search` | Nominatim geocoding + reverse geocoding, rate limiter, SQLite cache | rate limiter spacing, cache hit avoids HTTP, JSON parsing, errors |
| **8a. Bundled world map** | ✅ Done (PR #12) | `feature/08a-world-map` | Dev script that builds the z0–5 world MBTiles; bundled asset; copy on first launch; offline rendering | asset copy, tile lookup, fallback order |
| **8b. Region download** | ✅ Done (PR #13) | `feature/08b-region-download` | Current-region prompt, Offline maps screen, estimate → throttled download → resume/cancel → list/delete | tile count maths, 3,000-tile cap, concurrency limit, resume, shared-tile deletion |
| **9a. Settings** | ✅ Done (PR #14) | `feature/09a-settings` | Settings page from the Quests "⋮" menu (gear, below Recycle bin): dark mode (System / Light / Dark) and high contrast mode, saved in SQLite (schema v6) (D28) | settings saved and loaded, migration v5→v6, theme contrast ratios, menu position, theme switches the whole app |
| **9b. Polish** | 🚧 In progress | `feature/09b-polish` | Map speed with no change to the look; one-time long-press tip; the map cache's size and Clear in Settings (D29); the release step in its own commit (debug tools removed, app id) | no rebuild while zooming between limits, layer settings, tip shown/dismissed/remembered, cache size and clear, confirmation |

---

## 5. Open questions

**Before release (to do when the app is finished):**
* Remove the temporary developer tools: `lib/dev/`, the `DevToolsButton`
  in the Quests app bar, and `test/dev/`.
* Replace the template app id `com.example.questmark`.
* None blocking right now. To revisit in Phase 8a: the bundled world-map
  size, and whether zoom 0–5 fits the size goal.
