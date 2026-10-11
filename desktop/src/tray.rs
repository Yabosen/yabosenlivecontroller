//! Windows tray icon: keeps the app reachable while its window is hidden.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use eframe::egui::{Context, ViewportCommand};
use tray_icon::menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use tray_icon::{Icon, MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent};

pub struct Tray {
    _icon: TrayIcon,
}

/// Creates the tray icon. `quit` is set when the user picks "Quit" from its menu.
pub fn create(ctx: Context, quit: Arc<AtomicBool>) -> Option<Tray> {
    let show = MenuItem::new("Show Yabosen Controller", true, None);
    let exit = MenuItem::new("Quit", true, None);
    let menu = Menu::new();
    menu.append_items(&[&show, &PredefinedMenuItem::separator(), &exit]).ok()?;

    let icon = Icon::from_rgba(crate::icon::rgba(32), 32, 32).ok()?;
    let tray = TrayIconBuilder::new()
        .with_tooltip("Yabosen Controller")
        .with_icon(icon)
        .with_menu(Box::new(menu))
        .build()
        .ok()?;

    let (show_id, exit_id) = (show.id().clone(), exit.id().clone());
    let menu_ctx = ctx.clone();
    MenuEvent::set_event_handler(Some(move |event: MenuEvent| {
        if event.id == show_id {
            reveal(&menu_ctx);
        } else if event.id == exit_id {
            quit.store(true, Ordering::SeqCst);
            menu_ctx.send_viewport_cmd(ViewportCommand::Close);
            menu_ctx.request_repaint();
        }
    }));
    TrayIconEvent::set_event_handler(Some(move |event: TrayIconEvent| {
        if let TrayIconEvent::Click {
            button: MouseButton::Left,
            button_state: MouseButtonState::Up,
            ..
        } = event
        {
            reveal(&ctx);
        }
    }));

    Some(Tray { _icon: tray })
}

fn reveal(ctx: &Context) {
    ctx.send_viewport_cmd(ViewportCommand::Visible(true));
    ctx.send_viewport_cmd(ViewportCommand::Minimized(false));
    ctx.send_viewport_cmd(ViewportCommand::Focus);
    ctx.request_repaint();
}
