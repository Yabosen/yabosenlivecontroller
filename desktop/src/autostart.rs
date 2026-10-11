//! Start with Windows (registry Run key) or Linux (XDG autostart entry).

use auto_launch::{AutoLaunch, AutoLaunchBuilder};

fn launcher() -> Result<AutoLaunch, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    AutoLaunchBuilder::new()
        .set_app_name("Yabosen Controller")
        .set_app_path(&exe.to_string_lossy())
        .set_args(&["--minimized"])
        .build()
        .map_err(|e| e.to_string())
}

pub fn is_enabled() -> bool {
    launcher().ok().and_then(|l| l.is_enabled().ok()).unwrap_or(false)
}

pub fn set(enabled: bool) -> Result<(), String> {
    let launcher = launcher()?;
    let result = if enabled { launcher.enable() } else { launcher.disable() };
    result.map_err(|e| e.to_string())
}
