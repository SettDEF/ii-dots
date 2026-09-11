# finance-sync

Bank balances and transactions for the quickshell left sidebar, via
[Enable Banking](https://enablebanking.com) (PSD2 account information).

Nordigen/GoCardless' free tier closed to new signups in 2025; Enable Banking's
self-serve **Restricted Production** tier is the current way to read your *own*
accounts for free.

## Why a timer instead of live polling

PSD2 caps *unattended* access at roughly **4 calls per account per day**, and
consent expires every **90 days**. So the fetcher runs on a 6-hour timer and the
shell always paints from the cached JSON — the sidebar opens instantly and never
blocks on a bank.

## Setup

**Two steps.**

**1.** Register an application in the Enable Banking control panel — pick
**Restricted Production** (free, your own accounts only). Give it a name and
whitelist `http://localhost:8899/callback` as a redirect URL. Your browser
downloads a `.pem`; leave it in `~/Downloads`.

**2.** Run:

```
./finance-sync setup
```

That finds the downloaded key (its filename *is* your application id), installs
it at `~/.secure/enablebanking.pem` with mode 600, writes both credentials into
`~/.secure/apikeys`, asks which bank, opens your browser, **catches the redirect
itself** so there is no code to copy, links the session, and does the first sync.

Then, to keep it fresh every 6 hours:

```
./install.sh
```

Re-run `setup` every ~90 days when consent expires. The sidebar warns you 14 days
out.

<details>
<summary>Manual equivalent, if setup cannot find something</summary>

```
./finance-sync banks --country DE --filter sparkasse
./finance-sync auth --bank "<exact name>" --country DE
# open the printed URL, approve, copy `code` from the redirect
./finance-sync finish --code <code>
./finance-sync sync
```
</details>

## Preview without a bank

```
./finance-sync demo
```

Writes fixture data in the exact schema a real sync produces, so the UI can be
built and reviewed before anything is linked.

## Security

- **Read-only by construction.** Every call is a GET, or a POST to `/auth` and
  `/sessions` which only establish consent. There is no payment-initiation code
  path and there should never be one.
- The private key is refused if group or other can read it.
- `finance.json` and `finance-session.json` are written **0600** inside a **0700**
  directory, created with those modes rather than chmod-ed afterwards, so there
  is no window where they are world-readable.
- Server error bodies are never logged verbatim — only the machine-readable
  error field — because a failed transactions call can echo account data and
  errors end up in the journal.
- The systemd unit runs with `ProtectHome=read-only`, `ProtectSystem=strict` and
  a single `ReadWritePaths`.

## Files

| path | what |
|---|---|
| `~/.secure/apikeys` | app id + key path |
| `~/.local/state/quickshell/finance.json` | what the shell reads |
| `~/.local/state/quickshell/finance-session.json` | session id, consent expiry |
