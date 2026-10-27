//! filecopy copy|cut <path>...
//!
//! Puts files on the Wayland clipboard in every format a file manager reads,
//! in ONE offer — `wl-copy` can only offer a single MIME type, which is why a
//! cut on the desktop could not be pasted in Dolphin:
//!
//! - `text/uri-list`                    — what Dolphin / KIO and most apps paste
//! - `application/x-kde-cutselection`   — "1" marks a cut for KDE apps
//! - `x-special/gnome-copied-files`     — "cut|copy" + URIs, for GTK file managers
//! - `text/plain`                       — the paths, for terminals and editors
//!
//! Stays in the foreground serving the clipboard until something else is
//! copied, so start it detached.

use std::path::Path;
use wl_clipboard_rs::copy::{MimeSource, MimeType, Options, Source};

fn uri(path: &str) -> String {
    let abs = Path::new(path)
        .canonicalize()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| path.to_string());
    let mut out = String::from("file://");
    for b in abs.bytes() {
        if b.is_ascii_alphanumeric() || b"/-_.~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn main() {
    let mut args = std::env::args().skip(1);
    let op = args.next().unwrap_or_default();
    let paths: Vec<String> = args.collect();
    if !(op == "copy" || op == "cut") || paths.is_empty() {
        eprintln!("usage: filecopy copy|cut <path>...");
        std::process::exit(2);
    }
    let uris: Vec<String> = paths.iter().map(|p| uri(p)).collect();

    let offer = |mime: &str, data: String| MimeSource {
        source: Source::Bytes(data.into_bytes().into_boxed_slice()),
        mime_type: MimeType::Specific(mime.to_string()),
    };
    let mut sources = vec![
        offer("text/uri-list", uris.iter().map(|u| format!("{u}\r\n")).collect()),
        offer("x-special/gnome-copied-files", format!("{op}\n{}", uris.join("\n"))),
        offer("text/plain;charset=utf-8", paths.join("\n")),
        offer("text/plain", paths.join("\n")),
    ];
    if op == "cut" {
        sources.push(offer("application/x-kde-cutselection", "1".into()));
    }

    let mut opts = Options::new();
    opts.foreground(true);
    if let Err(e) = opts.copy_multi(sources) {
        eprintln!("filecopy: {e}");
        std::process::exit(1);
    }
}
