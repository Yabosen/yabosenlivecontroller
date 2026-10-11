//! One instance at a time. Launching the app again just brings the running window forward
//! (otherwise you'd get two heartbeats, two tray icons and dueling auto-detect).

use std::net::{Ipv4Addr, TcpListener, TcpStream};
use std::thread;

use eframe::egui::{Context, ViewportCommand};

const PORT: u16 = 47_853;

/// `Some(listener)` if we're the first instance. Otherwise pokes the running one and
/// returns `None`.
pub fn acquire() -> Option<TcpListener> {
    match TcpListener::bind((Ipv4Addr::LOCALHOST, PORT)) {
        Ok(listener) => Some(listener),
        Err(_) => {
            let _ = TcpStream::connect((Ipv4Addr::LOCALHOST, PORT));
            None
        }
    }
}

/// Shows the window whenever another launch pokes us.
pub fn listen(listener: TcpListener, ctx: Context) {
    thread::Builder::new()
        .name("single-instance".into())
        .spawn(move || {
            for _ in listener.incoming() {
                ctx.send_viewport_cmd(ViewportCommand::Visible(true));
                ctx.send_viewport_cmd(ViewportCommand::Minimized(false));
                ctx.send_viewport_cmd(ViewportCommand::Focus);
                ctx.request_repaint();
            }
        })
        .expect("failed to start single-instance listener");
}
