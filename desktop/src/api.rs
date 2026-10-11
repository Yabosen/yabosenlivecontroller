//! Client for the yabosen.live status API.

use std::fmt;
use std::time::Duration;

use serde::{Deserialize, Serialize};

pub const BASE_URL: &str = "https://yabosen.live";

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Online,
    #[default]
    Offline,
    Dnd,
    Idle,
    Sleeping,
    Streaming,
}

impl Status {
    pub const ALL: [Status; 6] = [
        Status::Online,
        Status::Dnd,
        Status::Idle,
        Status::Sleeping,
        Status::Streaming,
        Status::Offline,
    ];

    pub fn label(self) -> &'static str {
        match self {
            Status::Online => "Online",
            Status::Offline => "Offline",
            Status::Dnd => "Do Not Disturb",
            Status::Idle => "Idle",
            Status::Sleeping => "Sleeping",
            Status::Streaming => "Streaming",
        }
    }

    /// RGB colour used for the status dot.
    pub fn rgb(self) -> [u8; 3] {
        match self {
            Status::Online => [0x22, 0xc5, 0x5e],
            Status::Offline => [0x6b, 0x72, 0x80],
            Status::Dnd => [0xef, 0x44, 0x44],
            Status::Idle => [0xea, 0xb3, 0x08],
            Status::Sleeping => [0xa8, 0x55, 0xf7],
            Status::Streaming => [0xe0, 0x00, 0x7a],
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ActivityKind {
    Playing,
    Watching,
    Listening,
}

/// The status document as returned by `GET /api/status`.
#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteStatus {
    #[serde(default)]
    pub status: Status,
    pub custom_message: Option<String>,
    pub activity_type: Option<ActivityKind>,
    pub activity_name: Option<String>,
    pub episode_info: Option<String>,
    pub season_info: Option<String>,
    #[serde(default)]
    pub updated_at: i64,
    pub started_at: Option<i64>,
}

impl RemoteStatus {
    /// "Playing X", "Watching X (S1 · Ep 3)", "Listening to X", or `None`.
    pub fn activity_text(&self) -> Option<String> {
        let name = self.activity_name.as_deref().filter(|n| !n.is_empty())?;
        Some(match self.activity_type? {
            ActivityKind::Playing if self.status == Status::Streaming => format!("Streaming {name}"),
            ActivityKind::Playing => format!("Playing {name}"),
            ActivityKind::Listening => format!("Listening to {name}"),
            ActivityKind::Watching => {
                let extras: Vec<String> = [
                    self.season_info.clone(),
                    self.episode_info.as_ref().map(|e| format!("Ep {e}")),
                ]
                .into_iter()
                .flatten()
                .filter(|s| !s.is_empty())
                .collect();
                if extras.is_empty() {
                    format!("Watching {name}")
                } else {
                    format!("Watching {name} ({})", extras.join(" · "))
                }
            }
        })
    }
}

/// Body for `POST /api/status`.
#[derive(Clone, Debug, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StatusUpdate {
    pub status: Status,
    pub custom_message: Option<String>,
    pub activity_type: Option<ActivityKind>,
    pub activity_name: Option<String>,
    pub episode_info: Option<String>,
    pub season_info: Option<String>,
}

impl StatusUpdate {
    pub fn new(status: Status, custom_message: Option<String>) -> Self {
        Self { status, custom_message, ..Default::default() }
    }

    pub fn with_activity(mut self, kind: ActivityKind, name: impl Into<String>) -> Self {
        self.activity_type = Some(kind);
        self.activity_name = Some(name.into());
        self
    }
}

/// Body/response of `/api/sleep-schedule`. Times are "HH:mm", Europe/Bucharest.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SleepSchedule {
    pub enabled: bool,
    pub sleepy_time: String,
    pub wakey_time: String,
}

#[derive(Debug, Clone)]
pub enum ApiError {
    NoKey,
    Unauthorized,
    Server(String),
    Network(String),
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ApiError::NoKey => write!(f, "Add your API key in Settings first"),
            ApiError::Unauthorized => write!(f, "API key was rejected"),
            ApiError::Server(msg) => write!(f, "{msg}"),
            ApiError::Network(msg) => write!(f, "Network error: {msg}"),
        }
    }
}

impl From<reqwest::Error> for ApiError {
    fn from(err: reqwest::Error) -> Self {
        ApiError::Network(err.without_url().to_string())
    }
}

pub type ApiResult<T> = Result<T, ApiError>;

pub struct Api {
    http: reqwest::blocking::Client,
    key: String,
}

impl Api {
    pub fn new(key: &str) -> Self {
        let http = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent(concat!("yabosen-controller/", env!("CARGO_PKG_VERSION")))
            .build()
            .expect("HTTP client");
        Self { http, key: key.trim().to_owned() }
    }

    pub fn set_key(&mut self, key: &str) {
        self.key = key.trim().to_owned();
    }

    pub fn has_key(&self) -> bool {
        !self.key.is_empty()
    }

    fn url(path: &str) -> String {
        format!("{BASE_URL}{path}")
    }

    fn post<B: Serialize>(&self, path: &str, body: &B) -> ApiResult<reqwest::blocking::Response> {
        if self.key.is_empty() {
            return Err(ApiError::NoKey);
        }
        let res = self.http.post(Self::url(path)).bearer_auth(&self.key).json(body).send()?;
        check(res)
    }

    pub fn status(&self) -> ApiResult<RemoteStatus> {
        let res = self.http.get(Self::url("/api/status")).send()?;
        Ok(check(res)?.json()?)
    }

    /// Writes the status and returns the stored document.
    pub fn set_status(&self, update: &StatusUpdate) -> ApiResult<RemoteStatus> {
        Ok(self.post("/api/status", update)?.json()?)
    }

    pub fn heartbeat(&self) -> ApiResult<()> {
        match self.post("/api/heartbeat", &serde_json::json!({ "source": "pc" })) {
            // No status stored yet: the beat was still recorded, nothing to worry about.
            Err(ApiError::Server(msg)) if msg.contains("No status data") => Ok(()),
            other => other.map(drop),
        }
    }

    pub fn sleep_schedule(&self) -> ApiResult<SleepSchedule> {
        let res = self.http.get(Self::url("/api/sleep-schedule")).send()?;
        Ok(check(res)?.json()?)
    }

    pub fn set_sleep_schedule(&self, schedule: &SleepSchedule) -> ApiResult<()> {
        self.post("/api/sleep-schedule", schedule).map(drop)
    }

    pub fn upload_avatar(&self, data_url: String) -> ApiResult<()> {
        self.post("/api/avatar", &serde_json::json!({ "avatar": data_url })).map(drop)
    }

    /// "Artist - Track" if Last.fm (as configured on the website) is scrobbling right now.
    pub fn now_playing(&self) -> ApiResult<Option<String>> {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct NowPlaying {
            #[serde(default)]
            is_playing: bool,
            track: Option<Track>,
        }
        #[derive(Deserialize)]
        struct Track {
            name: String,
            artist: String,
        }

        let res = self.http.get(Self::url("/api/lastfm")).send()?;
        let body: NowPlaying = check(res)?.json()?;
        Ok(body
            .track
            .filter(|_| body.is_playing)
            .map(|t| format!("{} - {}", t.artist, t.name)))
    }
}

/// Turns non-2xx responses into an [`ApiError`] using the `{ "error": ... }` body.
fn check(res: reqwest::blocking::Response) -> ApiResult<reqwest::blocking::Response> {
    let code = res.status();
    if code.is_success() {
        return Ok(res);
    }
    if code == reqwest::StatusCode::UNAUTHORIZED {
        return Err(ApiError::Unauthorized);
    }
    let message = res
        .json::<serde_json::Value>()
        .ok()
        .and_then(|v| v.get("error").and_then(|e| e.as_str()).map(str::to_owned))
        .unwrap_or_else(|| format!("Server returned {code}"));
    Err(ApiError::Server(message))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_status_document() {
        let json = r#"{"status":"online","customMessage":"hi","activityType":"watching",
            "activityName":"Lain","episodeInfo":"3","seasonInfo":"S1","updatedAt":1,"startedAt":2}"#;
        let s: RemoteStatus = serde_json::from_str(json).unwrap();
        assert_eq!(s.status, Status::Online);
        assert_eq!(s.activity_text().unwrap(), "Watching Lain (S1 · Ep 3)");
    }

    #[test]
    fn serializes_update_with_nulls() {
        let body = serde_json::to_value(StatusUpdate::new(Status::Dnd, None)).unwrap();
        assert_eq!(body["status"], "dnd");
        assert!(body["activityType"].is_null());
    }
}
