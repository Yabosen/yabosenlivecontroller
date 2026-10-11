# Yabosen Controller (Android)

A Flutter app for controlling the live status shown on
[yabosen.live](https://yabosen.live) from your phone. It replaces the old
.NET MAUI app. All app logic is in Dart.

## What it does

- **Status tab**
  - Live status card: coloured dot, activity-aware label ("Playing CS2",
    "Watching Frieren (S1 Ep 3)", "Streaming CS2"…), custom message, last
    update time and your avatar.
  - Pull to refresh. While the app is open it also refreshes every 15 s.
  - If the site shows *Idle* only because your PC heartbeat is stale, the card
    tells you which status is actually stored.
  - Set status: Online / Offline / DND / Idle / Sleeping / Streaming, an
    optional custom message, and an activity (None / Playing a game / Watching
    a show with season and episode). Tapping a status sends everything,
    vibrates on success and refreshes the card. Errors show up in a snackbar.
- **Schedule tab**: turn the server-side sleep schedule on or off and set
  sleepy/wakey times with a 24 h picker. The times are **Romania time
  (Europe/Bucharest)**. The schedule runs on the server, so it works even when
  your phone is off.
- **Settings tab**
  - API key (your `STATUS_API_KEY`): it is checked against the server before
    being saved, stored only on the phone, shown masked, and can be cleared.
  - Background heartbeat: an Android foreground service that sends
    `POST /api/heartbeat {"source":"mobile"}` every 60 s, even when the app is
    closed. It starts again after a reboot or an app update. This tab shows
    whether the service is running, the last heartbeat result, and the
    notification and battery permission state.
  - Avatar upload: pick an image from the gallery. It is resized to 512 px and
    must be 500 KB or smaller, and the thumbnail refreshes after the upload.

## Build

You need the Flutter SDK (3.44+; this was built with 3.47) and the Android
SDK.

```sh
flutter pub get
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. Copy it
to your phone and install it (allow "Install unknown apps" for your file
manager or browser). For development, use `flutter run` with a device
connected.

The release build is signed with the debug key so it can be sideloaded right
away. To use your own key, add a signing config in
`android/app/build.gradle.kts`.

Run the tests with `flutter test`.

## First run

1. Open the app. It goes straight to **Settings**. Enter your API key
   (`STATUS_API_KEY`) and tap **Save**.
2. Allow notifications when Android asks (Android 13+). The heartbeat service
   needs its persistent notification
   ("Heartbeat active · last ok 14:03").
3. When the "Keep the heartbeat alive" dialog appears, tap **Continue** and
   allow the app to ignore battery optimisations. Without this Android may
   kill the heartbeat.
4. On Xiaomi, Samsung, Huawei, OnePlus and similar phones, also enable
   *Autostart* or *Unrestricted* battery for the app in system settings
   (see [dontkillmyapp.com](https://dontkillmyapp.com)).

The heartbeat switches on by default once a key is saved. You can turn it off
in Settings. Turning it off also stops it from starting after a reboot.

## How the background heartbeat works

- It uses [`flutter_foreground_task`](https://pub.dev/packages/flutter_foreground_task)
  (`lib/src/heartbeat.dart`). The task handler runs in its own isolate. It
  reads the API key from `shared_preferences` on every beat, posts the
  heartbeat, saves the result, sends it to the UI and updates the
  notification text.
- The service type is **`specialUse`**. On Android 15, `dataSync` services
  are limited to 6 h per day and cannot be started at boot, and this service
  must run 24/7. The manifest declares the
  `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` property.
- `autoRunOnBoot`, `autoRunOnMyPackageReplaced`, `allowAutoRestart` and a
  partial wake lock are all enabled.
- If the server answers `404 No status data found` (no status has ever been
  set), the beat still counts as OK, because the server records it anyway.

## Limitations

- **Android only.** iOS is not supported because it does not allow a 24/7
  background heartbeat.
- **Google Play:** apps that use `specialUse` foreground services need a
  written justification in the Play Console. This doesn't matter for
  sideloading.
- The app talks to `https://yabosen.live`. To change that, edit
  `YabosenApi.defaultBaseUri` in `lib/src/api.dart`.

## Code layout

```
lib/
  main.dart                     entry point: comms port + service init
  src/
    api.dart                    HTTP client, ApiException, avatar helpers
    models.dart                 StatusKind, LiveStatus, StatusUpdate, SleepSchedule, HeartbeatResult
    settings.dart               shared_preferences storage + ApiKeyController
    heartbeat.dart              TaskHandler (task isolate) + service config/controller (UI)
    status_controller.dart      status fetching + 15 s foreground polling
    format.dart                 time formatting, Europe/Bucharest wall clock
    ui/
      app.dart, home_screen.dart, theme.dart, widgets.dart, permissions.dart
      status/                   live status card, set-status panel, tab
      schedule/                 sleep schedule tab
      settings/                 API key, heartbeat, avatar panels
test/                           unit tests for models, formatting and the API client
```
