//! Credentials and paths.
//!
//! The Enable Banking application id and the path to its RSA private key come
//! from ~/.secure/apikeys, which is where every other key in this setup lives —
//! deliberately not a finance-specific dotfile, so there is one place to audit
//! and one place to lock down.

use anyhow::{anyhow, bail, Context, Result};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

pub const APP_ID_KEY: &str = "ENABLE_BANKING_APP_ID";
pub const KEY_PATH_KEY: &str = "ENABLE_BANKING_KEY_PATH";

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/home/caesar".into()))
}

/// Reads `NAME=value` out of ~/.secure/apikeys.
///
/// The file is shell-sourced elsewhere, so values may be quoted and lines may
/// be `export`-prefixed or commented.
pub fn secret(name: &str) -> Result<String> {
    // The environment wins when the key file has already been sourced, which
    // is the normal case for an interactive run.
    if let Ok(v) = std::env::var(name) {
        if !v.trim().is_empty() {
            return Ok(v);
        }
    }
    let path = home().join(".secure/apikeys");
    let body = std::fs::read_to_string(&path)
        .with_context(|| format!("reading {}", path.display()))?;
    for line in body.lines() {
        let line = line.trim().trim_start_matches("export ").trim();
        if line.starts_with('#') {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else { continue };
        if k.trim() != name {
            continue;
        }
        let v = v.trim().trim_matches(['"', '\'']).to_string();
        if !v.is_empty() {
            return Ok(v);
        }
    }
    Err(anyhow!(
        "{name} not found in {} (or the environment)",
        path.display()
    ))
}

/// Where the shell reads its data from. Same directory as the rest of the
/// quickshell state, so it is covered by whatever backs that up.
pub fn state_path() -> PathBuf {
    home().join(".local/state/quickshell/finance.json")
}

/// Session ids and consent expiry. Kept apart from the state file because this
/// is credential-adjacent and the state file is read by the UI.
pub fn session_path() -> PathBuf {
    home().join(".local/state/quickshell/finance-session.json")
}

/// Refuses to use a private key that anyone but the owner can read.
///
/// This key IS the credential — with it you can mint tokens that read every
/// linked account. ssh refuses to use a world-readable key for the same reason,
/// and a finance tool has no business being laxer than ssh.
pub fn assert_key_perms(path: &Path) -> Result<()> {
    let md = std::fs::metadata(path)
        .with_context(|| format!("stat {}", path.display()))?;
    let mode = md.permissions().mode() & 0o777;
    if mode & 0o077 != 0 {
        bail!(
            "private key {} is mode {:o} — group/other can read it.\n\
             Fix with: chmod 600 {}",
            path.display(),
            mode,
            path.display()
        );
    }
    Ok(())
}

/// Creates (or tightens) a file to owner-only.
///
/// The state file holds balances and a 90-day transaction history, and the
/// session file holds what is effectively a bearer credential for the account.
/// Neither should ever be readable by another user on the box, and the default
/// umask does not guarantee that.
pub fn harden(path: &Path) -> Result<()> {
    if let Ok(md) = std::fs::metadata(path) {
        let mut perms = md.permissions();
        perms.set_mode(0o600);
        std::fs::set_permissions(path, perms)
            .with_context(|| format!("chmod 600 {}", path.display()))?;
    }
    Ok(())
}

/// The containing directory, owner-only too — a 0600 file inside a 0755 dir
/// still leaks its name, size and mtime.
pub fn harden_dir(path: &Path) -> Result<()> {
    std::fs::create_dir_all(path)?;
    let mut perms = std::fs::metadata(path)?.permissions();
    perms.set_mode(0o700);
    std::fs::set_permissions(path, perms).ok();
    Ok(())
}
