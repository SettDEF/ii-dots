//! zsh: the line-editor keys worth knowing — your widgets (fzf and friends),
//! your macros (`bindkey -s`) and the editing commands a config usually adds.
//! Asked of an interactive zsh, so it is your .zshrc that answers. zsh's own
//! emacs defaults and the completion system's internal widgets are left out:
//! they are dozens of rows nobody looks up.

use crate::model::{humanize, push, run, App, Bind, Section};
use std::collections::HashSet;

/// Builtin widgets worth listing because a config binds them on purpose.
const NOTABLE: &[(&str, &str)] = &[
    ("history-search-backward", "History: previous with this prefix"),
    ("history-search-forward", "History: next with this prefix"),
    ("history-substring-search-up", "History: previous containing this"),
    ("history-substring-search-down", "History: next containing this"),
    ("edit-command-line", "Edit the command in $EDITOR"),
    ("autosuggest-accept", "Accept the suggestion"),
    ("autosuggest-execute", "Accept the suggestion and run it"),
    ("clear-screen", "Clear the screen"),
    ("undo", "Undo"),
    ("push-line", "Park this line, type another"),
];

/// Friendlier names for well-known widgets.
fn describe(widget: &str) -> String {
    if let Some((_, d)) = NOTABLE.iter().find(|(w, _)| *w == widget) { return d.to_string(); }
    match widget {
        "fzf-history-widget" => "Search history (fzf)".into(),
        "fzf-file-widget" => "Insert a file path (fzf)".into(),
        "fzf-cd-widget" => "cd into a folder (fzf)".into(),
        "fzf_cd" => "cd into a folder (fzf)".into(),
        "fzf_killps" => "Kill a process (fzf)".into(),
        w => {
            let w = w.trim_matches('_').replace("__", " ");
            humanize(&w)
        }
    }
}

/// zsh's key notation → readable: "^X^E" → "Ctrl+X Ctrl+E", "^[[A" → "Up", "^[x" → "Alt+X"
fn key_name(k: &str) -> String {
    let k = k.trim_matches('"');
    match k {
        "^[[A" | "^[OA" => return "Up".into(),
        "^[[B" | "^[OB" => return "Down".into(),
        "^[[C" | "^[OC" => return "Right".into(),
        "^[[D" | "^[OD" => return "Left".into(),
        "^[[H" => return "Home".into(),
        "^[[F" => return "End".into(),
        "^?" => return "Backspace".into(),
        "^I" => return "Tab".into(),
        "^M" | "^J" => return "Enter".into(),
        " " => return "Space".into(),
        _ => {}
    }
    let mut parts = Vec::new();
    let mut chars = k.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '^' {
            match chars.next() {
                Some('[') => {
                    // Alt+<next> (escape prefix)
                    if let Some(n) = chars.next() { parts.push(format!("Alt+{}", n.to_uppercase())); }
                }
                Some('?') => parts.push("Backspace".into()),
                Some(n) => parts.push(format!("Ctrl+{}", n.to_uppercase())),
                None => {}
            }
        } else if c == '\\' {
            if let Some(n) = chars.next() { parts.push(n.to_string()); }
        } else {
            parts.push(c.to_string());
        }
    }
    parts.join(" ")
}

pub fn extract() -> Option<App> {
    let binds = run("zsh", &["-ic", "bindkey; print -r -- '---WIDGETS---'; zle -l"])?;
    let (keys, widgets) = binds.split_once("---WIDGETS---")?;
    // user-defined widgets: the first word of each `zle -l` line
    let user: HashSet<String> = widgets.lines().filter_map(|l| l.split_whitespace().next()).map(String::from).collect();

    let mut sections: Vec<Section> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for line in keys.lines() {
        // `"^R" fzf-history-widget`  or a macro: `"^O" "fzf-dmenu^J"`
        let Some(rest) = line.strip_prefix('"') else { continue };
        let Some(end) = rest.find("\" ") else { continue };
        let (k, target) = (&rest[..end], rest[end + 2..].trim());
        let (section, comment) = if target.starts_with('"') {
            ("Macros", format!("Type “{}”", target.trim_matches('"').replace("^J", " ⏎").replace("^M", " ⏎")))
        } else if NOTABLE.iter().any(|(w, _)| *w == target) {
            ("Line editing", describe(target))
        } else if user.contains(target) && !is_internal(target) {
            (if target.contains("fzf") { "fzf" } else { "Your widgets" }, describe(target))
        } else {
            continue;
        };
        let key = key_name(k);
        if !seen.insert(format!("{key}|{comment}")) { continue; }
        push(&mut sections, section, Bind { mods: Vec::new(), key, comment });
    }
    Some(App::new("zsh", "zsh", "prompt_suggestion", String::new(), sections, &["fzf", "Your widgets", "Line editing", "Macros"]))
}

/// Completion and highlighting plumbing that is technically user-defined.
fn is_internal(w: &str) -> bool {
    w.starts_with("_bash_") || w.starts_with("_complete") || w.starts_with("_correct") || w.starts_with("_expand")
        || w.starts_with("_history-complete") || w.starts_with("_list_") || w.starts_with("_most_recent")
        || w.starts_with("_next_tags") || w.starts_with("_read_comp") || w.starts_with("_zsh_highlight")
        || w.starts_with("_zsh_autosuggest") || w.starts_with("zle-")
}
