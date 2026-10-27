//! WezTerm: asks wezterm itself (`wezterm show-keys`), so the list is the
//! merged result of the defaults and your wezterm.lua, key tables included.
//!
//!   Leader: Char('q') CTRL 1s
//!   Default key table
//!   	CTRL         T       ->   EmitEvent("toggle-tab-bar")
//!   Key Table: copy_mode
//!   	SHIFT   Tab          ->   CopyMode(MoveBackwardWord)

use crate::model::{humanize, push, run, App, Bind, Section};
use std::collections::HashSet;

const ORDER: &[&str] = &["Tabs", "Panes", "Clipboard", "Scrolling", "Font", "Window", "Other", "Copy mode", "Search mode"];

/// "ActivatePaneDirection" → "activate pane direction"
fn words(camel: &str) -> String {
    let mut out = String::new();
    for (i, c) in camel.chars().enumerate() {
        if c.is_uppercase() && i > 0 { out.push(' '); }
        out.extend(c.to_lowercase());
    }
    out
}

/// What an action does, in words.
fn describe(action: &str) -> String {
    let (name, arg) = match action.split_once('(') {
        Some((n, a)) => (n.trim(), a.trim_end_matches(')').trim().trim_matches('"')),
        None => (action.trim(), ""),
    };
    let s = match name {
        "EmitEvent" => humanize(arg),
        "PasteFrom" => "Paste".into(),
        "CopyTo" => "Copy".into(),
        "SpawnTab" => "New tab".into(),
        "SpawnWindow" => "New window".into(),
        "CloseCurrentTab" => "Close tab".into(),
        "CloseCurrentPane" => "Close pane".into(),
        "ActivateTabRelative" => if arg.starts_with('-') { "Previous tab".into() } else { "Next tab".into() },
        "ActivateTab" => arg.parse::<i64>().map(|n| if n < 0 { "Last tab".into() } else { format!("Go to tab {}", n + 1) }).unwrap_or_else(|_| "Go to tab".into()),
        "MoveTabRelative" => if arg.starts_with('-') { "Move tab left".into() } else { "Move tab right".into() },
        "SplitHorizontal" => "Split side by side".into(),
        "SplitVertical" => "Split top and bottom".into(),
        "ActivatePaneDirection" => format!("Focus pane {}", arg.to_lowercase()),
        "AdjustPaneSize" => format!("Resize pane {}", arg.split(',').next().unwrap_or("").trim().to_lowercase()),
        "TogglePaneZoomState" => "Zoom pane".into(),
        "IncreaseFontSize" => "Bigger font".into(),
        "DecreaseFontSize" => "Smaller font".into(),
        "ResetFontSize" => "Reset font size".into(),
        "ScrollByPage" => if arg.starts_with('-') { "Scroll up a page".into() } else { "Scroll down a page".into() },
        "ScrollByLine" => if arg.starts_with('-') { "Scroll up a line".into() } else { "Scroll down a line".into() },
        "ScrollToTop" => "Scroll to top".into(),
        "ScrollToBottom" => "Scroll to bottom".into(),
        "ActivateCopyMode" => "Copy mode".into(),
        "QuickSelect" => "Quick select (copy a word on screen)".into(),
        "ToggleFullScreen" => "Fullscreen".into(),
        "ReloadConfiguration" => "Reload config".into(),
        "ShowLauncher" | "ShowLauncherArgs" => "Launcher".into(),
        "ShowTabNavigator" => "Tab navigator".into(),
        "ActivateCommandPalette" => "Command palette".into(),
        "CharSelect" => "Emoji & character picker".into(),
        "Search" => "Search".into(),
        "ClearScrollback" => "Clear scrollback".into(),
        "CopyMode" => humanize(&words(arg.split(['(', ',']).next().unwrap_or(arg))),
        "Nop" | "DisableDefaultAssignment" => String::new(),
        other => humanize(&words(other)),
    };
    s
}

fn section_for(action: &str) -> &'static str {
    let a = action.to_lowercase();
    if a.contains("tab") { "Tabs" }
    else if a.contains("pane") || a.contains("split") { "Panes" }
    else if a.contains("paste") || a.contains("copyto") || a.contains("copy_to") || a.starts_with("copyto") { "Clipboard" }
    else if a.contains("scroll") { "Scrolling" }
    else if a.contains("font") { "Font" }
    else if a.contains("window") || a.contains("fullscreen") { "Window" }
    else { "Other" }
}

/// "ALT | CTRL" → ["Ctrl", "Alt"]
fn mods(col: &str) -> Vec<String> {
    let mut out = Vec::new();
    let c = col.to_uppercase();
    if c.contains("LEADER") { out.push("Leader".into()); }
    if c.contains("SUPER") { out.push("Super".into()); }
    if c.contains("CTRL") { out.push("Ctrl".into()); }
    if c.contains("ALT") { out.push("Alt".into()); }
    if c.contains("SHIFT") { out.push("Shift".into()); }
    out
}

pub fn extract() -> Option<App> {
    let text = run("wezterm", &["show-keys"])?;
    let mut sections: Vec<Section> = Vec::new();
    let mut table = String::from("default");
    let mut note = String::new();
    let mut seen: HashSet<(String, String)> = HashSet::new();

    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("Leader: ") {
            // "Char('q') CTRL 1s"
            let key = rest.split('\'').nth(1).unwrap_or("?").to_uppercase();
            let m = mods(rest);
            note = format!("Leader = {}", m.iter().map(String::as_str).chain(std::iter::once(key.as_str())).collect::<Vec<_>>().join("+"));
            continue;
        }
        if line.starts_with("Default key table") { table = "default".into(); continue; }
        if let Some(t) = line.strip_prefix("Key Table: ") { table = t.trim().to_string(); continue; }
        let Some((lhs, action)) = line.split_once("->") else { continue };
        let action = action.trim();
        // lhs: "<mods column>   <key>"; the key is the last token
        let lhs = lhs.trim_end();
        let Some(split) = lhs.rfind(char::is_whitespace) else { continue };
        let (mcol, key) = (&lhs[..split], lhs[split..].trim());
        if key.is_empty() { continue; }
        let comment = describe(action);
        if comment.is_empty() { continue; }
        // "SHIFT $" and "$" doing the same thing appear once
        if !seen.insert((table.clone(), format!("{key}|{comment}"))) { continue; }
        let section = match table.as_str() {
            "default" => section_for(action),
            "copy_mode" => "Copy mode",
            "search_mode" => "Search mode",
            _ => "Other",
        };
        push(&mut sections, section, Bind { mods: mods(mcol), key: key.to_string(), comment });
    }
    Some(App::new("wezterm", "WezTerm", "terminal", note, sections, ORDER))
}
