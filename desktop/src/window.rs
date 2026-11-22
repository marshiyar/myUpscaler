//! The window's own chrome. macOS: the title bar is transparent and the interface extends under it, so the toolbar
//! the interface draws is the window's unified toolbar, with the system's traffic lights at their platform position;
//! the empty part of the toolbar moves the window, and a double click follows the system setting. Windows: the
//! system caption buttons stay, and the title bar takes the interface's colours in light and dark.
//! Elsewhere the window keeps the system's decorations.

use crate::AppWindow;
use slint::winit_030::{winit, WinitWindowAccessor};
use slint::ComponentHandle;

/// Window attributes set before the window exists.
pub fn attributes(attributes: winit::window::WindowAttributes) -> winit::window::WindowAttributes {
    #[cfg(target_os = "macos")]
    {
        use winit::platform::macos::WindowAttributesExtMacOS;
        return attributes.with_titlebar_transparent(true).with_title_hidden(true).with_fullsize_content_view(true);
    }
    #[cfg(not(target_os = "macos"))]
    attributes
}

/// Applies the chrome to the window and again when the appearance changes. The native window exists only once the
/// event loop runs, so this reports whether it was there; `apply_when_ready` retries until it is.
pub fn apply(ui: &AppWindow) -> bool {
    #[cfg(target_os = "macos")]
    return mac::apply(ui);
    #[cfg(windows)]
    return windows::apply(ui);
    #[cfg(not(any(windows, target_os = "macos")))]
    {
        let _ = ui;
        true
    }
}

/// Applies the chrome as soon as the native window exists.
pub fn apply_when_ready(ui: slint::Weak<AppWindow>, attempt: u32) {
    let Some(window) = ui.upgrade() else { return };
    if !apply(&window) && attempt < 100 {
        slint::Timer::single_shot(std::time::Duration::from_millis(50), move || apply_when_ready(ui, attempt + 1));
    }
}

/// A press on the empty part of the toolbar: a double click zooms or minimises as the system setting says, anything
/// else starts moving the window.
#[cfg_attr(not(target_os = "macos"), allow(unused_variables))]
pub fn toolbar_press(ui: &AppWindow) {
    #[cfg(target_os = "macos")]
    mac::toolbar_press(ui);
}

#[cfg(target_os = "macos")]
mod mac {
    use super::*;
    use crate::App;
    use objc2::rc::Retained;
    use objc2_app_kit::{NSApplication, NSToolbar, NSView, NSWindow, NSWindowButton, NSWindowToolbarStyle};
    use objc2_foundation::{MainThreadMarker, NSString};
    use winit::raw_window_handle::{HasWindowHandle, RawWindowHandle};

    fn ns_window(window: &winit::window::Window) -> Option<Retained<NSWindow>> {
        let RawWindowHandle::AppKit(handle) = window.window_handle().ok()?.as_raw() else { return None };
        // SAFETY: the handle's view is alive while `window` is borrowed, and this runs on the main thread.
        let view: &NSView = unsafe { handle.ns_view.cast::<NSView>().as_ref() };
        view.window()
    }

    pub fn apply(ui: &AppWindow) -> bool {
        let app = ui.global::<App>();
        ui.window()
            .with_winit_window(|window| {
                let (Some(win), Some(mtm)) = (ns_window(window), MainThreadMarker::new()) else { return };
                // SAFETY: AppKit calls on the main thread with a live window.
                unsafe {
                    // An empty toolbar in the unified style gives the title bar the height of a toolbar and centres the
                    // traffic lights in it, as in a native app. The interface draws the toolbar's contents.
                    if win.toolbar().is_none() {
                        let toolbar = NSToolbar::initWithIdentifier(mtm.alloc(), &NSString::from_str("main"));
                        toolbar.setShowsBaselineSeparator(false);
                        win.setToolbar(Some(&toolbar));
                        win.setToolbarStyle(NSWindowToolbarStyle::Unified);
                    }
                    if let Some(zoom) = win.standardWindowButton(NSWindowButton::NSWindowZoomButton) {
                        // The toolbar is as tall as twice the distance from the window's top to the middle of the
                        // window buttons, so the buttons sit centred in it.
                        let rect = zoom.convertRect_toView(zoom.bounds(), None);
                        let middle = win.frame().size.height - (rect.origin.y + rect.size.height / 2.0);
                        if middle > 10.0 {
                            app.set_toolbar_height((middle * 2.0) as f32);
                        }
                        app.set_toolbar_inset((rect.origin.x + rect.size.width + 12.0) as f32);
                    }
                }
            })
            .is_some()
    }

    pub fn toolbar_press(ui: &AppWindow) {
        ui.window().with_winit_window(|window| {
            let Some(mtm) = MainThreadMarker::new() else { return };
            // SAFETY: AppKit calls on the main thread while the press is being handled.
            let double =
                unsafe { NSApplication::sharedApplication(mtm).currentEvent().is_some_and(|e| e.clickCount() >= 2) };
            if !double {
                let _ = window.drag_window();
                return;
            }
            let action = std::process::Command::new("defaults")
                .args(["read", "-g", "AppleActionOnDoubleClick"])
                .output()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned())
                .unwrap_or_default();
            match action.as_str() {
                "None" => {}
                "Minimize" => window.set_minimized(true),
                _ => window.set_maximized(!window.is_maximized()),
            }
        });
    }
}

#[cfg(windows)]
mod windows {
    use super::*;
    use crate::Theme;
    use winit::platform::windows::{Color, WindowExtWindows};
    use winit::window::Theme as WindowTheme;

    pub fn apply(ui: &AppWindow) -> bool {
        let theme = ui.global::<Theme>();
        let rgb = |c: slint::Color| Color::from_rgb(c.red(), c.green(), c.blue());
        let (dark, bar, text) = (theme.get_dark(), theme.get_bar(), theme.get_text());
        ui.window()
            .with_winit_window(|window| {
                // The dark or light caption buttons and frame, then the exact colours where the system allows them
                // (Windows 11); older systems keep the themed caption.
                window.set_theme(Some(if dark { WindowTheme::Dark } else { WindowTheme::Light }));
                window.set_title_background_color(Some(rgb(bar)));
                window.set_title_text_color(rgb(text));
                window.set_border_color(Some(rgb(bar)));
            })
            .is_some()
    }
}
