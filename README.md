# QuestMark

A to-do app with the feel of an open-world video game map. Your tasks are **quests**: give one a place and it appears as a quest marker on a world map, next to your live GPS position.

Built with Flutter for **Android** and **iOS**. Everything is stored on your phone; there is no account and no server of our own.

### Disclaimer
This project was made with Claude Code on the Opus 5.5 model.

<p align="center">
  <img src="assets/icon/app_icon.png" alt="QuestMark app icon" width="120">
</p>

## Features

**Quests**
- Add, edit, complete and delete quests, with an optional description and due date.
- Search, filter (status, due or completed date) and sort the list. Completing a quest never moves it out from under your finger.
- Deleted quests go to a **recycle bin** for 30 days and can be restored. "Delete all completed tasks" asks before it does anything.

**The map**
- Quests with a place are shown as **quest markers**: gold for active, orange for due soon, red for overdue, grey for completed (hidden by default, with a toggle).
- **Show on map** from any quest in the list.
- Your **GPS position**, with a my-location button that follows you. Location is only used while the app is open and is never stored as a history. There is no route planning.
- Place a quest by **long-pressing the map**, by moving a pin, or by **searching an address** (OpenStreetMap's Nominatim).

**Offline maps**
- A **low-detail world map is built into the app**, so the map works even on the very first launch without a connection.
- **Download detailed areas** (Small, Medium or Large) for offline use. The app offers the area around you, but only downloads after you agree.
- With no connection, the map still shows: areas you haven't downloaded are drawn from the world map, enlarged, instead of going blank.
- Manage downloads in **Offline maps**: pause, resume, rename, delete, and see how much space they use.

**Settings**
- **Dark mode** (or follow the phone) and a **high contrast mode**.
- The size of the map cache, and a button to clear it.
- What is sent to the address service, under **Privacy**.

The app is portrait only, and is tested on screens from small phones to small tablets and with the largest font sizes.

## Install

There is no app store release.

- **Android:** download `app-release.apk` from the [latest GitHub release](https://github.com/YEEET214/questmark/releases/latest) and open it on your phone. The phone will ask you to allow installing apps from this source.
- **iOS:** there is no ready-made `.ipa`, because iOS apps can only be built on a Mac. On a Mac with Xcode and Flutter, build it from the source with `flutter build ios --release` (see below), then install it on your iPhone through Xcode.

## Build it yourself

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.47 or newer) and, for Android, the Android SDK. iOS builds need a Mac with Xcode.

```bash
git clone https://github.com/YEEET214/questmark.git
cd questmark
flutter pub get

flutter run                 # on a connected phone or emulator (debug)
flutter run --release       # judge speed on this: debug builds draw much slower
flutter build apk --release # Android: the APK ends up in build/app/outputs/flutter-apk/
flutter build ios --release # iOS: on a Mac with Xcode only
```

Development checks:

```bash
flutter analyze   # lint
flutter test      # all unit and widget tests (no phone or network needed)
```

## Map data and privacy

The map is drawn from **OpenStreetMap** data, served as vector tiles by [OpenFreeMap](https://openfreemap.org). The app never uses OpenStreetMap's own tile server, whose policy forbids offline use. It follows OpenFreeMap's rules for offline downloads: at most 3,000 tiles or 50 MB per download, 2 requests at a time, and its own User-Agent.

Address search uses OpenStreetMap's [Nominatim](https://nominatim.org): at most one request per second, only when you press Search, and every answer is cached so the same question is never sent twice. Search text and quest locations are sent to find addresses. Your own location is only sent, rounded to about 1 km, to name a map area you download.

Map © [OpenMapTiles](https://openmaptiles.org), data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright).

## How it's built

- **Flutter / Dart**, with `provider` for state.
- **SQLite** (`sqflite`) for quests, settings and the address cache, with versioned migrations.
- **`flutter_map`** and **`flutter_map_vector_tiles`** for the map, and **`geolocator`** for GPS.
- Offline maps: the bundled world map and downloaded areas are SQLite (MBTiles-style) files.

```
lib/
  models/     plain data classes (Task, GeoPoint, regions, tile maths)
  data/       SQLite: database, migrations, repositories, tile stores
  services/   GPS, address search, tile downloads
  state/      ChangeNotifiers the screens listen to
  ui/         tasks, map, offline maps, settings
tool/         one-off scripts (world map builder, app icon)
test/         mirrors lib/
docs/PLAN.md  requirements, phases and every design decision
```

The full plan, including why each decision was made, is in [docs/PLAN.md](docs/PLAN.md).
This project was made with Claude Code on the Opus 5.5 model.

## License

[MIT](LICENSE).
