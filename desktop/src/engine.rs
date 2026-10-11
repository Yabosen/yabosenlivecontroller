//! Background worker that owns every network call: heartbeats, polling, auto-detect and
//! Discord. It runs on its own thread so the window can be hidden or busy without the
//! website flipping to idle.

use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use base64::Engine as _;
use chrono::{DateTime, Local};

use crate::api::{ActivityKind, Api, ApiError, RemoteStatus, SleepSchedule, Status, StatusUpdate};
use crate::config::Config;
use crate::detect::{Detected, Detector};
use crate::discord::Rpc;

const HEARTBEAT_EVERY: Duration = Duration::from_secs(60);
const REFRESH_EVERY: Duration = Duration::from_secs(15);
const SCAN_EVERY: Duration = Duration::from_secs(5);
const LASTFM_EVERY: Duration = Duration::from_secs(20);
const MAX_AVATAR_BYTES: usize = 500 * 1024;

pub enum Command {
    SetStatus(StatusUpdate),
    Refresh,
    UpdateConfig(Config),
    UploadAvatar(PathBuf),
    SaveSchedule(SleepSchedule),
}

#[derive(Clone)]
pub struct Notice {
    pub text: String,
    pub error: bool,
    pub at: Instant,
}

/// What the UI renders. The worker updates it; the UI only reads it.
#[derive(Clone, Default)]
pub struct Snapshot {
    pub remote: Option<RemoteStatus>,
    pub remote_error: Option<String>,
    pub heartbeat: Option<(DateTime<Local>, Result<(), String>)>,
    pub detected: Detected,
    pub schedule: Option<SleepSchedule>,
    pub busy: bool,
    pub notice: Option<Notice>,
    pub discord_connected: bool,
}

pub struct Engine {
    tx: Sender<Command>,
    shared: Arc<Mutex<Snapshot>>,
}

impl Engine {
    /// `repaint` is called whenever the snapshot changes.
    pub fn spawn(config: Config, repaint: impl Fn() + Send + 'static) -> Self {
        let (tx, rx) = mpsc::channel();
        let shared = Arc::new(Mutex::new(Snapshot::default()));
        let worker = Worker {
            api: Api::new(&config.api_key),
            config,
            shared: shared.clone(),
            repaint: Box::new(repaint),
            detector: Detector::new(),
            detected: Detected::default(),
            rpc: Rpc::new(),
            remote: None,
            auto_owned: false,
        };
        thread::Builder::new()
            .name("engine".into())
            .spawn(move || worker.run(rx))
            .expect("failed to start engine thread");
        Self { tx, shared }
    }

    pub fn send(&self, command: Command) {
        let _ = self.tx.send(command);
    }

    pub fn snapshot(&self) -> Snapshot {
        self.shared.lock().unwrap().clone()
    }
}

struct Worker {
    api: Api,
    config: Config,
    shared: Arc<Mutex<Snapshot>>,
    repaint: Box<dyn Fn() + Send>,
    detector: Detector,
    detected: Detected,
    rpc: Rpc,
    remote: Option<RemoteStatus>,
    /// The current status/activity was set by auto-detect (so we may clear it again).
    auto_owned: bool,
}

impl Worker {
    fn run(mut self, rx: Receiver<Command>) {
        self.startup();

        let now = Instant::now();
        let mut next_heartbeat = now + HEARTBEAT_EVERY;
        let mut next_refresh = now + REFRESH_EVERY;
        let mut next_scan = now;
        let mut next_lastfm = now;

        loop {
            let wake = next_heartbeat.min(next_refresh).min(next_scan).min(next_lastfm);
            match rx.recv_timeout(wake.saturating_duration_since(Instant::now())) {
                Ok(command) => self.handle(command),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
            }

            let now = Instant::now();
            if now >= next_heartbeat {
                self.heartbeat();
                next_heartbeat = now + HEARTBEAT_EVERY;
            }
            if now >= next_refresh {
                self.refresh();
                next_refresh = now + REFRESH_EVERY;
            }

            let mut detected = self.detected.clone();
            if now >= next_scan {
                if self.config.auto_detect {
                    self.detector.scan(&mut detected);
                } else {
                    detected.obs = false;
                    detected.game = None;
                }
                next_scan = now + SCAN_EVERY;
            }
            if now >= next_lastfm {
                if self.config.auto_detect && self.config.lastfm_listening {
                    // Keep the last known track on network hiccups instead of "ending" it.
                    if let Ok(track) = self.api.now_playing() {
                        detected.track = track;
                    }
                } else {
                    detected.track = None;
                }
                next_lastfm = now + LASTFM_EVERY;
            }
            if detected != self.detected {
                self.detected = detected;
                self.on_detected_change();
                self.publish();
            }
        }

        // Window closed: stop quietly. We deliberately don't post "offline" — the site
        // shows idle once heartbeats stop, and a manual Offline would stick.
        self.rpc.disconnect();
    }

    /// Beat first so the site sees the PC as alive, then come back online if we were away.
    fn startup(&mut self) {
        self.load_schedule();
        if !self.api.has_key() {
            self.refresh();
            return;
        }
        self.heartbeat();
        self.refresh();
        let away = self
            .remote
            .as_ref()
            .is_some_and(|r| matches!(r.status, Status::Offline | Status::Idle | Status::Sleeping));
        if away {
            let message = self.remote.as_ref().and_then(|r| r.custom_message.clone());
            self.post(StatusUpdate::new(Status::Online, message), "Back online");
        }
    }

    fn handle(&mut self, command: Command) {
        match command {
            Command::SetStatus(update) => {
                let label = update.status.label();
                if self.post(update, &format!("Status set to {label}")) {
                    self.auto_owned = false;
                }
            }
            Command::Refresh => {
                self.refresh();
                self.load_schedule();
            }
            Command::UpdateConfig(config) => {
                let key_changed = config.api_key != self.config.api_key;
                self.config = config;
                self.api.set_key(&self.config.api_key);
                if key_changed && self.api.has_key() {
                    self.heartbeat();
                }
                self.sync_discord();
                self.publish();
            }
            Command::UploadAvatar(path) => self.upload_avatar(&path),
            Command::SaveSchedule(schedule) => {
                self.set_busy(true);
                match self.api.set_sleep_schedule(&schedule) {
                    Ok(()) => {
                        self.update(|s| s.schedule = Some(schedule));
                        self.notice("Sleep schedule saved", false);
                    }
                    Err(err) => self.notice(err.to_string(), true),
                }
                self.set_busy(false);
            }
        }
    }

    /// Posts a status update. Returns whether it was stored.
    fn post(&mut self, update: StatusUpdate, success: &str) -> bool {
        self.set_busy(true);
        let ok = match self.api.set_status(&update) {
            Ok(stored) => {
                self.remote = Some(stored);
                self.update(|s| s.remote_error = None);
                self.notice(success, false);
                true
            }
            Err(err) => {
                self.notice(format!("Couldn't update status: {err}"), true);
                false
            }
        };
        self.sync_discord();
        self.set_busy(false);
        self.publish();
        ok
    }

    fn heartbeat(&mut self) {
        if !self.api.has_key() {
            return;
        }
        let result = self.api.heartbeat();
        if let Err(ApiError::Unauthorized) = result {
            self.notice("Heartbeat rejected: check your API key", true);
        }
        let entry = (Local::now(), result.map_err(|e| e.to_string()));
        self.update(|s| s.heartbeat = Some(entry));
    }

    fn refresh(&mut self) {
        match self.api.status() {
            Ok(remote) => {
                self.remote = Some(remote);
                self.update(|s| s.remote_error = None);
            }
            Err(err) => {
                let text = err.to_string();
                self.update(|s| s.remote_error = Some(text));
            }
        }
        self.sync_discord();
        self.publish();
    }

    fn load_schedule(&mut self) {
        if let Ok(schedule) = self.api.sleep_schedule() {
            self.update(|s| s.schedule = Some(schedule));
        }
    }

    /// Reacts to OBS / Steam / Last.fm changes, the same way the old app did:
    /// OBS → Streaming, a Steam game → Playing, a scrobble → Listening, nothing → clear.
    fn on_detected_change(&mut self) {
        if !self.config.auto_detect || !self.api.has_key() {
            return;
        }
        let detected = self.detected.clone();
        let current = self.remote.as_ref().map_or(Status::Online, |r| r.status);
        let message = self.remote.as_ref().and_then(|r| r.custom_message.clone());

        let update = if detected.obs {
            let update = StatusUpdate::new(Status::Streaming, message);
            match detected.game {
                Some(game) => update.with_activity(ActivityKind::Playing, game),
                None => update,
            }
        } else if matches!(current, Status::Offline | Status::Sleeping) {
            // You said you're away: don't announce games or music.
            return;
        } else {
            // Keep Do Not Disturb; otherwise Online (which also ends an auto-started stream).
            let status = if current == Status::Dnd { Status::Dnd } else { Status::Online };
            let update = StatusUpdate::new(status, message);
            if let Some(game) = detected.game {
                update.with_activity(ActivityKind::Playing, game)
            } else if let Some(track) = detected.track.filter(|_| self.config.lastfm_listening) {
                update.with_activity(ActivityKind::Listening, track)
            } else if self.auto_owned {
                update
            } else {
                // Nothing we started has ended; leave manual activities alone.
                return;
            }
        };

        if self.remote.as_ref().is_some_and(|r| same_as(r, &update)) {
            self.auto_owned = true;
            return;
        }
        let what = match (&update.activity_type, &update.activity_name) {
            (Some(ActivityKind::Playing), Some(game)) if update.status == Status::Streaming => {
                format!("Streaming {game}")
            }
            (Some(ActivityKind::Playing), Some(game)) => format!("Playing {game}"),
            (Some(ActivityKind::Listening), Some(track)) => format!("Listening to {track}"),
            _ => update.status.label().to_owned(),
        };
        if self.post(update, &format!("Auto: {what}")) {
            self.auto_owned = true;
        }
    }

    fn upload_avatar(&mut self, path: &Path) {
        let mime = match path
            .extension()
            .and_then(|e| e.to_str())
            .map(str::to_ascii_lowercase)
            .as_deref()
        {
            Some("png") => "image/png",
            Some("jpg" | "jpeg") => "image/jpeg",
            Some("gif") => "image/gif",
            Some("webp") => "image/webp",
            _ => return self.notice("Pick a PNG, JPG, GIF or WebP image", true),
        };
        let bytes = match std::fs::read(path) {
            Ok(bytes) => bytes,
            Err(err) => return self.notice(format!("Couldn't read image: {err}"), true),
        };
        if bytes.len() > MAX_AVATAR_BYTES {
            return self.notice(
                format!("Image is {} KB; the website allows up to 500 KB", bytes.len() / 1024),
                true,
            );
        }

        self.set_busy(true);
        let data_url = format!(
            "data:{mime};base64,{}",
            base64::engine::general_purpose::STANDARD.encode(&bytes)
        );
        match self.api.upload_avatar(data_url) {
            Ok(()) => self.notice("Avatar uploaded", false),
            Err(err) => self.notice(format!("Avatar upload failed: {err}"), true),
        }
        self.set_busy(false);
    }

    fn sync_discord(&mut self) {
        match (&self.remote, self.config.discord_rpc) {
            (Some(remote), true) => self.rpc.show(remote),
            (_, false) => self.rpc.disconnect(),
            (None, true) => {}
        }
    }

    fn publish(&mut self) {
        let remote = self.remote.clone();
        let detected = self.detected.clone();
        let discord = self.rpc.connected();
        self.update(|s| {
            s.remote = remote;
            s.detected = detected;
            s.discord_connected = discord;
        });
    }

    fn set_busy(&self, busy: bool) {
        self.update(|s| s.busy = busy);
    }

    fn notice(&self, text: impl Into<String>, error: bool) {
        let notice = Notice { text: text.into(), error, at: Instant::now() };
        self.update(|s| s.notice = Some(notice));
    }

    fn update(&self, change: impl FnOnce(&mut Snapshot)) {
        change(&mut self.shared.lock().unwrap());
        (self.repaint)();
    }
}

/// Whether posting `update` would change nothing visible.
fn same_as(remote: &RemoteStatus, update: &StatusUpdate) -> bool {
    remote.status == update.status
        && remote.activity_type == update.activity_type
        && remote.activity_name == update.activity_name
}
