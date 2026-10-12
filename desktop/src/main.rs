// No console window for release builds on Windows.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod api;
mod app;
mod autostart;
mod config;
mod detect;
mod discord;
mod engine;
mod icon;
mod single;
mod theme;
#[cfg(windows)]
mod tray;

use eframe::egui;

fn main() -> eframe::Result {
    if std::env::args().any(|a| a == "--version" || a == "-V") {
        println!("yabosen-controller {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    let Some(instance) = single::acquire() else {
        // Already running; it has been asked to show its window.
        return Ok(());
    };
    let config = config::Config::load();
    // `--minimized` is what the "start with system" entry passes.
    let minimized = config.start_minimized || std::env::args().any(|a| a == "--minimized");

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Yabosen Controller")
            .with_app_id("yabosen-controller")
            .with_inner_size([440.0, 700.0])
            .with_min_inner_size([380.0, 480.0])
            .with_icon(egui::IconData { rgba: icon::rgba(64), width: 64, height: 64 }),
        ..Default::default()
    };

    eframe::run_native(
        "Yabosen Controller",
        options,
        Box::new(move |cc| {
            single::listen(instance, cc.egui_ctx.clone());
            Ok(Box::new(app::App::new(cc, config, minimized)))
        }),
    )
}
