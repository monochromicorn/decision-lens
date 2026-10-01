# Decision Lens: Koyeb Configuration

**Status:** configuration reference for the first deployment (Phase 3B). Nothing here has been deployed yet.
**Related:** `decision-lens-hosting-domain-plan.md`, `README.md`. Values below are placeholders; never commit real ones.

## Service shape

| Setting | Value |
|---|---|
| Region | Washington, D.C. |
| Instance | Eco Micro (0.25 vCPU, 512 MB RAM) |
| Scaling | Exactly one instance (minimum 1, maximum 1). **No scale-to-zero.** |
| Source | Public Git repository, `main` branch |
| Database / Redis / worker / persistent disk | **None.** Do not add any. |
| Processes | One web process: Puma in single-process mode (0 forked workers), 2 threads |

The app is verified database-free (Active Record is not loaded, there is no `database.yml`, no adapter gem, no migrations, no job queue). There is **no release/migration command** to configure.

## Secrets (Koyeb Secrets)

| Name | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Signs and encrypts the session cookie. 128 hex characters. |
| `DEMO_USERNAME` | Shared demo username. |
| `DEMO_PASSWORD` | Shared demo password. |
| `TYPESAFE_API_KEY` | TypeSafe API key (sent only as a Bearer token). |

`RAILS_MASTER_KEY` is **not** needed (the app has no credentials file).

Generate `SECRET_KEY_BASE` without displaying it (macOS; it goes straight to the clipboard):

```bash
bin/rails secret | pbcopy
```

Paste it into the Koyeb secret, then overwrite your clipboard. Do not save it in a file or `.env` that could be committed. Rotating it signs everyone out, which is fine for this app.

## Required non-secret environment variables

| Name | Value | Notes |
|---|---|---|
| `RAILS_ENV` | `production` | Set explicitly; do not rely on the builder. |
| `AI_PROVIDER` | `typesafe` | |
| `TYPESAFE_MODEL` | `jev-latest` | The only stable alias the account lists (`jev-preview` is a pre-release channel). Record the concrete version from `result[:model]`; do not pin an unlisted name. |
| `PORT` | e.g. `8000` | Must equal the port exposed in Koyeb (see below). Puma binds `0.0.0.0:$PORT`. |
| `APP_HOSTS` | see "Hostnames" | **Added after Koyeb assigns the generated hostname.** |

## Optional variables

| Name | Default | Notes |
|---|---|---|
| `TYPESAFE_BASE_URL` | `https://api.typesafe.ai` | Must be `https`. |
| `AI_TIMEOUT_SECONDS` | `10` | Per-phase timeout for the single Jev request. |
| `RAILS_MAX_THREADS` | `2` | Puma threads. Use 2 or 3; more threads cost memory on a 512 MB instance. |
| `ANALYSES_PER_HOUR` | `8` | Live analyses per client IP per hour. |
| `FAILED_LOGINS_PER_15_MINUTES` | `10` | Failed sign-ins per client IP. |
| `RAILS_LOG_LEVEL` | `info` | Logs go to standard output. |

`WEB_CONCURRENCY` is intentionally ignored: `config/puma.rb` pins `workers 0` so a platform default cannot multiply memory use. `RAILS_SERVE_STATIC_FILES` is unnecessary: static files are served by default and were verified in a production boot.

## Hostnames (`APP_HOSTS`)

`APP_HOSTS` is a comma-separated list of **exact** hostnames. Example (placeholders):

```text
APP_HOSTS=your-service-your-org.koyeb.app,lens.yourdomain.example
```

Rules (enforced by `lib/allowed_hosts.rb`, covered by specs):

- Whitespace around entries is trimmed; case is ignored; duplicates are removed.
- **Rejected:** wildcards (`*`, `*.example.com`, `.*`), leading dots, URLs or schemes, ports, paths, IP addresses, underscores, trailing dots, empty entries. Rejected entries are ignored and the boot log says how many (never which).
- Requests whose `Host` (or `X-Forwarded-Host`) is not listed get `403`.
- **Fail closed:** if the variable is unset, empty, or contains no valid hostname, every request except `/up` is refused. The app still boots and passes its health check, so a first deploy works.
- `/up` is exempt from host checks and from the HTTPS redirect, so the platform health probe works under any Host header.

### Sequence

1. First deploy **without** `APP_HOSTS`. The service starts, `/up` is healthy, everything else returns 403, and the log warns that `APP_HOSTS` is empty.
2. Copy the generated Koyeb hostname from the service page (not stored in this repository).
3. Set `APP_HOSTS` to that hostname and redeploy. Verify sign-in over `https://`.
4. **Later stage (domain not purchased yet):** after attaching the custom domain, change `APP_HOSTS` to `generated-hostname,lens.<chosen-domain>.com` (both) and redeploy. Keep the generated hostname for diagnostics.

## Process, port, and health check

- **Run command:** `bin/rails server -b 0.0.0.0` (the form Koyeb's Rails example uses). `config/puma.rb` binds `tcp://0.0.0.0:$PORT` and reads `RAILS_MAX_THREADS`. Shutdown is graceful on `SIGTERM` (verified: Puma stops accepting, drains, exits).
- **Port:** choose one port (for example `8000`), expose it as protocol **HTTP** in Koyeb, and set `PORT` to the same number. Koyeb's documentation shows `PORT` being set explicitly; if the two differ the health check fails. If `PORT` is unset the app listens on 3000.
- **Health check:** HTTP `GET /up` on that port; success is any 2xx/3xx. Use a grace period of 15–30 seconds (Koyeb's minimum is 5 s; Rails needs a few seconds to boot).
- **Build:** run `SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile` at build time. It needs no database, secrets, or Node (Propshaft is pure Ruby), and the AI-configuration boot check is skipped for that run. Whether the Koyeb builder does this automatically (buildpack) or needs a Dockerfile is a Phase 3B decision; no `Dockerfile` or `Procfile` is committed yet.
- **Logs:** standard output only. Visitor text, passwords, and API keys are filtered or never logged.

## HTTPS and proxy behavior

- `force_ssl` is on. TLS ends at Koyeb; Rails decides whether a request was HTTPS from the forwarded protocol header (`X-Forwarded-Proto`) and **redirects plain HTTP to HTTPS** (301 for GET, 308 for other methods), sets HSTS, and marks cookies `Secure`.
- `assume_ssl` is deliberately **off**. Turning it on would treat plain-HTTP requests as secure and skip the redirect, letting a visitor submit the shared password over HTTP.
- Koyeb documents that it does not redirect HTTP to HTTPS itself, so the app must. Koyeb's documentation lists `x-forwarded-for` and `x-forwarded-host` but **does not mention `x-forwarded-proto`**. This is the main open item for the first deploy (see checklist). If the header is not sent, the symptom is a redirect loop, which fails safe.
- Session cookie: `Secure`, `HttpOnly`, `SameSite=Lax`, 12-hour expiry. The browser JavaScript never sees the credentials or the session.
- **Client IP:** rate limits use Rails' `request.remote_ip` with default trusted proxies (loopback and private ranges only). Koyeb appends the connecting IP to the end of `X-Forwarded-For` and documents that last entry as the only one it certifies. Rails takes the rightmost entry that is not a trusted proxy, so forged entries to its left are ignored (covered by specs). No extra trusted-proxy ranges are configured, because there is no evidence yet that Koyeb needs them.

## First-deploy verification checklist (Phase 3B)

Replace `HOST` with the generated hostname after step 3 above.

- [ ] `curl -sI http://HOST/up` returns 200 (the health probe works over HTTP).
- [ ] `curl -sI http://HOST/` returns a 301 to `https://HOST/`. **If it loops or never redirects, stop:** Koyeb is not sending `X-Forwarded-Proto`; decide on a fix before exposing sign-in.
- [ ] `curl -sI https://HOST/` returns a 302 to `/login`, with a `strict-transport-security` header.
- [ ] `curl -s -o /dev/null -w '%{http_code}' -H 'Host: other.example' https://HOST/login` is not 200 once `APP_HOSTS` is set (note: with Koyeb routing this may need a direct test; at minimum confirm an unlisted custom domain is refused).
- [ ] Sign in in a private window; the session cookie shows Secure, HttpOnly, SameSite=Lax in dev tools.
- [ ] Per-visitor throttling works: confirm failed-login limits apply per client, not to everyone together (for example, test from two different networks). If all visitors share one bucket, the peer address Rails sees is not trusted as a proxy; investigate before adding any `trusted_proxies`.
- [ ] Memory stays well under 512 MB after a few analyses (local production measurement: about 60–80 MB RSS).
- [ ] One approved live analysis works with `AI_PROVIDER=typesafe`.
- [ ] Koyeb scaling shows min = max = 1 and scale-to-zero is off.
