//! ai-activity — the live state of AI sessions, for the shell.
//!
//!   ai-activity hook        Claude Code hook: reads the event JSON on stdin,
//!                           updates $XDG_RUNTIME_DIR/ai-activity/<session>.json
//!   ai-activity list        every session, as JSON (for scripts and the CLI)
//!   ai-activity prune       drop ended sessions older than a day
//!
//! The hook PRINTS NOTHING and always exits 0. Claude Code adds a hook's
//! stdout to the model's context for some events (SessionStart,
//! UserPromptSubmit); a silent hook costs no tokens and can never block or
//! confuse a session, whatever goes wrong here.
//!
//! States: ready · working · needs_you · finished · ended
//!   SessionStart → ready          UserPromptSubmit → working (+ prompt)
//!   PreToolUse   → working (+1), needs_you for AskUserQuestion / ExitPlanMode
//!   Notification → needs_you only for a permission prompt or dialog (idle reminders ignored)
//!   PostToolUse  → Dotos kept in step: the agent's tasks (TaskCreate/TaskUpdate) as cards
//!                  linked agent:<id>, `dotos state ID doing` links that card, each git
//!                  commit recorded on the session and on the card it is working on
//!   Stop         → finished       SessionEnd       → ended

use serde_json::{json, Map, Value};
use std::io::Read;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

fn dir() -> PathBuf {
    let rt = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/tmp/{}", unsafe_uid()));
    PathBuf::from(rt).join("ai-activity")
}

fn unsafe_uid() -> String {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| s.lines().find(|l| l.starts_with("Uid:")).and_then(|l| l.split_whitespace().nth(1).map(String::from)))
        .unwrap_or_else(|| "0".into())
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// The `claude` process this hook runs under: hooks run through a shell, so
/// walk up the parents until a process named claude appears.
fn claude_pid() -> Option<u32> {
    let mut pid = std::process::id();
    for _ in 0..8 {
        let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
        let close = stat.rfind(')')?;
        let comm = &stat[stat.find('(')? + 1..close];
        if comm == "claude" && pid != std::process::id() {
            return Some(pid);
        }
        pid = stat[close + 2..].split_whitespace().nth(1)?.parse().ok()?;
        if pid <= 1 {
            return None;
        }
    }
    None
}

fn clip(s: &str, n: usize) -> String {
    let one: String = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if one.chars().count() <= n { one } else { one.chars().take(n).collect::<String>() + "…" }
}

fn write_atomic(path: &PathBuf, v: &Value) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, serde_json::to_vec(v).unwrap_or_default())?;
    std::fs::rename(tmp, path)
}

fn hook() -> Option<()> {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).ok()?;
    let ev: Value = serde_json::from_str(&input).ok()?;
    let sid = ev["session_id"].as_str()?.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-').collect::<String>();
    if sid.is_empty() {
        return None;
    }
    let d = dir();
    std::fs::create_dir_all(&d).ok()?;
    let path = d.join(format!("claude-{sid}.json"));
    let mut s: Map<String, Value> = std::fs::read_to_string(&path)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default();

    let t = now();
    let event = ev["hook_event_name"].as_str().unwrap_or("");
    if s.is_empty() {
        let cwd = ev["cwd"].as_str().unwrap_or("");
        s.insert("id".into(), json!(format!("claude-{sid}")));
        s.insert("source".into(), json!("claude-code"));
        s.insert("session".into(), json!(sid));
        s.insert("cwd".into(), json!(cwd));
        s.insert("started".into(), json!(t));
        s.insert("tools".into(), json!(0));
        // where to jump back to
        for (k, var) in [("tmux", "TMUX"), ("tmux_pane", "TMUX_PANE"), ("wezterm_pane", "WEZTERM_PANE")] {
            if let Ok(v) = std::env::var(var) {
                s.insert(k.into(), json!(v));
            }
        }
        if let Some(p) = claude_pid() {
            s.insert("pid".into(), json!(p));
        }
    }
    if let Some(cwd) = ev["cwd"].as_str() {
        s.insert("cwd".into(), json!(cwd));
        s.insert("project".into(), json!(project_of(cwd)));
    }

    let state = match event {
        "SessionStart" => "ready",
        "UserPromptSubmit" => {
            if let Some(p) = ev["prompt"].as_str() {
                s.insert("prompt".into(), json!(clip(p, 160)));
            }
            s.insert("turn_started".into(), json!(t));
            s.remove("message");
            "working"
        }
        "PreToolUse" => {
            let n = s.get("tools").and_then(|v| v.as_u64()).unwrap_or(0) + 1;
            s.insert("tools".into(), json!(n));
            let tool = ev["tool_name"].as_str().unwrap_or("");
            if !tool.is_empty() {
                s.insert("last_tool".into(), json!(tool));
            }
            // a question to the user (a choice dialog, a plan to approve) really waits for them
            if tool == "AskUserQuestion" || tool == "ExitPlanMode" {
                let q = ev["tool_input"]["questions"][0]["question"].as_str().unwrap_or("a question for you");
                s.insert("message".into(), json!(clip(q, 200)));
                "needs_you"
            } else {
                s.remove("message");
                "working"
            }
        }
        "Notification" => {
            // only a permission prompt or a dialog waits for the user; "waiting for your input" after
            // a finished turn is an idle reminder, not a need (it made "needs you" a lie)
            let kind = ev["notification_type"].as_str().unwrap_or("");
            let msg = ev["message"].as_str().unwrap_or("");
            let real = match kind {
                "permission_prompt" | "elicitation_dialog" => true,
                "" => msg.contains("permission"),
                _ => false,
            };
            if !real {
                return Some(());
            }
            s.insert("message".into(), json!(clip(msg, 200)));
            "needs_you"
        }
        "PostToolUse" => {
            dotos_mirror(&ev, &mut s, &sid);
            "working"
        }
        "Stop" => {
            s.remove("message");
            "finished"
        }
        "SessionEnd" => "ended",
        _ => return Some(()),
    };
    s.insert("state".into(), json!(state));
    s.insert("updated".into(), json!(t));
    write_atomic(&path, &Value::Object(s)).ok()
}

fn list() -> Vec<Value> {
    let mut out: Vec<Value> = std::fs::read_dir(dir())
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
        .filter_map(|e| std::fs::read_to_string(e.path()).ok())
        .filter_map(|t| serde_json::from_str::<Value>(&t).ok())
        // a session whose claude process is gone ended, whatever its file says
        // (a crash or a closed terminal sends no SessionEnd)
        .map(|mut v| {
            if let Some(p) = v["pid"].as_u64() {
                if !std::path::Path::new(&format!("/proc/{p}")).exists() {
                    v["state"] = json!("ended");
                }
            }
            v
        })
        .collect();
    out.sort_by_key(|v| std::cmp::Reverse(v["updated"].as_u64().unwrap_or(0)));
    out
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("hook") => {
            let _ = hook();
        }
        Some("list") => println!("{}", serde_json::to_string_pretty(&list()).unwrap_or_default()),
        Some("prune") => {
            let cutoff = now().saturating_sub(86_400);
            for v in list() {
                let gone = v["state"] == "ended" || v["pid"].as_u64().is_some_and(|p| !std::path::Path::new(&format!("/proc/{p}")).exists());
                if gone && v["updated"].as_u64().unwrap_or(0) < cutoff {
                    if let Some(id) = v["id"].as_str() {
                        let _ = std::fs::remove_file(dir().join(format!("{id}.json")));
                    }
                }
            }
        }
        _ => eprintln!("usage: ai-activity hook|list|prune"),
    }
}

/// The repository a folder belongs to (the nearest parent with a .git), by
/// name; the folder's own name when it is in none. A session that `cd`s into
/// src/ is still working on the project, not on "src".
fn project_of(cwd: &str) -> String {
    let mut p = std::path::Path::new(cwd);
    loop {
        if p.join(".git").exists() {
            return p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        }
        match p.parent() {
            Some(up) if up.as_os_str().len() > 1 => p = up,
            _ => break,
        }
    }
    cwd.rsplit('/').find(|s| !s.is_empty()).unwrap_or(cwd).to_string()
}

/// `dotos …` as the AI (DOTOS_WHO=ai), its JSON answer; quick (a few ms), never fatal.
fn dotos(args: &[&str]) -> Option<Value> {
    let out = std::process::Command::new("dotos").arg("--json").args(args).env("DOTOS_WHO", "ai").stdin(std::process::Stdio::null()).stderr(std::process::Stdio::null()).output().ok()?;
    serde_json::from_slice(&out.stdout).ok()
}

/// The agent's own task id from a TaskCreate answer (`{task: {id}}`, `{id}`, or "Task #N …").
fn task_id_of(resp: &Value) -> Option<String> {
    for v in [&resp["task"]["id"], &resp["id"], &resp["taskId"]] {
        if let Some(s) = v.as_str() {
            return Some(s.to_string());
        }
        if let Some(n) = v.as_u64() {
            return Some(n.to_string());
        }
    }
    let text = resp.as_str().map(String::from).unwrap_or_else(|| resp.to_string());
    let i = text.find('#')?;
    let n: String = text[i + 1..].chars().take_while(|c| c.is_ascii_digit()).collect();
    (!n.is_empty()).then_some(n)
}

/// The folders a shell command works in (`cd X`, `git -C X`), the session's folder last.
fn dirs_of(cmd: &str, cwd: &str) -> Vec<String> {
    let mut out = Vec::new();
    let words: Vec<&str> = cmd.split(|c: char| c.is_whitespace() || c == ';' || c == '&' || c == '(' || c == ')').filter(|w| !w.is_empty()).collect();
    for w in words.windows(2) {
        if w[0] == "cd" || w[0] == "-C" {
            let d = w[1].trim_matches(|c| c == '"' || c == '\'');
            let d = d.replacen('~', &std::env::var("HOME").unwrap_or_default(), 1);
            out.push(d);
        }
    }
    out.push(cwd.to_string());
    out
}

/// Keeps Dotos in step with what the agent does (PostToolUse).
fn dotos_mirror(ev: &Value, s: &mut Map<String, Value>, sid: &str) {
    let tool = ev["tool_name"].as_str().unwrap_or("");
    let input = &ev["tool_input"];
    let agent = format!("agent:claude-{sid}");
    let project = s.get("project").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let mut map = s.get("dotos_tasks").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    match tool {
        "TaskCreate" => {
            let Some(id) = task_id_of(&ev["tool_response"]) else { return };
            let subject = input["subject"].as_str().unwrap_or("").replace(['+', '>', '#', '@', '!', '~', '/'], " ");
            if subject.trim().is_empty() {
                return;
            }
            let line = if project.is_empty() { format!("{subject} >todo") } else { format!("{subject} +{project} >todo") };
            let Some(card) = dotos(&["capture", &line]) else { return };
            let Some(uid) = card["uid"].as_str() else { return };
            dotos(&["set", uid, &format!("link+={agent}")]);
            map.insert(id, json!(uid));
        }
        "TaskUpdate" => {
            let id = input["taskId"].as_str().map(String::from).or_else(|| input["taskId"].as_u64().map(|n| n.to_string())).unwrap_or_default();
            let Some(uid) = map.get(&id).and_then(|v| v.as_str()).map(String::from) else { return };
            if let Some(st) = input["status"].as_str() {
                let to = match st {
                    "in_progress" => "doing",
                    "completed" => "done",
                    "deleted" => "cancelled",
                    _ => "todo",
                };
                dotos(&["state", &uid, to]);
                if to == "doing" {
                    s.insert("task".into(), json!(uid));
                } else if s.get("task").and_then(|v| v.as_str()) == Some(uid.as_str()) {
                    s.remove("task");
                }
            }
            if let Some(t) = input["subject"].as_str() {
                dotos(&["set", &uid, &format!("title={t}")]);
            }
        }
        "Bash" => {
            let cmd = input["command"].as_str().unwrap_or("");
            // the agent moved a card itself: that card is what it works on, linked to it
            for part in cmd.split("&&").chain(cmd.split(';')) {
                let w: Vec<&str> = part.split_whitespace().collect();
                if let Some(i) = w.iter().position(|x| *x == "dotos") {
                    if w.get(i + 1) == Some(&"state") {
                        if let (Some(id), Some(st)) = (w.get(i + 2), w.get(i + 3)) {
                            if *st == "doing" {
                                dotos(&["set", id, &format!("link+={agent}")]);
                                s.insert("task".into(), json!(id));
                            } else if s.get("task").and_then(|v| v.as_str()) == Some(*id) {
                                s.remove("task");
                            }
                        }
                    }
                }
            }
            // a commit: on the session, and on the card it is working on
            if cmd.contains("git") && cmd.contains("commit") {
                let since = s.get("turn_started").and_then(|v| v.as_u64()).unwrap_or(0).saturating_sub(5);
                let mut commits = s.get("commits").and_then(|v| v.as_array()).cloned().unwrap_or_default();
                for d in dirs_of(cmd, ev["cwd"].as_str().unwrap_or("")) {
                    let Ok(out) = std::process::Command::new("git").args(["-C", &d, "log", "-1", "--format=%h%x09%ct%x09%s"]).stderr(std::process::Stdio::null()).output() else { continue };
                    let line = String::from_utf8_lossy(&out.stdout).trim().to_string();
                    let mut f = line.splitn(3, '\t');
                    let (Some(h), Some(ct), Some(msg)) = (f.next(), f.next(), f.next()) else { continue };
                    if ct.parse::<u64>().unwrap_or(0) < since || commits.iter().any(|c| c["hash"] == h) {
                        continue;
                    }
                    let repo = project_of(&d);
                    commits.push(json!({ "hash": h, "repo": repo, "msg": clip(msg, 140), "t": ct.parse::<u64>().unwrap_or(0) }));
                    if let Some(card) = s.get("task").and_then(|v| v.as_str()) {
                        dotos(&["set", card, &format!("link+=git:{repo}@{h}")]);
                    }
                }
                let keep = commits.len().saturating_sub(30);
                s.insert("commits".into(), json!(commits[keep..].to_vec()));
            }
        }
        _ => {}
    }
    if !map.is_empty() {
        s.insert("dotos_tasks".into(), Value::Object(map));
    }
}
