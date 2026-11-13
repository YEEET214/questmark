# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

QuestMark is a Flutter/Dart to-do app. Tasks can have a location and are shown on an OpenStreetMap world map as open-world-game-style "quest markers", together with the phone's live GPS position (no route planning). Storage is local SQLite only.

**`docs/PLAN.md` is the source of truth** for requirements, the phased roadmap, the decision log (D1–D11) and open questions. Read it before starting work, and update it when a decision changes or a phase is completed.

## Working agreement with the user

- Build phase by phase as laid out in `docs/PLAN.md`. Never implement several phases in one go. After each phase, report progress and wait for the user's go-ahead.
- Every feature gets unit and/or widget tests. `flutter test` and `flutter analyze` must pass before committing.
- Git: one branch per feature (`feature/<NN>-<short-name>`), with detailed commits on it (what was done, why, how it was tested). When it's done and green, push the branch and **open a pull request into `main`** (description: summary, design choices, testing). Merge only after the user approves, with `gh pr merge <n> --merge` (a merge commit, never squash or rebase). Then `git checkout main && git pull`. Never merge feature branches into `main` locally.
- **Ask the user for permission before installing, uninstalling, upgrading or otherwise modifying anything on their system** outside this repository. This covers system tools and CLIs (e.g. GitHub CLI), SDKs (`flutter upgrade`, Android SDK components), global packages, PATH or environment variables, and global git/IDE config. Say what will change and why, and wait for a yes. Project-local changes (e.g. `flutter pub add` editing pubspec.yaml) are part of normal work and don't need this.
- `gh` is installed but not on the bash PATH: call it as `"/c/Program Files/GitHub CLI/gh.exe"` (bash) or `& "C:\Program Files\GitHub CLI\gh.exe"` (PowerShell). It is already authenticated.
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
- Map: `flutter_map` + `vector_map_tiles`, drawing **OpenFreeMap vector tiles** (OSM data). Markers are Flutter widgets. List → map navigation goes through a shared `MapFocusController`, not direct widget access.
- GPS: `geolocator`, foreground position stream only.
- Offline maps: a bundled zoom 0–5 world MBTiles asset (copied to app storage on first launch), plus user-approved region downloads (zoom 6–14, overzoomed beyond 14) into an app-managed SQLite tile store with a `regions` table. Tile lookup order: downloaded regions → online/cached tiles → bundled world map.

### Map/API usage constraints (hard rules)

These policies shape the design, so don't work around them:
- **Never fetch from `tile.openstreetmap.org`.** Its policy forbids offline use and prefetching entirely, with no low-zoom exception. That is why tiles come from OpenFreeMap.
- **OpenFreeMap offline downloads**: ≤3,000 tiles or 50 MB per download, ≤4 parallel requests (we use 2), and a unique stable `User-Agent` (`QuestMark/<version>`). Show the "© OpenMapTiles, data © OpenStreetMap contributors" attribution.
- **Nominatim geocoding**: ≤1 request/second (client-side rate limiter), search only on explicit submit (no autocomplete), cache results in SQLite with normalised query keys.
- Region downloads start only after the user explicitly agrees.
