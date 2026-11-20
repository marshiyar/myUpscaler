//! The player's glue: its frames and state into the window, and the play, seek, frame-strip and source actions. The
//! player itself is in `player.rs`.

use std::cell::RefCell;
use std::rc::Rc;

use slint::{ComponentHandle, Image};

use crate::{append_log, player, progress, request_preview, with, Actions, App, AppWindow, State};

/// Applies the player's frames and state.
pub fn drain(ui: &AppWindow, state: &mut State) {
    let app = ui.global::<App>();
    while let Ok(event) = state.player_events.try_recv() {
        match event {
            player::Event::Frame(buffer, seconds) => {
                app.set_player_frame(Image::from_rgba8(buffer));
                app.set_has_player_frame(true);
                if app.get_playing() {
                    app.set_position(seconds as f32);
                }
                app.set_position_text(progress::clock(seconds).into());
            }
            player::Event::Playing(playing) => {
                app.set_playing(playing);
                // Paused on the original: show the adjusted preview of the frame stopped at.
                if !playing && app.get_source() == 0 {
                    request_preview(ui, state);
                }
            }
            player::Event::Failed(e) => append_log(ui, &format!("Playback: {e}\n")),
        }
    }
}

/// Plays the imported video (0) or the finished export (1).
pub fn set_source(ui: &AppWindow, state: &mut State, source: i32) {
    let app = ui.global::<App>();
    let path = if source == 1 { state.completed.clone() } else { state.input.clone() };
    let Some(path) = path else { return };
    app.set_source(source);
    app.set_playing(false);
    app.set_has_player_frame(false);
    let _ = state.player.send(player::Command::Load(path));
    let _ = state.player.send(player::Command::Seek(app.get_position() as f64));
    if source == 0 {
        request_preview(ui, state);
    }
}

/// Connects the player's actions.
pub fn wire(ui: &AppWindow, state: &Rc<RefCell<State>>) {
    let actions = ui.global::<Actions>();
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_select_frame(move |index| {
        with(&w, &st, |ui, s| {
            let app = ui.global::<App>();
            app.set_selected_frame(index);
            let seconds = s.thumbnail_times.get(index as usize).copied().unwrap_or(0.0);
            app.set_position(seconds as f32);
            app.set_position_text(progress::clock(seconds).into());
            let _ = s.player.send(player::Command::Seek(seconds));
            request_preview(ui, s);
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_play_pause(move || {
        with(&w, &st, |ui, s| {
            let playing = ui.global::<App>().get_playing();
            let _ = s.player.send(if playing { player::Command::Pause } else { player::Command::Play });
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_seek(move |seconds| {
        with(&w, &st, |ui, s| {
            ui.global::<App>().set_position_text(progress::clock(seconds as f64).into());
            let _ = s.player.send(player::Command::Seek(seconds as f64));
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_seek_done(move || {
        with(&w, &st, |ui, s| {
            if !ui.global::<App>().get_playing() && ui.global::<App>().get_source() == 0 {
                request_preview(ui, s);
            }
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_set_source(move |source| with(&w, &st, |ui, s| set_source(ui, s, source)));
}
