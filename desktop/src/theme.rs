//! Dark plum + lavender look, matching the website's Windows 98 theme.

use eframe::egui::{self, Color32, CornerRadius, Stroke};

pub const BG: Color32 = Color32::from_rgb(0x0e, 0x0a, 0x12);
pub const PANEL: Color32 = Color32::from_rgb(0x1c, 0x17, 0x23);
pub const FACE: Color32 = Color32::from_rgb(0x2b, 0x24, 0x34);
pub const FIELD: Color32 = Color32::from_rgb(0x16, 0x11, 0x1c);
pub const TEXT: Color32 = Color32::from_rgb(0xe8, 0xde, 0xfa);
pub const MUTED: Color32 = Color32::from_rgb(0xa3, 0x97, 0xb8);
pub const ACCENT: Color32 = Color32::from_rgb(0xb9, 0x8c, 0xff);
pub const SELECT: Color32 = Color32::from_rgb(0x7c, 0x4d, 0xcc);
pub const BORDER: Color32 = Color32::from_rgb(0x4a, 0x3e, 0x5c);
pub const ERROR: Color32 = Color32::from_rgb(0xff, 0x7a, 0x8a);
pub const OK: Color32 = Color32::from_rgb(0x4a, 0xde, 0x80);

pub fn apply(ctx: &egui::Context) {
    let mut visuals = egui::Visuals::dark();
    visuals.override_text_color = Some(TEXT);
    visuals.panel_fill = PANEL;
    visuals.window_fill = FACE;
    visuals.extreme_bg_color = FIELD;
    visuals.faint_bg_color = FACE;
    visuals.hyperlink_color = ACCENT;
    visuals.selection.bg_fill = SELECT;
    visuals.selection.stroke = Stroke::new(1.0, TEXT);
    visuals.window_corner_radius = CornerRadius::same(2);
    visuals.window_stroke = Stroke::new(1.0, BORDER);

    let square = CornerRadius::same(2);
    let w = &mut visuals.widgets;
    w.noninteractive.bg_fill = FACE;
    w.noninteractive.bg_stroke = Stroke::new(1.0, BORDER);
    w.noninteractive.fg_stroke = Stroke::new(1.0, TEXT);
    w.inactive.bg_fill = FACE;
    w.inactive.weak_bg_fill = FACE;
    w.inactive.bg_stroke = Stroke::new(1.0, BORDER);
    w.inactive.fg_stroke = Stroke::new(1.0, TEXT);
    w.hovered.bg_fill = Color32::from_rgb(0x3a, 0x30, 0x46);
    w.hovered.weak_bg_fill = Color32::from_rgb(0x3a, 0x30, 0x46);
    w.hovered.bg_stroke = Stroke::new(1.0, ACCENT);
    w.active.bg_fill = SELECT;
    w.active.weak_bg_fill = SELECT;
    w.active.bg_stroke = Stroke::new(1.0, ACCENT);
    w.open.weak_bg_fill = FACE;
    for state in [&mut w.noninteractive, &mut w.inactive, &mut w.hovered, &mut w.active, &mut w.open] {
        state.corner_radius = square;
    }

    ctx.set_visuals(visuals);
    ctx.global_style_mut(|style| {
        style.spacing.item_spacing = egui::vec2(8.0, 8.0);
        style.spacing.button_padding = egui::vec2(10.0, 5.0);
    });
}
