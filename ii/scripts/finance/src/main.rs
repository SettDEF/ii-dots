//! finance-sync — pulls balances and transactions into a JSON file the
//! quickshell left sidebar renders.
//!
//! Why a timer and not a live feed: PSD2 caps *unattended* access at roughly
//! four calls per account per day, and consent expires every 90 days. So this
//! syncs on a schedule and the UI always paints from the cached file, which
//! also means the sidebar opens instantly instead of waiting on a bank.

mod api;
mod callback;
mod config;
mod model;

use anyhow::{Context, Result};
use chrono::{Duration, Utc};
use clap::{Parser, Subcommand};
use model::{Account, State, Txn};
use serde_json::Value;

#[derive(Parser)]
#[command(name = "finance-sync", about = "Bank data for the quickshell sidebar")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// List supported banks for a country, e.g. `banks --country DE`.
    Banks {
        /// Emit a JSON array instead of TSV.
        #[arg(long)]
        json: bool,
        #[arg(long, default_value = "DE")]
        country: String,
        #[arg(long)]
        filter: Option<String>,
    },
    /// Begin authorization; prints the URL to open in a browser.
    Auth {
        #[arg(long)]
        bank: String,
        #[arg(long, default_value = "DE")]
        country: String,
        #[arg(long, default_value = "http://localhost:8899/callback")]
        redirect: String,
        #[arg(long, default_value_t = 90)]
        days: i64,
    },
    /// Finish authorization with the `code` from the redirect URL.
    Finish {
        #[arg(long)]
        code: String,
    },
    /// Fetch and write the state file.
    Sync {
        #[arg(long, default_value_t = 90)]
        days: i64,
    },
    /// One-command setup: finds the downloaded key, writes the credentials,
    /// picks a bank, opens the browser and catches the redirect. Run this.
    Setup {
        /// Path to the .pem from the Enable Banking control panel. Omitted:
        /// looks for a UUID-named .pem in ~/Downloads.
        #[arg(long)]
        key: Option<String>,
        #[arg(long, default_value = "DE")]
        country: String,
        #[arg(long, default_value = "http://localhost:8899/callback")]
        redirect: String,
        /// Exact bank name. Given, the two interactive prompts are skipped
        /// entirely — which is what lets the sidebar drive this instead of a
        /// terminal.
        #[arg(long)]
        bank: Option<String>,
        /// Emit one JSON object per stage on stdout instead of prose, so a UI
        /// can show real progress rather than a spinner and a guess.
        #[arg(long)]
        json: bool,
    },
    /// Write a realistic fixture so the UI can be built before any bank is
    /// linked. Same schema as a real sync, so nothing has to change later.
    Demo,
}

fn client() -> Result<api::Client> {
    let app_id = config::secret(config::APP_ID_KEY)?;
    let key_path = config::secret(config::KEY_PATH_KEY)?;
    let key_path = std::path::PathBuf::from(shellexpand_home(&key_path));
    // Refuse before reading, not after.
    config::assert_key_perms(&key_path)?;
    let pem = std::fs::read_to_string(&key_path)
        .with_context(|| format!("reading private key at {}", key_path.display()))?;
    api::Client::new(&app_id, &pem)
}

/// Only `~` — deliberately not a general shell expansion, since this value
/// comes from a file and expanding `$(...)` out of it would be a hole.
fn shellexpand_home(p: &str) -> String {
    if let Some(rest) = p.strip_prefix("~/") {
        return config::home().join(rest).to_string_lossy().into_owned();
    }
    p.to_string()
}

fn write_json(path: &std::path::Path, v: &impl serde::Serialize) -> Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;

    if let Some(dir) = path.parent() {
        config::harden_dir(dir)?;
    }
    // Write-then-rename: the shell has a FileView watching this, and a partial
    // read of a half-written file would surface as a parse error in the UI.
    //
    // The temp file is created 0600 up front rather than chmod-ed afterwards —
    // otherwise there is a window, however brief, where balances and a 90-day
    // transaction history sit on disk world-readable.
    let tmp = path.with_extension("tmp");
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)
        .with_context(|| format!("creating {}", tmp.display()))?;
    f.write_all(&serde_json::to_vec_pretty(v)?)?;
    f.sync_all()?;
    drop(f);
    std::fs::rename(&tmp, path)?;
    config::harden(path)?;
    Ok(())
}

fn str_at<'a>(v: &'a Value, path: &[&str]) -> &'a str {
    let mut cur = v;
    for p in path {
        match cur.get(p) {
            Some(next) => cur = next,
            None => return "",
        }
    }
    cur.as_str().unwrap_or("")
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Banks { country, filter, json } => {
            let list = client()?.aspsps(&country)?;
            let matched: Vec<_> = list
                .into_iter()
                .filter(|b| {
                    filter
                        .as_ref()
                        .map(|f| b.name.to_lowercase().contains(&f.to_lowercase()))
                        .unwrap_or(true)
                })
                .collect();
            if json {
                let arr: Vec<_> = matched
                    .iter()
                    .map(|b| serde_json::json!({ "country": b.country, "name": b.name }))
                    .collect();
                println!("{}", serde_json::to_string(&arr)?);
            } else {
                for b in &matched {
                    println!("{}\t{}", b.country, b.name);
                }
            }
        }

        Cmd::Auth { bank, country, redirect, days } => {
            let v = client()?.start_auth(&bank, &country, &redirect, days)?;
            let url = str_at(&v, &["url"]);
            if url.is_empty() {
                println!("{}", serde_json::to_string_pretty(&v)?);
            } else {
                println!("Open this in a browser, approve, then copy the `code`");
                println!("parameter out of the URL you land on:\n\n{url}\n");
                println!("Then run:  finance-sync finish --code <code>");
            }
        }

        Cmd::Finish { code } => {
            let v = client()?.create_session(&code)?;
            let sid = str_at(&v, &["session_id"]);
            anyhow::ensure!(!sid.is_empty(), "no session_id in response: {v}");
            write_json(&config::session_path(), &v)?;
            println!("Linked. session_id={sid}");
            println!("Now run:  finance-sync sync");
        }

        Cmd::Sync { days } => {
            let out = do_sync(days);
            // A failed sync still writes state, with the error in it. A sidebar
            // that silently shows yesterday's number is worse than one that
            // says it could not refresh.
            let state = match out {
                Ok(s) => s,
                Err(e) => {
                    let mut prev: State = std::fs::read_to_string(config::state_path())
                        .ok()
                        .and_then(|b| serde_json::from_str(&b).ok())
                        .unwrap_or_else(empty_state);
                    prev.error = Some(e.to_string());
                    prev.generated_at = Utc::now().to_rfc3339();
                    write_json(&config::state_path(), &prev)?;
                    return Err(e);
                }
            };
            write_json(&config::state_path(), &state)?;
            println!(
                "{} accounts, {} transactions -> {}",
                state.accounts.len(),
                state.transactions.len(),
                config::state_path().display()
            );
        }

        Cmd::Setup { key, country, redirect, bank, json } => {
            setup(key, &country, &redirect, bank, json)?;
        }

        Cmd::Demo => {
            let state = demo_state();
            write_json(&config::state_path(), &state)?;
            println!("Wrote fixture to {}", config::state_path().display());
        }
    }
    Ok(())
}

/// Fills the derived fields. Shared by sync and demo so the two can never
/// disagree about how a number is computed.
fn finish_state(mut s: State, txns: &[model::Txn]) -> State {
    let today = Utc::now().date_naive();
    s.prev_month_spent = model::prev_month_spent(txns, today);
    s.upcoming = model::project_upcoming(&s.recurring, today);
    // Only what falls inside 30 days counts against spendable balance;
    // a bill 60 days out is not this month's problem.
    let committed: f64 = s
        .upcoming
        .iter()
        .filter(|u| u.days_until <= 30)
        .map(|u| u.amount.abs())
        .sum();
    s.safe_to_spend = s.total_balance - committed;
    s.daily_net = model::daily_net(txns, today, 30);
    s
}

fn empty_state() -> State {
    State {
        generated_at: Utc::now().to_rfc3339(),
        currency: "EUR".into(),
        total_balance: 0.0,
        spent_this_month: 0.0,
        income_this_month: 0.0,
        accounts: vec![],
        transactions: vec![],
        recurring: vec![],
        by_category: Default::default(),
        prev_month_spent: 0.0,
        upcoming: vec![],
        safe_to_spend: 0.0,
        daily_net: vec![],
        consent_expires: None,
        error: None,
    }
}

fn do_sync(days: i64) -> Result<State> {
    let c = client()?;
    let session: Value = serde_json::from_str(
        &std::fs::read_to_string(config::session_path())
            .context("no linked session — run `finance-sync auth` first")?,
    )?;
    let sid = str_at(&session, &["session_id"]).to_string();
    let live = c.session(&sid)?;

    let from = (Utc::now() - Duration::days(days))
        .format("%Y-%m-%d")
        .to_string();

    let mut accounts = Vec::new();
    let mut txns: Vec<Txn> = Vec::new();

    let empty = vec![];
    let account_list = live
        .get("accounts")
        .and_then(|a| a.as_array())
        .unwrap_or(&empty);

    for a in account_list {
        let uid = a.get("uid").and_then(|u| u.as_str()).unwrap_or_default();
        if uid.is_empty() {
            continue;
        }
        let iban = str_at(a, &["account_id", "iban"]);
        let currency = {
            let c = str_at(a, &["currency"]);
            if c.is_empty() { "EUR" } else { c }
        };

        let bal = c.balances(uid)?;
        let balance = bal
            .get("balances")
            .and_then(|b| b.as_array())
            .and_then(|arr| arr.first())
            .map(|b| str_at(b, &["balance_amount", "amount"]).parse::<f64>().unwrap_or(0.0))
            .unwrap_or(0.0);

        accounts.push(Account {
            uid: uid.to_string(),
            name: {
                let n = str_at(a, &["name"]);
                if n.is_empty() { "Account".into() } else { n.to_string() }
            },
            iban_tail: iban.chars().rev().take(4).collect::<String>().chars().rev().collect(),
            currency: currency.to_string(),
            balance,
        });

        let tx = c.transactions(uid, &from)?;
        if let Some(list) = tx.get("transactions").and_then(|t| t.as_array()) {
            for t in list {
                let amount_raw = str_at(t, &["transaction_amount", "amount"])
                    .parse::<f64>()
                    .unwrap_or(0.0);
                // Enable Banking reports magnitude plus a DBIT/CRDT indicator
                // rather than a signed number.
                let debit = str_at(t, &["credit_debit_indicator"]).eq_ignore_ascii_case("DBIT");
                let amount = if debit { -amount_raw } else { amount_raw };

                let counterparty = {
                    let a = str_at(t, &["creditor", "name"]);
                    if !a.is_empty() { a.to_string() } else { str_at(t, &["debtor", "name"]).to_string() }
                };
                let reference = t
                    .get("remittance_information")
                    .and_then(|r| r.as_array())
                    .map(|a| {
                        a.iter()
                            .filter_map(|x| x.as_str())
                            .collect::<Vec<_>>()
                            .join(" ")
                    })
                    .unwrap_or_default();
                let date = {
                    let d = str_at(t, &["booking_date"]);
                    if d.is_empty() { str_at(t, &["value_date"]).to_string() } else { d.to_string() }
                };

                txns.push(Txn {
                    category: model::categorise(&counterparty, &reference),
                    date,
                    amount,
                    currency: currency.to_string(),
                    counterparty,
                    reference,
                });
            }
        }
    }

    txns.sort_by(|a, b| b.date.cmp(&a.date));
    let today = Utc::now().date_naive();
    let (spent, income, by_category) = model::month_totals(&txns, today);

    let state = State {
        generated_at: Utc::now().to_rfc3339(),
        currency: accounts.first().map(|a| a.currency.clone()).unwrap_or_else(|| "EUR".into()),
        total_balance: accounts.iter().map(|a| a.balance).sum(),
        spent_this_month: spent,
        income_this_month: income,
        recurring: model::find_recurring(&txns),
        by_category,
        consent_expires: session
            .get("access")
            .and_then(|a| a.get("valid_until"))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string()),
        prev_month_spent: 0.0,
        upcoming: vec![],
        safe_to_spend: 0.0,
        daily_net: vec![],
        accounts,
        transactions: txns.clone(),
        error: None,
    };
    Ok(finish_state(state, &txns))
}

/// Fixture data. Shaped exactly like a real sync so the QML built against it
/// needs no changes once a bank is linked.
fn demo_state() -> State {
    let today = Utc::now().date_naive();
    let d = |back: i64| (today - Duration::days(back)).format("%Y-%m-%d").to_string();

    // Monthly items are spaced ~30 days apart on purpose: the recurring
    // detector reports the median gap, so fixture data that is not actually
    // monthly makes the UI show a nonsense cadence.
    let raw: Vec<(i64, f64, &str, &str)> = vec![
        // this month
        (1, -43.20, "Tesco Metro", "Groceries"),
        (2, -6.30, "Corner Bakery", "Breakfast"),
        (3, -21.00, "National Railway", "Ticket"),
        (4, -68.90, "Amazon EU", "Order 302-88"),
        (5, -12.49, "Netflix", "Monthly subscription"),
        (6, -9.99, "Spotify AB", "Premium"),
        (7, -52.10, "Whole Foods", "Groceries"),
        (8, -74.55, "Vodafone", "Mobile plan"),
        (9, -31.99, "Steam Games", "Purchase"),
        (10, -1180.00, "Northgate Properties", "Rent - Apartment 4B"),
        (11, 3120.00, "Acme Corp", "Salary"),
        (14, -47.80, "Tesco Metro", "Groceries"),
        // last month
        (35, -12.49, "Netflix", "Monthly subscription"),
        (36, -9.99, "Spotify AB", "Premium"),
        (38, -74.55, "Vodafone", "Mobile plan"),
        (40, -1180.00, "Northgate Properties", "Rent - Apartment 4B"),
        (41, 3120.00, "Acme Corp", "Salary"),
        (44, -39.10, "Whole Foods", "Groceries"),
        // the month before
        (65, -12.49, "Netflix", "Monthly subscription"),
        (66, -9.99, "Spotify AB", "Premium"),
        (68, -74.55, "Vodafone", "Mobile plan"),
        (70, -1180.00, "Northgate Properties", "Rent - Apartment 4B"),
        (71, 3120.00, "Acme Corp", "Salary"),
    ];

    let txns: Vec<Txn> = raw
        .into_iter()
        .map(|(back, amount, who, why)| Txn {
            date: d(back),
            amount,
            currency: "EUR".into(),
            category: model::categorise(who, why),
            counterparty: who.into(),
            reference: why.into(),
        })
        .collect();

    let (spent, income, by_category) = model::month_totals(&txns, today);
    let state = State {
        generated_at: Utc::now().to_rfc3339(),
        currency: "EUR".into(),
        total_balance: 4212.86,
        spent_this_month: spent,
        income_this_month: income,
        accounts: vec![
            Account { uid: "demo-1".into(), name: "Current".into(), iban_tail: "4821".into(), currency: "EUR".into(), balance: 3187.44 },
            Account { uid: "demo-2".into(), name: "Savings".into(), iban_tail: "9910".into(), currency: "EUR".into(), balance: 1025.42 },
        ],
        recurring: model::find_recurring(&txns),
        by_category,
        prev_month_spent: 0.0,
        upcoming: vec![],
        safe_to_spend: 0.0,
        daily_net: vec![],
        consent_expires: Some((Utc::now() + Duration::days(74)).format("%Y-%m-%d").to_string()),
        transactions: txns.clone(),
        error: None,
    };
    finish_state(state, &txns)
}

// ── Guided setup ─────────────────────────────────────────────────────────────

fn prompt(msg: &str) -> Result<String> {
    use std::io::Write;
    print!("{msg}");
    std::io::stdout().flush()?;
    let mut line = String::new();
    std::io::stdin().read_line(&mut line)?;
    Ok(line.trim().to_string())
}

/// The control panel names the downloaded key after the application id, so the
/// file itself carries both halves of what we need. Finding it removes the one
/// step where a user would have to copy a UUID by hand.
fn find_downloaded_key() -> Option<(String, std::path::PathBuf)> {
    let dl = config::home().join("Downloads");
    for e in std::fs::read_dir(dl).ok()?.flatten() {
        let path = e.path();
        if path.extension().and_then(|x| x.to_str()) != Some("pem") {
            continue;
        }
        let stem = path.file_stem()?.to_str()?.to_string();
        // A UUID: 8-4-4-4-12 hex. Anything else is somebody's unrelated key.
        let parts: Vec<&str> = stem.split('-').collect();
        let shaped = parts.len() == 5
            && [8usize, 4, 4, 4, 12]
                == [parts[0].len(), parts[1].len(), parts[2].len(), parts[3].len(), parts[4].len()]
            && parts.iter().all(|p| p.chars().all(|c| c.is_ascii_hexdigit()));
        if shaped {
            return Some((stem, path));
        }
    }
    None
}

/// Writes the credentials into ~/.secure/apikeys, replacing any existing lines
/// for the same names so re-running setup cannot stack duplicates.
fn write_credentials(app_id: &str, key_path: &std::path::Path) -> Result<()> {
    let file = config::home().join(".secure/apikeys");
    let existing = std::fs::read_to_string(&file).unwrap_or_default();
    let mut kept: Vec<String> = existing
        .lines()
        .filter(|l| {
            let t = l.trim().trim_start_matches("export ");
            !t.starts_with(config::APP_ID_KEY) && !t.starts_with(config::KEY_PATH_KEY)
        })
        .map(|l| l.to_string())
        .collect();
    kept.push(format!("{}={}", config::APP_ID_KEY, app_id));
    kept.push(format!("{}={}", config::KEY_PATH_KEY, key_path.display()));

    if let Some(dir) = file.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(&file, kept.join("\n") + "\n")?;
    config::harden(&file)?;
    Ok(())
}

/// Emits one JSON object per stage when `json` is set, so a UI can report what
/// is actually happening. Printed to stdout as newline-delimited objects — the
/// caller reads them as they arrive rather than waiting for the process to end,
/// which matters because the browser-consent stage can take minutes.
fn stage(json: bool, stage_name: &str, msg: &str) {
    if json {
        println!("{}", serde_json::json!({ "stage": stage_name, "message": msg }));
        use std::io::Write;
        let _ = std::io::stdout().flush();
    } else {
        println!("{msg}");
    }
}

fn setup(
    key: Option<String>,
    country: &str,
    redirect: &str,
    bank_arg: Option<String>,
    json: bool,
) -> Result<()> {
    println!("-- finance-sync setup --");

    // 1. Credentials.
    let have = config::secret(config::APP_ID_KEY).is_ok()
        && config::secret(config::KEY_PATH_KEY).is_ok();
    if have {
        println!("[ok] credentials already present in ~/.secure/apikeys");
    } else {
        let (app_id, src) = match key {
            Some(k) => {
                let p = std::path::PathBuf::from(shellexpand_home(&k));
                let stem = p
                    .file_stem()
                    .and_then(|x| x.to_str())
                    .ok_or_else(|| anyhow::anyhow!("no filename in {}", p.display()))?
                    .to_string();
                (stem, p)
            }
            None => find_downloaded_key().ok_or_else(|| {
                anyhow::anyhow!(
                    "no UUID-named .pem in ~/Downloads.\n\
                     Register an application in the Enable Banking control panel \
                     (pick Restricted Production), then re-run this - or pass --key <path>."
                )
            })?,
        };

        let dest = config::home().join(".secure/enablebanking.pem");
        if let Some(dir) = dest.parent() {
            std::fs::create_dir_all(dir)?;
        }
        std::fs::copy(&src, &dest)
            .with_context(|| format!("copying {} -> {}", src.display(), dest.display()))?;
        config::harden(&dest)?;
        write_credentials(&app_id, &dest)?;
        stage(json, "key", &format!("Key installed at {} (mode 600)", dest.display()));
        stage(json, "key", &format!("Application id {app_id} saved"));
    }

    // 2. Pick a bank. Supplied by --bank when a UI is driving; prompted for
    // only when a human is at a terminal.
    let c = client()?;
    let bank_owned: String = match bank_arg {
        Some(b) => {
            // Validated against the real list rather than trusted: a typo here
            // would otherwise surface much later as an opaque API error.
            let all = c.aspsps(country)?;
            let hit = all.iter().find(|x| x.name == b);
            anyhow::ensure!(hit.is_some(), "no bank in {country} named \"{b}\"");
            b
        }
        None => {
            let filter = prompt(&format!("\nSearch banks in {country}: "))?;
            let all = c.aspsps(country)?;
            let matches: Vec<_> = all
                .iter()
                .filter(|b| b.name.to_lowercase().contains(&filter.to_lowercase()))
                .collect();
            anyhow::ensure!(!matches.is_empty(), "no bank in {country} matches \"{filter}\"");
            for (i, b) in matches.iter().enumerate().take(30) {
                println!("  [{:>2}] {}", i + 1, b.name);
            }
            let pick = prompt("Number: ")?.parse::<usize>().unwrap_or(0);
            anyhow::ensure!(pick >= 1 && pick <= matches.len(), "not one of the listed numbers");
            matches[pick - 1].name.clone()
        }
    };
    let bank = &bank_owned;

    // 3. Authorize, catching the redirect ourselves.
    let v = c.start_auth(bank, country, redirect, 90)?;
    let url = str_at(&v, &["url"]).to_string();
    anyhow::ensure!(!url.is_empty(), "no authorization url returned");

    let port = callback::port_of(redirect);
    stage(json, "consent", &format!("Opening your browser to authorize with {bank}"));
    stage(json, "waiting", &format!("Waiting for the redirect on 127.0.0.1:{port}"));
    // Best effort: if no browser opens, the URL is printed below anyway.
    let _ = std::process::Command::new("xdg-open").arg(&url).spawn();
    if json {
        // The UI shows this as a fallback link when no browser appears.
        println!("{}", serde_json::json!({ "stage": "url", "url": url }));
        use std::io::Write;
        let _ = std::io::stdout().flush();
    } else {
        println!("If nothing opened, visit:\n{url}\n");
    }

    let code = callback::wait_for_code(port, 300)?;
    stage(json, "linked", "Authorization received");

    let session = c.create_session(&code)?;
    let sid = str_at(&session, &["session_id"]).to_string();
    anyhow::ensure!(!sid.is_empty(), "no session_id returned");
    write_json(&config::session_path(), &session)?;
    println!("[ok] session linked");

    // 4. First sync.
    let state = do_sync(90)?;
    write_json(&config::state_path(), &state)?;
    println!(
        "[ok] synced {} accounts, {} transactions",
        state.accounts.len(),
        state.transactions.len()
    );

    println!("\nThe Finance tab in the sidebar is live now.");
    println!("Keep it fresh every 6h with:  ./install.sh");
    Ok(())
}
