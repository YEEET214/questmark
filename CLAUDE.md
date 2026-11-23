# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

QuestMark is a Flutter/Dart to-do app. Tasks can have a location and are shown on an OpenStreetMap world map as open-world-game-style "quest markers", together with the phone's live GPS position (no route planning). Storage is local SQLite only.

**`docs/PLAN.md` is the source of truth** for requirements, the phased roadmap, the decision log (D1, D2, …) and open questions. Read it before starting work, and update it when a decision changes, and update the Status column of the phase table when a phase starts or its PR is merged.

## Working agreement with the user

- Build phase by phase as laid out in `docs/PLAN.md`. Never implement several phases in one go. After each phase, report progress and wait for the user's go-ahead.
- Every feature gets unit and/or widget tests. `flutter test` and `flutter analyze` must pass before committing.
- Test counts in commit messages and PRs must come from the test runner (`flutter test <file>`, the `+N` in the final line), never from counting by hand. Hand counts have been wrong twice.
- Git: one branch per feature (`feature/<NN>-<short-name>`), with detailed commits on it (what was done, why, how it was tested). When it's done and green, push the branch and **open a pull request into `main`** (description: summary, design choices, testing). Merge only after the user approves, with `gh pr merge <n> --merge` (a merge commit, never squash or rebase). Then `git checkout main && git pull`. Never merge feature branches into `main` locally.
- **Never delete branches, on GitHub or locally.** Only the user deletes branches, manually, after merging a PR. Never use `gh pr merge --delete-branch`, `git push --delete`, `git push origin :<branch>` or `git branch -d/-D`, and keep the repo setting "Automatically delete head branches" off. Local branches whose remote is gone are left alone too.
- Docs-only changes (plan updates) go on a `docs/<short-name>` branch with their own PR, like features.
- **Ask the user for permission before installing, uninstalling, upgrading or otherwise modifying anything on their system** outside this repository. This covers system tools and CLIs (e.g. GitHub CLI), SDKs (`flutter upgrade`, Android SDK components), global packages, PATH or environment variables, and global git/IDE config. Say what will change and why, and wait for a yes. Project-local changes (e.g. `flutter pub add` editing pubspec.yaml) are part of normal work and don't need this.
- `gh` is installed but not on the bash PATH: call it as `"/c/Program Files/GitHub CLI/gh.exe"` (bash) or `& "C:\Program Files\GitHub CLI\gh.exe"` (PowerShell). It is already authenticated.
- Gradle must never install SDK components on its own: `android/gradle.properties` sets `android.builder.sdkDownload=false`. If a build fails because a component (CMake, NDK, platform) is missing, ask the user before installing it. It also sets `kotlin.incremental=false`: Kotlin's incremental compiler breaks because the pub cache (C:) and the project (D:) are on different drives. Widget tests must not hit the network: pass `mapBaseLayer: const SizedBox.shrink()` to `QuestMarkApp`, or `baseLayer:` to `MapPage`.
- **Emulator:** the user's Android emulator is "MySmallPhone" (`emulator-5554`, 720x1280). **Never start or stop the emulator yourself; it sometimes crashes.** When you want to test on it, ask the user to start it and wait for their go-ahead. Once they say it's running, `flutter run -d emulator-5554` may be used. Screenshots: `"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" -s emulator-5554 exec-out screencap -p > shot.png` (save in the scratchpad).
- Temporary debug-only developer tools live in `lib/dev/` (bug icon in the Quests app bar: add/remove "[Demo] " quests). They must be removed before release (PLAN.md section 5).
- Targets are Android **and** iOS. Development is on Windows, so iOS config (Info.plist etc.) must be written but cannot be built here.
- Explain design choices and the reasoning behind them to the user, and record significant ones in the PLAN.md decision log.

## Commands

```bash
flutter pub get                               # install dependencies
flutter analyze                               # lint (flutter_lints; platform dirs excluded)
flutter test                                  # all tests
flutter test test/path/to/file_test.dart      # single file
flutter test --plain-name "test name"         # single test by name
flutter run                                   # run on connected device/emulator
```

The environment is Windows (Flutter 3.47.x / Dart 3.13.x).

## Architecture (as planned in docs/PLAN.md)

Layering: **UI → state (`ChangeNotifier` via `provider`) → repositories/services → SQLite/HTTP/GPS**. The UI never touches SQLite, HTTP or GPS directly. Services (location, geocoding, tile download) are abstract classes so tests can inject fakes. `test/` mirrors `lib/`.

- `lib/models`, `lib/data` (sqflite helper + versioned migrations + repositories), `lib/services`, `lib/state`, `lib/ui/{tasks,map,offline}`.
- SQLite tests use `sqflite_common_ffi` with an in-memory database, so they run under plain `flutter test` without an emulator.
- Map: `flutter_map` 8.3.2 + `flutter_map_vector_tiles` 2.11.0 (exact pins; package use confined to `lib/ui/map/base_map_layer.dart` and `lib/ui/map/world_map_tiles.dart`), drawing **OpenFreeMap vector tiles** (OSM data). Markers are Flutter widgets. List → map navigation goes through a shared `MapFocusController`, not direct widget access.
- GPS: `geolocator`, foreground position stream only.
- Offline maps: a bundled zoom 0–4 world MBTiles asset (`assets/map/`, built once by `dart run tool/build_world_map.dart`, which downloads from OpenFreeMap: ask the user before running it; copied to app storage on first launch; zoom 0–5 was over the 50 MB cap, PLAN.md D25), plus user-approved region downloads (zoom 5–14, Small/Medium/Large squares counted in zoom-14 tiles, middle first, overzoomed beyond 14) into their own SQLite file `offline_maps.db` (`tiles`, `region_tiles`, `regions`, `settings`; PLAN.md D26). Tile lookup order (PLAN.md D27): world map (zoom 0–4) → downloaded regions → the app's own browse cache (`map_cache.db`; the package's disk cache isn't used for vector tiles) → OpenFreeMap → offline: stale cache, else a stand-in tile made by enlarging the nearest less detailed one (`lib/services/mvt_overzoom.dart`), never cached.

### Map/API usage constraints (hard rules)

These policies shape the design, so don't work around them:
- **Never fetch from `tile.openstreetmap.org`.** Its policy forbids offline use and prefetching entirely, with no low-zoom exception. That is why tiles come from OpenFreeMap.
- **OpenFreeMap offline downloads**: ≤3,000 tiles or 50 MB per download, ≤4 parallel requests (we use 2), and a unique stable `User-Agent` (`QuestMark/<version>`). Show the "© OpenMapTiles, data © OpenStreetMap contributors" attribution.
- **Nominatim geocoding**: ≤1 request/second (client-side rate limiter), search only on explicit submit (no autocomplete), cache results in SQLite with normalised query keys.
- Region downloads start only after the user explicitly agrees.
