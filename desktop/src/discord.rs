//! Mirrors the live status into Discord Rich Presence.

use std::time::{Duration, Instant};

use discord_rich_presence::activity::{Activity, Timestamps};
use discord_rich_presence::{DiscordIpc, DiscordIpcClient};

use crate::api::{RemoteStatus, Status};

const CLIENT_ID: &str = "1458777387859836958";
const RETRY_EVERY: Duration = Duration::from_secs(30);

#[derive(Clone, PartialEq)]
struct Presence {
    details: String,
    state: String,
    started_at: Option<i64>,
}

pub struct Rpc {
    client: Option<DiscordIpcClient>,
    last_attempt: Option<Instant>,
    shown: Option<Presence>,
}

impl Rpc {
    pub fn new() -> Self {
        Self { client: None, last_attempt: None, shown: None }
    }

    pub fn connected(&self) -> bool {
        self.client.is_some()
    }

    /// Shows `status`. Cheap to call often: only talks to Discord when something changed.
    pub fn show(&mut self, status: &RemoteStatus) {
        let presence = presence_for(status);
        if self.shown.as_ref() == Some(&presence) && self.client.is_some() {
            return;
        }
        if !self.ensure_connected() {
            return;
        }

        let mut activity = Activity::new().details(&presence.details).state(&presence.state);
        if let Some(start) = presence.started_at {
            activity = activity.timestamps(Timestamps::new().start(start));
        }
        let ok = self.client.as_mut().is_some_and(|c| c.set_activity(activity).is_ok());
        if ok {
            self.shown = Some(presence);
        } else {
            self.disconnect();
        }
    }

    pub fn disconnect(&mut self) {
        if let Some(mut client) = self.client.take() {
            let _ = client.clear_activity();
            let _ = client.close();
        }
        self.shown = None;
    }

    fn ensure_connected(&mut self) -> bool {
        if self.client.is_some() {
            return true;
        }
        // Discord isn't running most of the time we fail; don't hammer the pipe.
        if self.last_attempt.is_some_and(|t| t.elapsed() < RETRY_EVERY) {
            return false;
        }
        self.last_attempt = Some(Instant::now());
        let mut client = DiscordIpcClient::new(CLIENT_ID);
        if client.connect().is_ok() {
            self.client = Some(client);
            true
        } else {
            false
        }
    }
}

fn presence_for(status: &RemoteStatus) -> Presence {
    let details = match status.status {
        Status::Sleeping => "Sleeping 💤".to_owned(),
        Status::Streaming => "🔴 Streaming".to_owned(),
        other => other.label().to_owned(),
    };
    let message = status.custom_message.clone().filter(|m| !m.is_empty());
    let state = match (status.activity_text(), message) {
        (Some(activity), Some(message)) => format!("{activity} · {message}"),
        (Some(text), None) | (None, Some(text)) => text,
        (None, None) => "yabosen.live".to_owned(),
    };
    // Discord rejects fields longer than 128 characters.
    let state = state.chars().take(128).collect();
    Presence { details, state, started_at: status.started_at }
}
