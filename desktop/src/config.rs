//! Settings persisted as JSON in the per-user config directory.

use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// The website's STATUS_API_KEY.
    pub api_key: String,
    /// Switch status automatically from OBS / Steam / Last.fm.
    pub auto_detect: bool,
    /// Show Last.fm scrobbles as a "Listening to" activity.
    pub lastfm_listening: bool,
    pub discord_rpc: bool,
    /// Closing the window keeps the app (and heartbeats) running.
    pub keep_running_when_closed: bool,
    pub start_minimized: bool,
    pub autostart: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            api_key: String::new(),
            auto_detect: true,
            lastfm_listening: true,
            discord_rpc: true,
            keep_running_when_closed: true,
            start_minimized: false,
            autostart: false,
        }
    }
}

fn path() -> Option<PathBuf> {
    directories::ProjectDirs::from("live", "yabosen", "Yabosen Controller")
        .map(|dirs| dirs.config_dir().join("config.json"))
}

impl Config {
    pub fn load() -> Self {
        path()
            .and_then(|p| fs::read_to_string(p).ok())
            // Editors like Notepad may add a byte-order mark, which JSON parsers reject.
            .and_then(|text| serde_json::from_str(text.trim_start_matches('\u{feff}')).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) -> std::io::Result<()> {
        let Some(path) = path() else {
            return Err(std::io::Error::other("no config directory"));
        };
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        fs::write(&path, serde_json::to_string_pretty(self)?)?;
        // The file holds the API key: keep it private to the user.
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
        }
        Ok(())
    }
}
