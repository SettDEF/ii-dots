//! The shape the shell reads.
//!
//! Deliberately flat and pre-computed: the QML side should render, not derive.
//! Anything that needs arithmetic over the transaction list (month totals,
//! recurring detection) is done here, once per sync, rather than in bindings
//! that re-run on every repaint.

use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Account {
    pub uid: String,
    pub name: String,
    pub iban_tail: String,
    pub currency: String,
    pub balance: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Txn {
    pub date: String,
    pub amount: f64,
    pub currency: String,
    pub counterparty: String,
    pub reference: String,
    pub category: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Recurring {
    pub counterparty: String,
    pub amount: f64,
    pub currency: String,
    pub category: String,
    /// Rough cadence in days, from the median gap between sightings.
    pub every_days: i64,
    pub last_seen: String,
    pub occurrences: usize,
}

/// A recurring debit projected forward to its next due date.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Upcoming {
    pub counterparty: String,
    pub amount: f64,
    pub category: String,
    pub due_date: String,
    pub days_until: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct State {
    pub generated_at: String,
    pub currency: String,
    pub total_balance: f64,
    pub spent_this_month: f64,
    pub income_this_month: f64,
    pub accounts: Vec<Account>,
    pub transactions: Vec<Txn>,
    pub recurring: Vec<Recurring>,
    pub by_category: HashMap<String, f64>,
    /// Last full month, for the month-over-month delta.
    pub prev_month_spent: f64,
    /// Recurring debits projected to their next due date, soonest first.
    pub upcoming: Vec<Upcoming>,
    /// Balance minus everything known to be leaving in the next 30 days.
    /// The number people actually want: not "what do I have" but "what can I
    /// spend without breaking something already committed".
    pub safe_to_spend: f64,
    /// Per-day net flow over the window, oldest first — enough for a sparkline.
    pub daily_net: Vec<f64>,
    /// ISO date the consent dies, so the UI can nag before it does.
    pub consent_expires: Option<String>,
    pub error: Option<String>,
}

/// Keyword → category. Crude on purpose: a first pass that is easy to read and
/// easy to extend beats a model nobody can correct. Everything unmatched lands
/// in "other" rather than being guessed at.
const RULES: &[(&str, &str)] = &[
    ("rewe", "groceries"), ("edeka", "groceries"), ("aldi", "groceries"),
    ("lidl", "groceries"), ("penny", "groceries"), ("netto", "groceries"),
    ("dm-", "groceries"), ("rossmann", "groceries"),
    ("supermarket", "groceries"), ("grocer", "groceries"),
    ("netflix", "subscriptions"), ("spotify", "subscriptions"),
    ("youtube", "subscriptions"), ("patreon", "subscriptions"),
    ("github", "subscriptions"), ("openai", "subscriptions"),
    ("anthropic", "subscriptions"), ("adobe", "subscriptions"),
    ("vodafone", "bills"), ("telekom", "bills"), ("o2", "bills"),
    ("stadtwerke", "bills"), ("strom", "bills"), ("gas", "bills"),
    ("energy", "bills"), ("electric", "bills"), ("utilities", "bills"),
    ("mobile", "bills"), ("broadband", "bills"),
    ("versicherung", "insurance"), ("allianz", "insurance"),
    ("insurance", "insurance"),
    ("miete", "rent"), ("kaltmiete", "rent"), ("vermiet", "rent"),
    ("hausverwaltung", "rent"), ("rent", "rent"), ("landlord", "rent"),
    ("properties", "rent"), ("letting", "rent"),
    ("db vertrieb", "transport"), ("deutsche bahn", "transport"),
    ("railway", "transport"), ("transit", "transport"), ("fuel", "transport"),
    ("uber", "transport"), ("tankstelle", "transport"), ("shell", "transport"),
    ("aral", "transport"), ("bvg", "transport"),
    ("amazon", "shopping"), ("zalando", "shopping"), ("otto", "shopping"),
    ("steam", "games"), ("nintendo", "games"), ("playstation", "games"),
    ("mcdonald", "eating-out"), ("burger", "eating-out"), ("lieferando", "eating-out"),
    ("deliveroo", "eating-out"), ("coffee", "eating-out"),
    ("restaurant", "eating-out"), ("cafe", "eating-out"), ("bakery", "eating-out"),
    ("apotheke", "health"), ("arzt", "health"), ("klinik", "health"),
    ("pharmacy", "health"), ("clinic", "health"), ("dentist", "health"),
    ("gehalt", "income"), ("lohn", "income"), ("salary", "income"),
    ("payroll", "income"), ("wages", "income"),
];

pub fn categorise(counterparty: &str, reference: &str) -> String {
    let hay = format!("{counterparty} {reference}").to_lowercase();
    for (needle, cat) in RULES {
        if hay.contains(needle) {
            return (*cat).to_string();
        }
    }
    "other".into()
}

fn parse_date(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(&s[..s.len().min(10)], "%Y-%m-%d").ok()
}

/// A counterparty seen 3+ times with a stable-ish amount is treated as
/// recurring. Three is the smallest number that can show a *rhythm* rather
/// than a coincidence, which matters when the window is only 90 days.
pub fn find_recurring(txns: &[Txn]) -> Vec<Recurring> {
    let mut groups: HashMap<String, Vec<&Txn>> = HashMap::new();
    for t in txns.iter().filter(|t| t.amount < 0.0) {
        let key = t.counterparty.to_lowercase();
        if key.is_empty() {
            continue;
        }
        groups.entry(key).or_default().push(t);
    }

    let mut out = Vec::new();
    for (_, mut list) in groups {
        if list.len() < 3 {
            continue;
        }
        list.sort_by(|a, b| a.date.cmp(&b.date));

        // Amounts must cluster: a shop you visit often is not a subscription.
        let amounts: Vec<f64> = list.iter().map(|t| t.amount.abs()).collect();
        let mean = amounts.iter().sum::<f64>() / amounts.len() as f64;
        let spread = amounts.iter().map(|a| (a - mean).abs()).fold(0.0, f64::max);
        if mean <= 0.0 || spread / mean > 0.15 {
            continue;
        }

        let mut gaps: Vec<i64> = list
            .windows(2)
            .filter_map(|w| {
                let a = parse_date(&w[0].date)?;
                let b = parse_date(&w[1].date)?;
                Some((b - a).num_days())
            })
            .filter(|g| *g > 0)
            .collect();
        if gaps.is_empty() {
            continue;
        }
        gaps.sort_unstable();
        let every = gaps[gaps.len() / 2];

        let last = list.last().unwrap();
        out.push(Recurring {
            counterparty: last.counterparty.clone(),
            amount: -mean,
            currency: last.currency.clone(),
            category: last.category.clone(),
            every_days: every,
            last_seen: last.date.clone(),
            occurrences: list.len(),
        });
    }
    out.sort_by(|a, b| a.amount.partial_cmp(&b.amount).unwrap_or(std::cmp::Ordering::Equal));
    out
}

pub fn month_totals(txns: &[Txn], today: NaiveDate) -> (f64, f64, HashMap<String, f64>) {
    let mut spent = 0.0;
    let mut income = 0.0;
    let mut by_cat: HashMap<String, f64> = HashMap::new();
    for t in txns {
        let Some(d) = parse_date(&t.date) else { continue };
        if d.year() != today.year() || d.month() != today.month() {
            continue;
        }
        if t.amount < 0.0 {
            spent += -t.amount;
            *by_cat.entry(t.category.clone()).or_insert(0.0) += -t.amount;
        } else {
            income += t.amount;
        }
    }
    (spent, income, by_cat)
}

/// Projects each recurring debit one cadence past its last sighting.
///
/// Anything already overdue is clamped to today rather than shown as negative:
/// a bill that has not landed yet is still money about to leave, and burying it
/// below "today" is exactly when it surprises you.
pub fn project_upcoming(recurring: &[Recurring], today: NaiveDate) -> Vec<Upcoming> {
    let mut out: Vec<Upcoming> = recurring
        .iter()
        .filter_map(|r| {
            let last = parse_date(&r.last_seen)?;
            let mut due = last + chrono::Duration::days(r.every_days.max(1));
            while due < today {
                due = due + chrono::Duration::days(r.every_days.max(1));
            }
            Some(Upcoming {
                counterparty: r.counterparty.clone(),
                amount: r.amount,
                category: r.category.clone(),
                due_date: due.format("%Y-%m-%d").to_string(),
                days_until: (due - today).num_days(),
            })
        })
        .collect();
    out.sort_by_key(|u| u.days_until);
    out
}

/// Spend for the calendar month before `today`.
pub fn prev_month_spent(txns: &[Txn], today: NaiveDate) -> f64 {
    let (y, m) = if today.month() == 1 {
        (today.year() - 1, 12)
    } else {
        (today.year(), today.month() - 1)
    };
    txns.iter()
        .filter(|t| t.amount < 0.0)
        .filter_map(|t| parse_date(&t.date).map(|d| (d, t)))
        .filter(|(d, _)| d.year() == y && d.month() == m)
        .map(|(_, t)| -t.amount)
        .sum()
}

/// Net flow per day across the window, oldest first. Fixed-length so the UI can
/// draw it without knowing the window size.
pub fn daily_net(txns: &[Txn], today: NaiveDate, days: i64) -> Vec<f64> {
    let mut buckets = vec![0.0; days.max(1) as usize];
    for t in txns {
        let Some(d) = parse_date(&t.date) else { continue };
        let back = (today - d).num_days();
        if back < 0 || back >= days {
            continue;
        }
        let idx = (days - 1 - back) as usize;
        buckets[idx] += t.amount;
    }
    buckets
}
