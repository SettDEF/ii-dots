//! tmux: asks the running tmux for its binds, so the cheatsheet shows what
//! is really bound — your tmux.conf, plugins, and tmux's own defaults.
//!
//!   tmux show -gv prefix         the prefix key (C-Space here)
//!   tmux list-keys -N            binds that carry a note (tmux's own labels)
//!   tmux list-keys -T prefix     every prefix bind; unnoted ones are labelled
//!                                from their command
//!   tmux list-keys -T root       binds that need no prefix (mouse ones skipped)

use crate::model::{humanize, push, run, App, Bind, Section};
use std::collections::HashSet;

const ORDER: &[&str] = &["Windows", "Panes", "Layout", "Sessions", "Copy & paste", "No prefix", "Other"];

/// "C-M-x" → (["Ctrl", "Alt"], "x")
fn parse_key(k: &str) -> (Vec<String>, String) {
    let mut mods = Vec::new();
    let mut rest = k;
    loop {
        if let Some(r) = rest.strip_prefix("C-") { mods.push("Ctrl".into()); rest = r; }
        else if let Some(r) = rest.strip_prefix("M-") { mods.push("Alt".into()); rest = r; }
        else if let Some(r) = rest.strip_prefix("S-") { mods.push("Shift".into()); rest = r; }
        else { break; }
    }
    let key = match rest {
        "Enter" | "Space" | "Tab" | "Escape" | "BSpace" | "Up" | "Down" | "Left" | "Right" | "PPage" | "NPage" | "Home" | "End" => {
            match rest { "BSpace" => "Backspace", "PPage" => "Page_Up", "NPage" => "Page_Down", o => o }.to_string()
        }
        o => o.trim_start_matches('\\').to_string(),
    };
    (mods, key)
}

fn section_for(text: &str) -> &'static str {
    let t = text.to_lowercase();
    if t.contains("layout") { "Layout" }
    else if t.contains("pane") || t.contains("split") || t.contains("zoom") { "Panes" }
    else if t.contains("window") { "Windows" }
    else if t.contains("session") || t.contains("client") || t.contains("detach") { "Sessions" }
    else if t.contains("copy") || t.contains("paste") || t.contains("buffer") { "Copy & paste" }
    else { "Other" }
}

/// A label for a bind without a note: its command, readable and short.
fn label_from_command(cmd: &str) -> String {
    // the first command of a sequence, without flags' values that are code
    let first = cmd.split(" \\; ").next().unwrap_or(cmd).trim();
    let words: Vec<&str> = first.split_whitespace().take(4).filter(|w| !w.starts_with('{') && !w.starts_with('"')).collect();
    let s = humanize(&words.join(" "));
    if s.chars().count() > 48 { format!("{}…", s.chars().take(47).collect::<String>()) } else { s }
}

/// One `list-keys` line → (table, key, command)
fn parse_bind_line(line: &str) -> Option<(String, String, String)> {
    let mut it = line.split_whitespace();
    if it.next()? != "bind-key" { return None; }
    let mut repeat = false;
    let mut table = String::new();
    let mut key = None;
    while let Some(tok) = it.next() {
        match tok {
            "-r" => repeat = true,
            "-T" => table = it.next()?.to_string(),
            "-N" => { it.next(); }
            t => { key = Some(t.to_string()); break; }
        }
    }
    let _ = repeat;
    let cmd: Vec<&str> = it.collect();
    Some((table, key?, cmd.join(" ")))
}

/// tmux args against the running server, or — when none is running — a
/// private one started from your tmux.conf just for this, so the list is the
/// same either way.
fn tmux(args: &[&str]) -> Option<String> {
    if run("tmux", &["has-session"]).is_some() {
        return run("tmux", args);
    }
    let mut a = vec!["-L", "keybinds-sync"];
    a.extend_from_slice(args);
    run("tmux", &a)
}

pub fn extract() -> Option<App> {
    run("tmux", &["-V"])?;
    // no server: start the private one (it reads ~/.config/tmux/tmux.conf like any other)
    let private = run("tmux", &["has-session"]).is_none();
    if private {
        run("tmux", &["-L", "keybinds-sync", "new-session", "-d", "-s", "keybinds-sync"])?;
        std::thread::sleep(std::time::Duration::from_millis(400));
    }
    let app = extract_from_server();
    if private {
        run("tmux", &["-L", "keybinds-sync", "kill-server"]);
    }
    app
}

fn extract_from_server() -> Option<App> {
    let prefix_raw = tmux(&["show", "-gv", "prefix"]).map(|s| s.trim().to_string()).unwrap_or_else(|| "C-b".into());
    let (pm, pk) = parse_key(&prefix_raw);
    let prefix_label = pm.iter().map(String::as_str).chain(std::iter::once(pk.as_str())).collect::<Vec<_>>().join("+");

    let mut sections: Vec<Section> = Vec::new();
    let mut seen: HashSet<(String, bool)> = HashSet::new();

    // 1. binds with notes: "<key> <note>" lines, the prefix ones start with the prefix
    if let Some(notes) = tmux(&["list-keys", "-N"]) {
        for line in notes.lines() {
            let line = line.trim_end();
            let (is_prefix, rest) = match line.strip_prefix(&prefix_raw) {
                Some(r) if r.starts_with(' ') => (true, r.trim_start()),
                _ => (false, line),
            };
            let Some((k, note)) = rest.split_once(char::is_whitespace) else { continue };
            let note = note.trim();
            if note.is_empty() { continue; }
            let (mut mods, key) = parse_key(k);
            if is_prefix { mods.insert(0, "Prefix".into()); }
            seen.insert((k.to_string(), is_prefix));
            let sec = if is_prefix { section_for(note) } else { "No prefix" };
            push(&mut sections, sec, Bind { mods, key, comment: note.to_string() });
        }
    }

    // 2. prefix and root binds without notes (yours, from tmux.conf and plugins)
    for (table, is_prefix) in [("prefix", true), ("root", false)] {
        let Some(list) = tmux(&["list-keys", "-T", table]) else { continue };
        for line in list.lines() {
            let Some((_, k, cmd)) = parse_bind_line(line) else { continue };
            if seen.contains(&(k.clone(), is_prefix)) { continue; }
            // the mouse is not something a cheatsheet needs to teach
            if k.contains("Mouse") || k.contains("Wheel") || k.contains("Click") || k.contains("Drag") { continue; }
            seen.insert((k.clone(), is_prefix));
            let (mut mods, key) = parse_key(&k);
            if is_prefix { mods.insert(0, "Prefix".into()); }
            let comment = label_from_command(&cmd);
            if comment.is_empty() { continue; }
            let sec = if is_prefix { section_for(&cmd) } else { "No prefix" };
            push(&mut sections, sec, Bind { mods, key, comment });
        }
    }

    Some(App::new("tmux", "tmux", "view_quilt", format!("Prefix = {prefix_label}"), sections, ORDER))
}
