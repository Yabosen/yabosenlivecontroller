# Yabosen Live Controller

Controls the live status shown on [yabosen.live](https://yabosen.live): pick Online / DND / Idle / Sleeping / Streaming / Offline, set a custom message and what you're playing or watching, and keep the site's heartbeat alive.

| Folder | What | Platforms | Language |
|---|---|---|---|
| [`desktop/`](desktop) | PC controller | Windows, Linux | Rust ([egui](https://github.com/emilk/egui)) |
| [`mobile/`](mobile) | Phone controller | Android | Dart ([Flutter](https://flutter.dev)) |

Both talk to the website's API with your `STATUS_API_KEY` (the "password" from the old app).

## How the status works

- The PC app sends a **heartbeat** every 60 s while it's open. If the site stops hearing from the PC for 3 minutes, it shows you as **Idle**. Quitting the PC app never sets Offline; you only go Offline by picking it.
- The phone app also sends heartbeats (`source: "mobile"`). The site records them but doesn't currently use them to pick a status.
- The **sleep schedule** lives on the server: inside the window (Romania time) the site switches you to **Sleeping** while your PC is off, and back to **Online** afterwards. Both apps can edit it.

## Desktop (Rust)

Features:

- Status buttons, custom message, Playing / Watching activity
- Heartbeat every 60 s on a background thread (keeps going while the window is hidden)
- Auto-detect: OBS open → **Streaming**, a Steam game → **Playing**, Last.fm scrobble → **Listening to**; back to Online when it ends. Never overrides a manual Offline/Sleeping (except OBS).
- Discord Rich Presence
- Avatar upload, sleep schedule editor
- Start when you log in, start minimized, close to tray (Windows) / minimize (Linux)
- Comes back Online on launch if the site had you as Offline/Idle/Sleeping

### Build

Needs [Rust](https://rustup.rs) (stable).

- **Windows:** also needs the Visual Studio C++ Build Tools (the "Desktop development with C++" workload).
- **Linux (Debian/Ubuntu):** `sudo apt install libxkbcommon-dev libgl1-mesa-dev libwayland-dev libx11-dev`

```bash
cd desktop
cargo build --release
```

The app ends up in `desktop/target/release/` (`yabosen-controller.exe` on Windows, `yabosen-controller` on Linux). It's a single file, so you can copy it anywhere.

Settings (including the API key) are saved in:

- Windows: `%APPDATA%\yabosen\Yabosen Controller\config\config.json`
- Linux: `~/.config/yabosencontroller/config.json` (readable only by you)

Notes:

- Linux has no tray icon: closing the window minimizes it instead, so heartbeats keep running.
- Steam detection reads Steam's own files, so it works for native and Flatpak Steam on Linux.

## Mobile (Flutter)

See [`mobile/README.md`](mobile/README.md).

## CI

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds and tests on every push to `main`:

- the desktop app on Windows and Linux
- the Android APK

The finished files can be downloaded from each run's **Artifacts** section on GitHub.
