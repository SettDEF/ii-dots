//! Enable Banking REST client.
//!
//! Auth is a self-signed RS256 JWT rather than an API key: you register an
//! application, they hold the public half, and every request carries a short
//! lived token you mint locally with the private half. Nothing to rotate on
//! their side, and the key never leaves the machine.

use anyhow::{anyhow, Context, Result};
use chrono::Utc;
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const BASE: &str = "https://api.enablebanking.com";

// READ-ONLY BY CONSTRUCTION. Every method below is a GET, or a POST to /auth
// and /sessions which only establish consent. There is deliberately no method
// touching payment initiation, and there should never be one: this tool asks
// for AIS scope, so a PIS call would fail anyway — but the absence is the
// point. Nothing here can move money.

#[derive(Serialize)]
struct Claims {
    iss: String,
    aud: String,
    iat: i64,
    exp: i64,
}

pub struct Client {
    token: String,
}

impl Client {
    pub fn new(app_id: &str, key_pem: &str) -> Result<Self> {
        let now = Utc::now().timestamp();
        let claims = Claims {
            iss: "enablebanking.com".into(),
            aud: "api.enablebanking.com".into(),
            iat: now,
            // Deliberately short. The token is minted per run, so a long life
            // buys nothing and only widens the window if it ever leaks.
            exp: now + 3600,
        };
        let mut header = Header::new(Algorithm::RS256);
        // Enable Banking routes the request to your application by the key id,
        // so this is not optional.
        header.kid = Some(app_id.to_string());
        let key = EncodingKey::from_rsa_pem(key_pem.as_bytes())
            .context("parsing the RSA private key (expected a PKCS#1/PKCS#8 PEM)")?;
        let token = encode(&header, &claims, &key).context("signing the JWT")?;
        Ok(Self { token })
    }

    fn get(&self, path: &str) -> Result<Value> {
        let resp = ureq::get(&format!("{BASE}{path}"))
            .set("Authorization", &format!("Bearer {}", self.token))
            .call();
        Self::read(resp, path)
    }

    fn post(&self, path: &str, body: Value) -> Result<Value> {
        let resp = ureq::post(&format!("{BASE}{path}"))
            .set("Authorization", &format!("Bearer {}", self.token))
            .send_json(body);
        Self::read(resp, path)
    }

    /// Turns ureq's error shape into something with the server's own message
    /// in it — a bare "400 Bad Request" is useless when debugging consent.
    fn read(resp: Result<ureq::Response, ureq::Error>, path: &str) -> Result<Value> {
        match resp {
            Ok(r) => r.into_json::<Value>().context("decoding response JSON"),
            Err(ureq::Error::Status(code, r)) => {
                // Only the machine-readable error fields, never the raw body.
                // Error text lands in the journal, and a failed transactions
                // call can echo account data back in its response.
                let body = r.into_string().unwrap_or_default();
                let detail = serde_json::from_str::<Value>(&body)
                    .ok()
                    .and_then(|v| {
                        v.get("error")
                            .or_else(|| v.get("message"))
                            .and_then(|e| e.as_str())
                            .map(|s| s.to_string())
                    })
                    .unwrap_or_else(|| "<response body withheld>".into());
                Err(anyhow!("{path} -> HTTP {code}: {detail}"))
            }
            Err(e) => Err(anyhow!("{path} -> {e}")),
        }
    }

    /// Banks available in a country, e.g. "DE".
    pub fn aspsps(&self, country: &str) -> Result<Vec<Aspsp>> {
        let v = self.get(&format!("/aspsps?country={country}"))?;
        let list = v
            .get("aspsps")
            .and_then(|a| a.as_array())
            .ok_or_else(|| anyhow!("unexpected /aspsps shape: {v}"))?;
        Ok(list
            .iter()
            .filter_map(|a| {
                Some(Aspsp {
                    name: a.get("name")?.as_str()?.to_string(),
                    country: a
                        .get("country")
                        .and_then(|c| c.as_str())
                        .unwrap_or(country)
                        .to_string(),
                })
            })
            .collect())
    }

    /// Starts an authorization and returns the URL the human has to open.
    pub fn start_auth(&self, bank: &str, country: &str, redirect: &str, days: i64) -> Result<Value> {
        // PSD2 consent is capped at 90 days in practice; asking for more just
        // gets silently clamped or rejected depending on the bank.
        let valid_until = (Utc::now() + chrono::Duration::days(days)).to_rfc3339();
        self.post(
            "/auth",
            serde_json::json!({
                "access": { "valid_until": valid_until },
                "aspsp": { "name": bank, "country": country },
                "redirect_url": redirect,
                "state": uuid::Uuid::new_v4().to_string(),
                "psu_type": "personal",
            }),
        )
    }

    /// Exchanges the code from the redirect for a session holding the accounts.
    pub fn create_session(&self, code: &str) -> Result<Value> {
        self.post("/sessions", serde_json::json!({ "code": code }))
    }

    pub fn session(&self, id: &str) -> Result<Value> {
        self.get(&format!("/sessions/{id}"))
    }

    pub fn balances(&self, account_uid: &str) -> Result<Value> {
        self.get(&format!("/accounts/{account_uid}/balances"))
    }

    pub fn transactions(&self, account_uid: &str, from: &str) -> Result<Value> {
        self.get(&format!(
            "/accounts/{account_uid}/transactions?date_from={from}"
        ))
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Aspsp {
    pub name: String,
    pub country: String,
}
