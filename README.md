# Decision Lens

Decision Lens turns a short piece of text into three structured judgments instead of an open-ended chat reply:

| Card | Answers | Values |
|---|---|---|
| **Category** | What kind of message is this? | `support`, `sales`, `billing`, `feedback`, `security`, `other` |
| **Urgency** | How soon does it need attention? | `low`, `medium`, `high` |
| **Recommended action** | What should happen next? | `automate`, `review`, `escalate` |

Each decision carries a confidence score (shown as a badge plus a gauge), and a one-to-two sentence summary explains the overall recommendation. It is a portfolio demo: a small, server-rendered Ruby on Rails 8.1 app with no database, no JavaScript framework, and no stored visitor data, designed to run inside a 512 MB hosting instance.

> **Status: Phase 1 (local build).** The app is complete and tested locally with a deterministic fake AI provider. A real AI provider, deployment, and the custom domain are Phase 2 (see [Roadmap](#roadmap-and-open-decisions)). The live demo URL will be added here after deployment.

## How it works

1. A visitor signs in with the shared demo username and password.
2. They pick one of three samples or write 10–2,000 characters, then press **Analyze decision**.
3. The server validates the text and makes at most one AI request.
4. The provider's JSON is normalized into a stable result and rendered as three cards, a summary, and an expandable JSON view.

Built-in samples are **precomputed**: submitting sample text returns a stored result with no AI call and no quota use, so demos always work and cost nothing.

## Quick start

Requirements: Ruby 4.0.7 (see `.ruby-version`), Bundler. No database, Node, or Redis.

```bash
bundle install
cp .env.example .env     # then edit DEMO_USERNAME / DEMO_PASSWORD
bin/rails server
```

Open <http://localhost:3000> and sign in with the credentials from `.env`. The default `AI_PROVIDER=fake` needs no API key or network access.

```bash
bin/rails test           # full suite, no network
```

## Configuration

All configuration is environment variables (`.env` locally via `dotenv-rails`, hosting secrets in production). `.env` is git-ignored; `.env.example` lists every variable with placeholders.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DEMO_USERNAME`, `DEMO_PASSWORD` | yes | none | Shared demo login. If either is blank, sign-in always fails (fails closed). |
| `SECRET_KEY_BASE` | production | none | Signs/encrypts the session cookie. Generate with `bin/rails secret`. No credentials file or master key is used. |
| `AI_PROVIDER` | production | `fake` in dev/test, **none** in production | Selects the provider adapter. With no provider in production, analysis shows a friendly "unavailable" message while samples keep working. |
| `AI_TIMEOUT_SECONDS` | no | `10` | Provider request timeout passed to the adapter. |
| `ANALYSES_PER_HOUR` | no | `8` | Live analyses per client IP per hour. |
| `FAILED_LOGINS_PER_15_MINUTES` | no | `10` | Failed sign-ins per client IP per 15 minutes. |
| `APP_HOSTS` | no | unset | Comma-separated allowed `Host` headers in production (`/up` is always exempt). |
| `RAILS_MAX_THREADS` | no | `2` | Puma threads (one worker, no clustering). |

## Architecture

```
config/routes.rb                        GET / · POST /analyze · GET|POST /login · DELETE /logout · GET /up
app/controllers/concerns/demo_authentication.rb   shared-credential gate (before_action)
app/controllers/sessions_controller.rb  sign-in / sign-out, failed-login throttle
app/controllers/decisions_controller.rb form + analysis, per-IP analysis throttle, error mapping
app/models/decision_input.rb            ActiveModel validation (10–2,000 chars after trim); nothing persisted
app/services/decision_analyzer.rb       the only place that talks to a provider; normalizes + validates output
app/services/providers/fake.rb          deterministic keyword-based provider (dev/test)
app/services/sample_inputs.rb           three samples with precomputed results
app/services/rate_limiter.rb            in-process fixed-window counter
app/services/app_settings.rb            ENV access and limits
app/views/{sessions,decisions}/         server-rendered ERB
app/assets/                             vendored Pico CSS 2.1.1, a small custom stylesheet, ~50 lines of vanilla JS
```

Rails is loaded without Active Record, Active Job, Action Mailer, Active Storage, Action Cable, or Action Text. The only runtime gems beyond Rails are `puma` and `propshaft`; there is no Node build step.

### The decision schema

`DecisionAnalyzer` always returns this shape, whatever the provider sent:

```ruby
{
  category: { value: "support",  confidence: 0.91 },   # one of CATEGORIES
  urgency:  { value: "high",     confidence: 0.84 },   # low | medium | high
  action:   { value: "escalate", confidence: 0.88 },   # automate | review | escalate
  summary:  "This appears to be an urgent support issue requiring human attention."
}
```

Normalization rules: values are lower-cased and must be in the allowed vocabulary; confidence must be numeric and is clamped to 0.0–1.0 and rounded to two decimals; the summary is whitespace-collapsed and truncated to 280 characters. Anything else raises `DecisionAnalyzer::InvalidResponse`. Confidence below 0.6 is flagged in the UI with text and an icon ("Low confidence. Treat as a suggestion."), and the summary heading becomes "Tentative recommendation" when any decision is low-confidence.

The vocabulary lives in the constants at the top of `decision_analyzer.rb`; the category list is provisional (see open decisions).

### The provider adapter

A provider is any object with `complete(text, timeout:)` that returns the model's raw JSON (String or Hash) in the schema above and raises one of `DecisionAnalyzer`'s error classes (`TimeoutError`, `RateLimited`, `AuthenticationFailed`, `ProviderError`) on transport failures. To add a real provider:

1. Create `app/services/providers/<name>.rb` implementing `complete`. Send only the submitted text plus a fixed prompt/schema, make exactly one request, set the timeout, and do not retry.
2. Register it in `DecisionAnalyzer::PROVIDERS`.
3. Set `AI_PROVIDER=<name>` and its API key.

Controllers and views never change. The controller maps analyzer errors to friendly messages and never renders exception text or upstream bodies.

## Security and privacy

- **Shared login, no accounts.** One username/password from the environment. Comparison is constant time (SHA-256 digests compared with `secure_compare`, both fields always evaluated). Wrong username and wrong password return the same generic message. `reset_session` runs on sign-in (session-fixation protection) and on sign-out.
- **Session cookie.** Rails' signed, encrypted cookie store holds only `authenticated: true`; `HttpOnly`, `SameSite=Lax`, `Secure` in production, 12-hour expiry.
- **Everything is protected except `/login` and `/up`.** Unauthenticated requests are redirected and can never reach the analyzer (tested).
- **Rate limits** (per `request.remote_ip`, in process memory, reset on restart): failed sign-ins, and live analyses. Invalid input and built-in samples do not consume analysis quota. Failed provider calls do, since they may still be billed.
- **CSRF** protection on all forms. **CSP** is strict (`'self'` only, no inline scripts or styles, no third-party hosts; Pico CSS is vendored). Responses from the app pages are `Cache-Control: no-store`; pages are `noindex`.
- **Logging.** `text`, `username`, and passwords are filtered parameters; provider error bodies are never logged (only the exception class). A test asserts visitor text and passwords are absent from logs.
- **No persistence.** Inputs and results exist only for the duration of the request. The UI tells visitors that text is sent to an external AI provider and should not be sensitive.
- **Production** forces HTTPS (HSTS, secure cookies) and assumes TLS terminates at the platform proxy; `/up` is exempt from the redirect and host check so health probes succeed.

## Testing

`bin/rails test` runs 39 tests (Minitest, no network, no real AI calls). They cover:

- input length boundaries and error messages;
- sign-in, wrong credentials, fail-closed when unconfigured, sign-out, redirects for every protected route, login throttling, cookie flags;
- unauthenticated requests cannot invoke the analyzer;
- response normalization, malformed/incomplete provider output, and each provider error class;
- friendly, non-leaking error messages; per-IP analysis throttling; samples bypass the provider and quota;
- CSRF enforcement, no-store caching, and log contents.

Not automated: responsive layout and keyboard use were checked by hand in a browser at mobile (375 px) and desktop widths, and the deployed memory footprint must be rechecked on Koyeb.

## Performance and the 512 MB constraint

One Puma worker, two threads, no background processes, no database, no Node. Measured locally in `RAILS_ENV=production` (macOS, Ruby 4.0.7): about **56 MB RSS after boot and five analyses, about 79 MB after 200 further requests**. Linux numbers will differ somewhat, so re-measure after deployment; there is ample headroom. Rate-limit counters are capped at a 2 MB in-memory store.

## Deployment notes (Phase 2, not yet done)

See `docs/decision-lens-hosting-domain-plan.md`. Points discovered while building that matter at deploy time:

- Set `SECRET_KEY_BASE`, `DEMO_USERNAME`, `DEMO_PASSWORD`, `AI_PROVIDER`, the provider API key, and optionally `APP_HOSTS` as secrets. `RAILS_MASTER_KEY` is not needed.
- Run `bin/rails assets:precompile` at build time (with `SECRET_KEY_BASE_DUMMY=1`) and start with `bin/rails server -b 0.0.0.0` (honors `PORT`). No Dockerfile is committed yet.
- Health check: HTTP `GET /up`.
- **Client IP:** the rate limiters key on `request.remote_ip`. Behind Koyeb's proxy, confirm the real client IP is what Rails sees (check `X-Forwarded-For` handling and, if needed, configure trusted proxies); otherwise all visitors could share one bucket.
- Rate-limit state is per process and lost on restart or redeploy, which is acceptable for a single instance.

## Roadmap and open decisions

Decisions still open (from the requirements and hosting plan): the real AI provider and its monthly cap; the final category vocabulary; whether samples stay fully precomputed (current behavior); the domain and registrar; the product subtitle and final palette; whether to publish the shared credentials openly.

Deferred by design: individual accounts, history, saved results, multiple providers in the UI, shareable links, metrics.

## Credits

[Pico CSS](https://picocss.com) 2.1.1 (MIT), vendored at `app/assets/stylesheets/pico.min.css`.
