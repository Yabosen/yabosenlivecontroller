//! The main window.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use chrono::{DateTime, Local};
use eframe::egui::{self, Color32, RichText, Stroke, TextEdit};

use crate::api::{ActivityKind, SleepSchedule, Status, StatusUpdate};
use crate::config::Config;
use crate::engine::{Command, Engine, Snapshot};
use crate::{autostart, theme};

const NOTICE_FOR: Duration = Duration::from_secs(6);

#[derive(Clone, Copy, PartialEq)]
enum Tab {
    Status,
    Automation,
    Settings,
}

#[derive(Clone, Copy, PartialEq)]
enum ActivityMode {
    None,
    Playing,
    Watching,
}

struct ScheduleDraft {
    enabled: bool,
    sleepy: String,
    wakey: String,
}

pub struct App {
    engine: Engine,
    config: Config,
    tab: Tab,
    key_input: String,
    message: String,
    activity: ActivityMode,
    game: String,
    show: String,
    season: String,
    episode: String,
    schedule: Option<ScheduleDraft>,
    settings_error: Option<String>,
    quit: Arc<AtomicBool>,
    /// Frames to wait before hiding (eframe always shows the window after frame one).
    pending_hide: u8,
    has_tray: bool,
    #[cfg(windows)]
    _tray: Option<crate::tray::Tray>,
}

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>, mut config: Config, start_minimized: bool) -> Self {
        theme::apply(&cc.egui_ctx);
        config.autostart = autostart::is_enabled();

        let repaint_ctx = cc.egui_ctx.clone();
        let engine = Engine::spawn(config.clone(), move || repaint_ctx.request_repaint());
        let quit = Arc::new(AtomicBool::new(false));

        #[cfg(windows)]
        let tray = crate::tray::create(cc.egui_ctx.clone(), quit.clone());
        #[cfg(windows)]
        let has_tray = tray.is_some();
        #[cfg(not(windows))]
        let has_tray = false;

        Self {
            engine,
            tab: if config.api_key.is_empty() { Tab::Settings } else { Tab::Status },
            config,
            key_input: String::new(),
            message: String::new(),
            activity: ActivityMode::None,
            game: String::new(),
            show: String::new(),
            season: String::new(),
            episode: String::new(),
            schedule: None,
            settings_error: None,
            quit,
            pending_hide: if start_minimized { 2 } else { 0 },
            has_tray,
            #[cfg(windows)]
            _tray: tray,
        }
    }

    fn save_config(&mut self) {
        self.settings_error = self.config.save().err().map(|e| format!("Couldn't save settings: {e}"));
        self.engine.send(Command::UpdateConfig(self.config.clone()));
    }

    fn hide(&self, ctx: &egui::Context) {
        if self.has_tray {
            ctx.send_viewport_cmd(egui::ViewportCommand::Visible(false));
        } else {
            ctx.send_viewport_cmd(egui::ViewportCommand::Minimized(true));
        }
    }

    fn set_status(&mut self, status: Status) {
        let text = |s: &str| Some(s.trim().to_owned()).filter(|s| !s.is_empty());
        let mut update = StatusUpdate::new(status, text(&self.message));
        match self.activity {
            ActivityMode::None => {}
            ActivityMode::Playing => {
                if let Some(game) = text(&self.game) {
                    update = update.with_activity(ActivityKind::Playing, game);
                }
            }
            ActivityMode::Watching => {
                if let Some(show) = text(&self.show) {
                    update = update.with_activity(ActivityKind::Watching, show);
                    update.season_info = text(&self.season);
                    update.episode_info = text(&self.episode);
                }
            }
        }
        self.engine.send(Command::SetStatus(update));
    }

    /// Copies the server's sleep schedule into the editable draft the first time it arrives.
    fn sync_schedule(&mut self, snap: &Snapshot) {
        if self.schedule.is_none() {
            if let Some(s) = &snap.schedule {
                self.schedule = Some(ScheduleDraft {
                    enabled: s.enabled,
                    sleepy: s.sleepy_time.clone(),
                    wakey: s.wakey_time.clone(),
                });
            }
        }
    }

    // ---------- Layout ----------

    fn header(&mut self, ui: &mut egui::Ui, snap: &Snapshot) {
        ui.horizontal(|ui| {
            ui.label(RichText::new("Yabosen Controller").size(18.0).strong());
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let (color, tip) = heartbeat_state(snap);
                dot(ui, color, 10.0).on_hover_text(tip);
            });
        });
        ui.add_space(4.0);
        ui.horizontal(|ui| {
            for (tab, label) in [(Tab::Status, "Status"), (Tab::Automation, "Automation"), (Tab::Settings, "Settings")] {
                ui.selectable_value(&mut self.tab, tab, label);
            }
        });
    }

    fn footer(&self, ui: &mut egui::Ui, snap: &Snapshot) {
        let notice = snap.notice.as_ref().filter(|n| n.at.elapsed() < NOTICE_FOR);
        let (text, color) = match (notice, &self.settings_error) {
            (_, Some(err)) => (err.clone(), theme::ERROR),
            (Some(n), None) => (n.text.clone(), if n.error { theme::ERROR } else { theme::OK }),
            (None, None) => (heartbeat_state(snap).1, theme::MUTED),
        };
        ui.horizontal(|ui| {
            if snap.busy {
                ui.spinner();
            }
            ui.label(RichText::new(text).color(color));
        });
    }

    fn status_tab(&mut self, ui: &mut egui::Ui, snap: &Snapshot) {
        let has_key = !self.config.api_key.is_empty();
        if !has_key {
            card(ui, "Welcome", |ui| {
                ui.label("Add your website API key to start controlling your status.");
                if ui.button("Open Settings").clicked() {
                    self.tab = Tab::Settings;
                }
            });
        }

        card(ui, "Live on yabosen.live", |ui| {
            match &snap.remote {
                Some(remote) => {
                    let headline = match remote.activity_text() {
                        Some(activity) if remote.status != Status::Online => {
                            format!("{} · {activity}", remote.status.label())
                        }
                        Some(activity) => activity,
                        None => remote.status.label().to_owned(),
                    };
                    ui.horizontal(|ui| {
                        dot(ui, rgb(remote.status.rgb()), 14.0);
                        ui.label(RichText::new(headline).size(17.0).strong());
                    });
                    if let Some(message) = remote.custom_message.as_deref().filter(|m| !m.is_empty()) {
                        ui.label(RichText::new(format!("“{message}”")).color(theme::MUTED));
                    }
                    ui.horizontal(|ui| {
                        ui.label(RichText::new(format!("Updated {}", ago_ms(remote.updated_at))).small().color(theme::MUTED));
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            if ui.small_button("Refresh").clicked() {
                                self.engine.send(Command::Refresh);
                            }
                        });
                    });
                }
                None if snap.remote_error.is_none() => {
                    ui.horizontal(|ui| {
                        ui.spinner();
                        ui.label("Loading…");
                    });
                }
                None => {}
            }
            if let Some(err) = &snap.remote_error {
                ui.colored_label(theme::ERROR, err);
            }
        });

        card(ui, "Set status", |ui| {
            ui.add(
                TextEdit::singleline(&mut self.message)
                    .hint_text("Custom message (optional)")
                    .desired_width(f32::INFINITY),
            );
            ui.horizontal(|ui| {
                ui.label("Activity:");
                ui.selectable_value(&mut self.activity, ActivityMode::None, "None");
                ui.selectable_value(&mut self.activity, ActivityMode::Playing, "Playing");
                ui.selectable_value(&mut self.activity, ActivityMode::Watching, "Watching");
            });
            match self.activity {
                ActivityMode::None => {}
                ActivityMode::Playing => {
                    ui.add(TextEdit::singleline(&mut self.game).hint_text("Game").desired_width(f32::INFINITY));
                }
                ActivityMode::Watching => {
                    ui.add(TextEdit::singleline(&mut self.show).hint_text("Show / anime").desired_width(f32::INFINITY));
                    ui.horizontal(|ui| {
                        let half = (ui.available_width() - 8.0) / 2.0;
                        ui.add(TextEdit::singleline(&mut self.season).hint_text("Season (e.g. S2)").desired_width(half));
                        ui.add(TextEdit::singleline(&mut self.episode).hint_text("Episode").desired_width(half));
                    });
                }
            }
            ui.add_space(4.0);

            let enabled = has_key && !snap.busy;
            let width = (ui.available_width() - 2.0 * 6.0) / 3.0;
            let mut clicked = None;
            egui::Grid::new("status-buttons").num_columns(3).spacing([6.0, 6.0]).show(ui, |ui| {
                for (i, status) in Status::ALL.into_iter().enumerate() {
                    let label = if status == Status::Dnd { "DND" } else { status.label() };
                    // Leading spaces leave room for the painted status dot.
                    let button = egui::Button::new(format!("   {label}")).min_size(egui::vec2(width, 34.0));
                    let response = ui.add_enabled(enabled, button);
                    let mut color = rgb(status.rgb());
                    if !enabled {
                        color = color.gamma_multiply(0.4);
                    }
                    ui.painter().circle_filled(response.rect.left_center() + egui::vec2(14.0, 0.0), 5.0, color);
                    if response.clicked() {
                        clicked = Some(status);
                    }
                    if i % 3 == 2 {
                        ui.end_row();
                    }
                }
            });
            if let Some(status) = clicked {
                self.set_status(status);
            }
        });
    }

    fn automation_tab(&mut self, ui: &mut egui::Ui, snap: &Snapshot) {
        let mut changed = false;

        card(ui, "Auto-detect", |ui| {
            changed |= ui.checkbox(&mut self.config.auto_detect, "Switch status automatically").changed();
            muted(ui, "OBS open: Streaming · Steam game: Playing · nothing running: back to Online. Never overrides Offline or Sleeping (except OBS).");
            ui.add_enabled_ui(self.config.auto_detect, |ui| {
                changed |= ui
                    .checkbox(&mut self.config.lastfm_listening, "Show Last.fm scrobbles as “Listening to”")
                    .changed();
            });
            ui.separator();
            let d = &snap.detected;
            egui::Grid::new("detected").num_columns(2).spacing([16.0, 4.0]).show(ui, |ui| {
                ui.label(RichText::new("OBS").color(theme::MUTED));
                ui.label(if d.obs { "Running" } else { "Not running" });
                ui.end_row();
                ui.label(RichText::new("Steam").color(theme::MUTED));
                ui.label(d.game.as_deref().unwrap_or("—"));
                ui.end_row();
                ui.label(RichText::new("Last.fm").color(theme::MUTED));
                ui.label(d.track.as_deref().unwrap_or("—"));
                ui.end_row();
            });
        });

        card(ui, "Discord", |ui| {
            changed |= ui.checkbox(&mut self.config.discord_rpc, "Show my status in Discord (Rich Presence)").changed();
            if self.config.discord_rpc {
                muted(ui, if snap.discord_connected { "Connected to Discord" } else { "Waiting for Discord to start…" });
            }
        });

        let busy = snap.busy;
        let mut save_schedule = None;
        card(ui, "Sleep schedule", |ui| {
            let Some(draft) = &mut self.schedule else {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label("Loading…");
                });
                return;
            };
            ui.checkbox(&mut draft.enabled, "Go to Sleeping automatically");
            egui::Grid::new("schedule").num_columns(2).spacing([16.0, 6.0]).show(ui, |ui| {
                ui.label("Sleepy time");
                ui.add(TextEdit::singleline(&mut draft.sleepy).desired_width(60.0).hint_text("23:00"));
                ui.end_row();
                ui.label("Wakey time");
                ui.add(TextEdit::singleline(&mut draft.wakey).desired_width(60.0).hint_text("07:00"));
                ui.end_row();
            });
            muted(ui, "Romania time (Europe/Bucharest). Inside this window the site shows Sleeping while your PC is off, and goes back to Online afterwards.");
            let valid = is_time(&draft.sleepy) && is_time(&draft.wakey);
            if !valid {
                ui.colored_label(theme::ERROR, "Use 24-hour HH:MM, like 23:30");
            }
            if ui.add_enabled(valid && !busy, egui::Button::new("Save schedule")).clicked() {
                save_schedule = Some(SleepSchedule {
                    enabled: draft.enabled,
                    sleepy_time: draft.sleepy.trim().to_owned(),
                    wakey_time: draft.wakey.trim().to_owned(),
                });
            }
        });

        if let Some(schedule) = save_schedule {
            self.engine.send(Command::SaveSchedule(schedule));
        }
        if changed {
            self.save_config();
        }
    }

    fn settings_tab(&mut self, ui: &mut egui::Ui, ctx: &egui::Context, snap: &Snapshot) {
        card(ui, "API key", |ui| {
            muted(ui, "The website's STATUS_API_KEY. It's saved in your user config folder.");
            if !self.config.api_key.is_empty() {
                ui.label(format!("Saved: {}", "•".repeat(self.config.api_key.chars().count().min(24))));
            }
            ui.horizontal(|ui| {
                ui.add(
                    TextEdit::singleline(&mut self.key_input)
                        .password(true)
                        .hint_text("Paste API key")
                        .desired_width(ui.available_width() - 120.0),
                );
                let key = self.key_input.trim().to_owned();
                if ui.add_enabled(!key.is_empty(), egui::Button::new("Save")).clicked() {
                    self.config.api_key = key;
                    self.key_input.clear();
                    self.save_config();
                    self.tab = Tab::Status;
                }
                if ui.add_enabled(!self.config.api_key.is_empty(), egui::Button::new("Clear")).clicked() {
                    self.config.api_key.clear();
                    self.save_config();
                }
            });
        });

        card(ui, "Avatar", |ui| {
            muted(ui, "Upload a new profile picture for the website. PNG, JPG, GIF or WebP, up to 500 KB.");
            let enabled = !self.config.api_key.is_empty() && !snap.busy;
            if ui.add_enabled(enabled, egui::Button::new("Choose image…")).clicked() {
                if let Some(path) = rfd::FileDialog::new()
                    .set_title("Choose an avatar")
                    .add_filter("Images", &["png", "jpg", "jpeg", "gif", "webp"])
                    .pick_file()
                {
                    self.engine.send(Command::UploadAvatar(path));
                }
            }
        });

        let mut changed = false;
        card(ui, "App", |ui| {
            let close_text = if self.has_tray {
                "Closing the window hides it to the tray"
            } else {
                "Closing the window minimizes it"
            };
            changed |= ui.checkbox(&mut self.config.keep_running_when_closed, close_text).changed();
            muted(ui, "Heartbeats only run while the app is open; when it quits, the site shows you as Idle.");
            changed |= ui.checkbox(&mut self.config.start_minimized, "Start minimized").changed();
            if ui.checkbox(&mut self.config.autostart, "Start when I log in").changed() {
                if let Err(err) = autostart::set(self.config.autostart) {
                    self.config.autostart = !self.config.autostart;
                    self.settings_error = Some(format!("Couldn't change autostart: {err}"));
                }
                changed = true;
            }
            ui.add_space(4.0);
            if ui.button("Quit").clicked() {
                self.quit.store(true, Ordering::SeqCst);
                ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            }
        });
        if changed {
            self.save_config();
        }

        card(ui, "About", |ui| {
            ui.horizontal(|ui| {
                ui.label(format!("Version {}", env!("CARGO_PKG_VERSION")));
                ui.hyperlink_to("yabosen.live", crate::api::BASE_URL);
            });
        });
    }
}

impl eframe::App for App {
    fn logic(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if self.pending_hide > 0 {
            self.pending_hide -= 1;
            if self.pending_hide == 0 {
                self.hide(ctx);
            } else {
                ctx.request_repaint();
            }
        }

        let closing = ctx.input(|i| i.viewport().close_requested());
        if closing && self.config.keep_running_when_closed && !self.quit.load(Ordering::SeqCst) {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            self.hide(ctx);
        }
    }

    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        let snap = self.engine.snapshot();
        self.sync_schedule(&snap);

        let bar = egui::Frame::new().fill(theme::FACE).inner_margin(egui::Margin::symmetric(12, 8));
        egui::Panel::top("header").frame(bar).show(ui, |ui| self.header(ui, &snap));
        egui::Panel::bottom("footer").frame(bar).show(ui, |ui| self.footer(ui, &snap));
        egui::CentralPanel::default()
            .frame(egui::Frame::new().fill(theme::BG).inner_margin(egui::Margin::same(12)))
            .show(ui, |ui| {
                egui::ScrollArea::vertical().auto_shrink(false).show(ui, |ui| match self.tab {
                    Tab::Status => self.status_tab(ui, &snap),
                    Tab::Automation => self.automation_tab(ui, &snap),
                    Tab::Settings => self.settings_tab(ui, &ctx, &snap),
                });
            });

        // Keep "x min ago" labels and notices fresh.
        ctx.request_repaint_after(Duration::from_secs(1));
    }
}

// ---------- Small widgets & helpers ----------

fn card(ui: &mut egui::Ui, title: &str, add: impl FnOnce(&mut egui::Ui)) {
    egui::Frame::new()
        .fill(theme::FACE)
        .stroke(Stroke::new(1.0, theme::BORDER))
        .corner_radius(2)
        .inner_margin(egui::Margin::same(12))
        .show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.label(RichText::new(title).strong().color(theme::ACCENT));
            add(ui);
        });
    ui.add_space(10.0);
}

fn muted(ui: &mut egui::Ui, text: &str) {
    ui.label(RichText::new(text).small().color(theme::MUTED));
}

fn rgb([r, g, b]: [u8; 3]) -> Color32 {
    Color32::from_rgb(r, g, b)
}

fn dot(ui: &mut egui::Ui, color: Color32, size: f32) -> egui::Response {
    let (rect, response) = ui.allocate_exact_size(egui::vec2(size, size), egui::Sense::hover());
    let painter = ui.painter();
    painter.circle_filled(rect.center(), size / 2.0, color);
    painter.circle_stroke(rect.center(), size / 2.0, Stroke::new(1.0, Color32::from_black_alpha(140)));
    response
}

/// Colour + tooltip for the heartbeat indicator.
fn heartbeat_state(snap: &Snapshot) -> (Color32, String) {
    match &snap.heartbeat {
        None => (theme::MUTED, "No heartbeat sent yet".to_owned()),
        Some((at, Ok(()))) => (theme::OK, format!("Heartbeat OK · {}", ago(*at))),
        Some((at, Err(err))) => (theme::ERROR, format!("Heartbeat failed {}: {err}", ago(*at))),
    }
}

fn ago(at: DateTime<Local>) -> String {
    let secs = (Local::now() - at).num_seconds().max(0);
    match secs {
        0..=59 => "just now".to_owned(),
        60..=3599 => format!("{} min ago", secs / 60),
        _ if at.date_naive() == Local::now().date_naive() => format!("at {}", at.format("%H:%M")),
        _ => at.format("%b %-d, %H:%M").to_string(),
    }
}

fn ago_ms(ms: i64) -> String {
    DateTime::from_timestamp_millis(ms)
        .map(|t| ago(t.with_timezone(&Local)))
        .unwrap_or_else(|| "—".to_owned())
}

fn is_time(text: &str) -> bool {
    let text = text.trim();
    let Some((h, m)) = text.split_once(':') else { return false };
    h.len() == 2
        && m.len() == 2
        && h.parse::<u8>().is_ok_and(|h| h < 24)
        && m.parse::<u8>().is_ok_and(|m| m < 60)
}

#[cfg(test)]
mod tests {
    #[test]
    fn validates_schedule_times() {
        assert!(super::is_time("23:00"));
        assert!(super::is_time("07:05"));
        assert!(!super::is_time("7:05"));
        assert!(!super::is_time("24:00"));
        assert!(!super::is_time("12:60"));
    }
}
