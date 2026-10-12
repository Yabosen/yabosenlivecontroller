# Yabosen Live Controller

Controls the live status shown on [yabosen.live](https://yabosen.live): pick Online / DND / Idle / Sleeping / Streaming / Offline, set a custom message and what you're playing or watching, and keep the site's heartbeat alive.

| Folder | What | Platforms | Language |
|---|---|---|---|
| [`desktop/`](desktop) | PC controller | Windows, Linux | Rust ([egui](https://github.com/emilk/egui)) |
| [`mobile/`](mobile) | Phone controller | Android | Dart ([Flutter](https://flutter.dev)) |

Both talk to the website's API with your `STATUS_API_KEY` (the "password" from the old app).

## Install

**Windows** (PowerShell, no admin needed):

```powershell
irm https://github.com/Yabosen/yabosenlivecontroller/releases/latest/download/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\Yabosen Controller`, adds a Start Menu shortcut, and shows up in **Settings → Apps** for uninstalling. Run it again to update.

**Linux** (x86_64):

```bash
curl -fsSL https://github.com/Yabosen/yabosenlivecontroller/releases/latest/download/install.sh | sh
```

It picks the package for your system: `.deb` on Debian/Ubuntu/Mint/Pop!_OS, `.rpm` on Fedora/RHEL/openSUSE, `.pkg.tar.zst` on Arch/Manjaro/EndeavourOS, and the AppImage on anything else. Options go after `sh -s --`:

```bash
curl -fsSL https://github.com/Yabosen/yabosenlivecontroller/releases/latest/download/install.sh | sh -s -- --appimage   # user-only AppImage, no root
curl -fsSL https://github.com/Yabosen/yabosenlivecontroller/releases/latest/download/install.sh | sh -s -- --uninstall
```

**Android:** download `yabosen-controller-android.apk` from the [latest release](https://github.com/Yabosen/yabosenlivecontroller/releases/latest) and open it on your phone.

Every file is also listed on the [releases page](https://github.com/Yabosen/yabosenlivecontroller/releases) if you'd rather install by hand. After installing, open **Settings** in the app and paste your API key.

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

## CI and releases

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds and tests on every push to `main`:

- the desktop app on Windows and Linux
- the Android APK

The finished files can be downloaded from each run's **Artifacts** section on GitHub.

To publish a release, bump `version` in `desktop/Cargo.toml` (and `mobile/pubspec.yaml`), commit, then push a matching tag:

```bash
git tag v1.0.1
git push origin v1.0.1
```

[`.github/workflows/release.yml`](.github/workflows/release.yml) then builds every package, publishes the GitHub Release with checksums and the install scripts, and finally runs the one-line installers on Debian, Ubuntu, Fedora, Arch, an AppImage and Windows to make sure they work.
