//! Detects what's running: OBS (streaming) and the current Steam game.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use regex::Regex;
use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Detected {
    pub obs: bool,
    pub game: Option<String>,
    /// "Artist - Track" from Last.fm.
    pub track: Option<String>,
}

pub struct Detector {
    sys: System,
    game_names: HashMap<u32, String>,
}

impl Detector {
    pub fn new() -> Self {
        Self { sys: System::new(), game_names: HashMap::new() }
    }

    /// Fills `obs` and `game`; `track` is left to the caller.
    pub fn scan(&mut self, into: &mut Detected) {
        self.sys
            .refresh_processes_specifics(ProcessesToUpdate::All, true, ProcessRefreshKind::nothing());
        into.obs = self.sys.processes().values().any(|p| is_obs(&p.name().to_string_lossy()));
        into.game = steam::running_app_id().map(|id| self.game_name(id));
    }

    fn game_name(&mut self, app_id: u32) -> String {
        if let Some(name) = self.game_names.get(&app_id) {
            return name.clone();
        }
        let name = steam::game_name(app_id).unwrap_or_else(|| format!("Steam game {app_id}"));
        self.game_names.insert(app_id, name.clone());
        name
    }
}

fn is_obs(process: &str) -> bool {
    let p = process.to_ascii_lowercase();
    matches!(p.as_str(), "obs" | "obs64.exe" | "obs32.exe" | "obs.exe" | "obs-studio")
}

fn capture_all(re: &str, text: &str) -> Vec<String> {
    Regex::new(re)
        .expect("valid regex")
        .captures_iter(text)
        .map(|c| c[1].to_owned())
        .collect()
}

/// Steam library folders (including the install itself) under a Steam root.
fn library_folders(root: &Path) -> Vec<PathBuf> {
    let mut folders = vec![root.to_path_buf()];
    if let Ok(vdf) = std::fs::read_to_string(root.join("steamapps").join("libraryfolders.vdf")) {
        folders.extend(
            capture_all(r#""path"\s+"([^"]+)""#, &vdf)
                .into_iter()
                .map(|p| PathBuf::from(p.replace("\\\\", "\\"))),
        );
    }
    folders
}

fn name_from_manifests(roots: &[PathBuf], app_id: u32) -> Option<String> {
    roots.iter().flat_map(|root| library_folders(root)).find_map(|folder| {
        let manifest = folder.join("steamapps").join(format!("appmanifest_{app_id}.acf"));
        let text = std::fs::read_to_string(manifest).ok()?;
        capture_all(r#""name"\s+"([^"]+)""#, &text).into_iter().next()
    })
}

#[cfg(windows)]
mod steam {
    use std::path::PathBuf;

    use winreg::RegKey;
    use winreg::enums::HKEY_CURRENT_USER;

    fn key() -> Option<RegKey> {
        RegKey::predef(HKEY_CURRENT_USER).open_subkey(r"Software\Valve\Steam").ok()
    }

    pub fn running_app_id() -> Option<u32> {
        key()?.get_value::<u32, _>("RunningAppID").ok().filter(|&id| id > 0)
    }

    pub fn game_name(app_id: u32) -> Option<String> {
        let root: String = key()?.get_value("SteamPath").ok()?;
        super::name_from_manifests(&[PathBuf::from(root.replace('/', "\\"))], app_id)
    }
}

#[cfg(not(windows))]
mod steam {
    use std::path::PathBuf;

    fn home() -> Option<PathBuf> {
        std::env::var_os("HOME").map(PathBuf::from)
    }

    /// Native and Flatpak Steam installs.
    fn roots() -> Vec<PathBuf> {
        let Some(home) = home() else { return Vec::new() };
        [
            ".steam/steam",
            ".local/share/Steam",
            ".var/app/com.valvesoftware.Steam/.local/share/Steam",
        ]
        .iter()
        .map(|p| home.join(p))
        .filter(|p| p.is_dir())
        .collect()
    }

    pub fn running_app_id() -> Option<u32> {
        let home = home()?;
        [".steam/registry.vdf", ".var/app/com.valvesoftware.Steam/.steam/registry.vdf"]
            .iter()
            .filter_map(|p| std::fs::read_to_string(home.join(p)).ok())
            .flat_map(|text| super::capture_all(r#""RunningAppID"\s+"(\d+)""#, &text))
            .filter_map(|id| id.parse().ok())
            .find(|&id| id > 0)
    }

    pub fn game_name(app_id: u32) -> Option<String> {
        super::name_from_manifests(&roots(), app_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognises_obs_on_both_platforms() {
        assert!(is_obs("obs64.exe"));
        assert!(is_obs("OBS64.EXE"));
        assert!(is_obs("obs"));
        assert!(!is_obs("obsidian"));
    }

    #[test]
    fn parses_vdf_values() {
        let vdf = r#""0" { "path"   "D:\\SteamLibrary" } "1" { "path" "E:\\Games" }"#;
        assert_eq!(capture_all(r#""path"\s+"([^"]+)""#, vdf), ["D:\\\\SteamLibrary", "E:\\\\Games"]);
    }
}
