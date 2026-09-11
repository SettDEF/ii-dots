//! One-shot local listener that catches the `code` from the bank's redirect.
//!
//! Without this you have to read a query parameter out of the browser's address
//! bar and paste it into a terminal, which is the single most annoying step in
//! every OAuth-shaped flow. The bank redirects to localhost, this catches it,
//! and the browser shows a "you can close this" page.
//!
//! Deliberately std-only: a whole async HTTP stack to accept exactly one GET
//! would be absurd.

use anyhow::{anyhow, Context, Result};
use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::time::Duration;

const PAGE_OK: &str = "\
<!doctype html><meta charset=utf-8><title>Linked</title>
<body style=\"font-family:system-ui;background:#14121a;color:#e8e0ef;display:grid;place-items:center;height:100vh;margin:0\">
<div style=\"text-align:center\">
<div style=\"font-size:44px\">&#10003;</div>
<h2 style=\"margin:.4em 0\">Bank linked</h2>
<p style=\"opacity:.7\">You can close this tab and go back to the terminal.</p>
</div>";

const PAGE_ERR: &str = "\
<!doctype html><meta charset=utf-8><title>Failed</title>
<body style=\"font-family:system-ui;background:#14121a;color:#e8e0ef;display:grid;place-items:center;height:100vh;margin:0\">
<div style=\"text-align:center\">
<div style=\"font-size:44px\">&#10007;</div>
<h2 style=\"margin:.4em 0\">No authorization code</h2>
<p style=\"opacity:.7\">The bank did not send one. Check the terminal.</p>
</div>";

/// Blocks until the bank redirects here, then returns the `code`.
///
/// `timeout_secs` bounds the wait so a closed browser tab does not hang the
/// setup forever.
pub fn wait_for_code(port: u16, timeout_secs: u64) -> Result<String> {
    let listener = TcpListener::bind(("127.0.0.1", port))
        .with_context(|| format!("binding 127.0.0.1:{port} for the redirect"))?;
    listener
        .set_nonblocking(false)
        .context("configuring the listener")?;

    let deadline = std::time::Instant::now() + Duration::from_secs(timeout_secs);

    for stream in listener.incoming() {
        if std::time::Instant::now() > deadline {
            return Err(anyhow!("timed out waiting for the bank redirect"));
        }
        let mut stream = match stream {
            Ok(s) => s,
            Err(_) => continue,
        };
        let mut reader = BufReader::new(&stream);
        let mut request_line = String::new();
        if reader.read_line(&mut request_line).is_err() {
            continue;
        }

        // "GET /callback?code=abc&state=xyz HTTP/1.1"
        let target = request_line.split_whitespace().nth(1).unwrap_or("");
        let code = target
            .split_once('?')
            .map(|(_, q)| q)
            .and_then(|q| {
                q.split('&').find_map(|kv| {
                    let (k, v) = kv.split_once('=')?;
                    (k == "code").then(|| percent_decode(v))
                })
            });

        let body = if code.is_some() { PAGE_OK } else { PAGE_ERR };
        let _ = write!(
            stream,
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body
        );
        let _ = stream.flush();

        if let Some(c) = code {
            return Ok(c);
        }
        // Browsers also ask for /favicon.ico; ignore and keep waiting for the
        // request that actually carries the code.
    }
    Err(anyhow!("listener closed before a code arrived"))
}

/// Minimal %-decoding — enough for an authorization code, which is URL-safe
/// base64 in practice but can still arrive percent-encoded.
fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'%' if i + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).unwrap_or("");
                match u8::from_str_radix(hex, 16) {
                    Ok(b) => {
                        out.push(b);
                        i += 3;
                    }
                    Err(_) => {
                        out.push(bytes[i]);
                        i += 1;
                    }
                }
            }
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            b => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Port out of a redirect URL, defaulting to 80/443 by scheme.
pub fn port_of(url: &str) -> u16 {
    let after_scheme = url.split("://").nth(1).unwrap_or(url);
    let hostport = after_scheme.split('/').next().unwrap_or("");
    hostport
        .rsplit_once(':')
        .and_then(|(_, p)| p.parse().ok())
        .unwrap_or(if url.starts_with("https") { 443 } else { 80 })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_percent_escapes() {
        assert_eq!(percent_decode("TEST%2DCODE%5F123"), "TEST-CODE_123");
        assert_eq!(percent_decode("plain"), "plain");
        // A trailing stray % must not panic or eat the string.
        assert_eq!(percent_decode("abc%"), "abc%");
    }

    #[test]
    fn reads_port_from_redirect() {
        assert_eq!(port_of("http://localhost:8899/callback"), 8899);
        assert_eq!(port_of("https://example.com/cb"), 443);
        assert_eq!(port_of("http://example.com/cb"), 80);
    }

    /// The real thing: bind, have a client hit it like a bank would, and check
    /// the code comes back. Port 0 lets the OS pick, so the test cannot collide
    /// with a developer's running instance.
    #[test]
    fn catches_the_code_from_a_redirect() {
        let probe = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);

        let handle = std::thread::spawn(move || wait_for_code(port, 10));

        // Give the listener a moment to bind, then send what a bank sends.
        std::thread::sleep(Duration::from_millis(200));
        use std::io::Write as _;
        let mut s = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(
            s,
            "GET /callback?code=abc%2D123&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n"
        )
        .unwrap();
        s.flush().unwrap();

        let got = handle.join().unwrap().unwrap();
        assert_eq!(got, "abc-123");
    }

    /// A favicon request must not be mistaken for the redirect.
    #[test]
    fn ignores_requests_without_a_code() {
        let probe = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);

        let handle = std::thread::spawn(move || wait_for_code(port, 10));
        std::thread::sleep(Duration::from_millis(200));

        use std::io::Write as _;
        // Browsers really do this before the redirect lands.
        let mut a = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(a, "GET /favicon.ico HTTP/1.1\r\nHost: localhost\r\n\r\n").unwrap();
        a.flush().unwrap();
        drop(a);

        std::thread::sleep(Duration::from_millis(100));
        let mut b = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(b, "GET /callback?code=real HTTP/1.1\r\nHost: localhost\r\n\r\n").unwrap();
        b.flush().unwrap();

        assert_eq!(handle.join().unwrap().unwrap(), "real");
    }
}
