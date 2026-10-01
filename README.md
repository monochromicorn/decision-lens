# Decision Lens

Decision Lens turns a short piece of text into three structured judgments instead of an open-ended chat reply:

| Card | Answers | Values |
|---|---|---|
| **Category** | What kind of message is this? | `support`, `sales`, `billing`, `feedback`, `security`, `other` |
| **Urgency** | How soon does it need attention? | `low`, `medium`, `high` |
| **Recommended action** | What should happen next? | `automate`, `review`, `escalate` |

Each decision carries a confidence score (shown as a badge plus a gauge), and a one-to-two sentence summary explains the overall recommendation. It is a portfolio demo: a small, server-rendered Ruby on Rails 8.1 app with no database, no JavaScript framework, and no stored visitor data, designed to run on one small (1 GB) server.

> **Status: Jev integration implemented locally.** The app runs against TypeSafe's Jev model or an offline fake provider. Deployment and the custom domain are not done yet (see [Roadmap](#roadmap-and-open-decisions)). The live demo URL will be added here after deployment.

## How it works

1. A visitor signs in with the shared demo username and password.
2. They pick one of three samples or write 10–2,000 characters, then press **Analyze decision**.
3. The server validates the text and makes at most one AI request (one HTTP call to TypeSafe).
4. The answer is validated and normalized into a stable result. The three cards, a summary that Ruby writes from those answers, and an expandable JSON view are rendered from it.

Built-in samples are **precomputed**: submitting sample text returns a stored result with no AI call and no quota use, so demos always work and cost nothing.

## Quick start

Requirements: Ruby 4.0.7 (see `.ruby-version`), Bundler. No database, Node, or Redis.

```bash
bundle install
cp .env.example .env     # then edit DEMO_USERNAME / DEMO_PASSWORD and, for offline work, set AI_PROVIDER=fake
bin/rails server
```

Open <http://localhost:3000> and sign in with the credentials from `.env`. `AI_PROVIDER=fake` needs no API key or network access (it is also the default in development and test when `AI_PROVIDER` is unset). `.env.example` selects `typesafe`, which needs `TYPESAFE_API_KEY`. See [Using Jev](#using-jev-typesafe-ai) to switch to the real model.

```bash
bundle exec rspec       # full suite, no network
```

## Configuration

All configuration is environment variables (`.env` locally via `dotenv-rails`, hosting secrets in production). `.env` is git-ignored; `.env.example` lists every variable with placeholders.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DEMO_USERNAME`, `DEMO_PASSWORD` | yes | none | Shared demo login. If either is blank, sign-in always fails (fails closed). |
| `SECRET_KEY_BASE` | production | none | Signs/encrypts the session cookie. Generate with `bin/rails secret`. No credentials file or master key is used. |
| `AI_PROVIDER` | production | `fake` in dev/test, **none** in production | `typesafe` (Jev) or `fake`. With none or an unknown value in production, analysis shows a friendly "unavailable" message while samples keep working. |
| `TYPESAFE_API_KEY` | when `typesafe` | none | TypeSafe API key, sent only as `Authorization: Bearer`. Server-side only; never logged. |
| `TYPESAFE_MODEL` | when `typesafe` | none (`jev-latest` in `.env.example`) | Model name from `GET /v1/models`. See [model choice](#model-choice-alias-vs-pinned-version). |
| `TYPESAFE_BASE_URL` | no | `https://api.typesafe.ai` | Must be `https` (plain `http` is allowed only for loopback, for tests). |
| `AI_TIMEOUT_SECONDS` | no | `10` | Per-phase (connect, write, read) timeout for the Jev request. |
| `ANALYSES_PER_HOUR` | no | `8` | Live analyses per client IP per hour. |
| `FAILED_LOGINS_PER_15_MINUTES` | no | `10` | Failed sign-ins per client IP per 15 minutes. |
| `APP_HOSTS` | production | unset | Comma-separated **exact** hostnames served in production (no wildcards). Unset or invalid refuses everything except `/up`. See [docs/kamal-digitalocean-deployment.md](docs/kamal-digitalocean-deployment.md). |
| `RAILS_MAX_THREADS` | no | `2` | Puma threads (single process, 0 forked workers). |
| `PORT` | production | `3000` | Port Puma listens on (all IPv4 interfaces). |

## Architecture

```
config/routes.rb                        GET / · POST /analyze · GET|POST /login · DELETE /logout · GET /up
app/controllers/concerns/demo_authentication.rb   shared-credential gate (before_action)
app/controllers/sessions_controller.rb  sign-in / sign-out, failed-login throttle
app/controllers/decisions_controller.rb form + analysis, per-IP analysis throttle, error mapping
app/models/decision_input.rb            ActiveModel validation (10–2,000 chars after trim); nothing persisted
app/services/decision_analyzer.rb       the only entry point for analysis; validates input and provider output
app/services/decision_summary.rb        deterministic summary built in Ruby from the three answers
app/services/providers/typesafe.rb      Jev adapter: one POST /v1/systemone, no retries
app/services/providers/fake.rb          deterministic keyword-based provider (dev/test)
app/services/sample_inputs.rb           three samples with precomputed results
app/services/rate_limiter.rb            in-process fixed-window counter
app/services/app_settings.rb            ENV access and limits
app/views/{sessions,decisions}/         server-rendered ERB
app/assets/                             vendored Pico CSS 2.1.1, a small custom stylesheet, ~50 lines of vanilla JS
Dockerfile, config/deploy.yml, .kamal/  container image and Kamal 2 deployment configuration
```

Rails is loaded without Active Record, Active Job, Action Mailer, Active Storage, Action Cable, or Action Text. The only runtime gems beyond Rails are `puma` and `propshaft`; there is no Node build step.

### The decision schema

`DecisionAnalyzer` always returns this shape, whatever the provider sent:

```ruby
{
  category: { value: "billing",  confidence: 0.91, probabilities: { "support" => 0.03, "billing" => 0.91, ... } },
  urgency:  { value: "high",     confidence: 0.84, probabilities: { "low" => 0.04, "medium" => 0.12, "high" => 0.84 } },
  action:   { value: "escalate", confidence: 0.88, probabilities: { "automate" => 0.02, "review" => 0.10, "escalate" => 0.88 } },
  summary:  "This appears to be a high-urgency billing item. The recommended action is escalation.",
  provider: "typesafe",
  model:    "<model reported by the API>",
  usage:    { input_tokens: 120 }          # only when the provider supplies it
}
```

Vocabulary (constants at the top of `decision_analyzer.rb`; the category list is provisional):

| Decision | Values |
|---|---|
| Category | `support`, `sales`, `billing`, `feedback`, `security`, `other` |
| Urgency (least to most urgent) | `low`, `medium`, `high` |
| Recommended action | `automate`, `review`, `escalate` |

Validation is strict: values must be in the vocabulary, every decision needs numeric `confidence` and a `probabilities` map covering exactly its options, every number must be within 0–1, and probabilities must sum to about 1 (±0.05). Anything else raises `DecisionAnalyzer::InvalidResponse`, which visitors see as a generic retry message. (Earlier phases clamped out-of-range confidence; it is now treated as a provider error.) Confidence below 0.6 is flagged in the UI with text and an icon ("Low confidence. Treat as a suggestion."), and the summary heading becomes "Tentative recommendation" when any decision is low-confidence.

### The deterministic summary

Jev only produces structured decisions. `DecisionSummary` writes the sentence in Ruby from the three normalized values, so it is the same every time and cannot disagree with the cards. No second model call is made, and any prose a provider might return is ignored.

### The provider boundary

A provider is any object with `complete(text, timeout:)` that returns the decisions (Hash or JSON string) in the provider contract described in `decision_analyzer.rb`, and raises `DecisionAnalyzer` error classes (`TimeoutError`, `RateLimited`, `AuthenticationFailed`, `ProviderError`) on transport failures. `PROVIDERS` maps `AI_PROVIDER` names to classes. Controllers and views only ever see the normalized result and never a provider response object. The controller maps analyzer errors to friendly messages and never renders exception text or upstream bodies.

## Using Jev (TypeSafe AI)

[TypeSafe's Jev](https://docs.typesafe.ai) is a "System One" model: it answers typed questions about some content with probabilities and a confidence value instead of generating text. That matches Decision Lens, which wants three bounded judgments, a calibrated confidence for each (so the UI can flag uncertain answers), a tiny input-priced cost, and predictable output that can be validated.

### One request, three questions

`Providers::Typesafe` sends a single `POST https://api.typesafe.ai/v1/systemone` (see the [OpenAPI schema](https://api.typesafe.ai/openapi.json)) with the visitor's trimmed text as `state` and these named questions, each option or level carrying a specific description:

| Name | Type | Options |
|---|---|---|
| `category` | Choice | the six categories above |
| `urgency` | Score | three ordered levels: 0 = nothing time-sensitive, 1 = needs handling within a day or two, 2 = needs attention today |
| `action` | Choice | `automate`, `review`, `escalate` |

For Score the adapter takes the most probable level (argmax of `probabilities`), not the rounded weighted `score`, and uses Jev's own `confidence`. Requests have no retries (`max_retries = 0`), a strict timeout, and exactly one HTTP call per accepted analysis. Invalid input, samples, throttled clients, and unauthenticated requests make no call at all. Descriptions live in `app/services/providers/typesafe.rb`; tune them there.

### Local setup

```bash
cp .env.example .env
# edit .env: set AI_PROVIDER=typesafe, TYPESAFE_API_KEY=<your key>, TYPESAFE_MODEL=<model>
bin/rails typesafe:models     # optional: lists model names your account can use (one live GET request)
bin/rails server
```

`.env` is git-ignored. Never put the key in `.env.example`, source, or chat. To go back to offline mode set `AI_PROVIDER=fake` (the default in development and test); the fake provider needs no key and returns deterministic results from keyword rules.

### Model choice: alias vs pinned version

`jev-latest` is a moving alias: you get model improvements automatically, but answers and confidence calibration can shift without a code change, which could invalidate the 0.6 low-confidence threshold or the descriptions you tuned. A concrete version (for example `jev-1.13.0`, the form the API reports in responses) is reproducible but may eventually be retired. On 2026-09-30 `bin/rails typesafe:models` listed only two names for the account: `jev-latest` and `jev-preview` (a pre-release channel; not suitable for production). No concrete version is listed, so a versioned name cannot be confirmed as accepted in requests. The result's `model` field records which model actually answered; once a live response reports a concrete version, test whether it is accepted as `TYPESAFE_MODEL` before pinning production to it, and re-check the sample results when upgrading.

### Provider failure behavior

| Situation | Visitor sees |
|---|---|
| Timeout (network, 408, 504) | "The AI provider took too long to respond. Please try again in a moment." |
| 429 rate limit | "The AI provider is busy right now. Please try again shortly." |
| Unreadable or invalid response | "The AI provider returned something we couldn't read. Please try again." |
| 401/403, 400/422, 5xx, connection failure, missing configuration | "Analysis is temporarily unavailable. Please try again later; the built-in samples still work." |

The submitted text is kept in the form. Server logs record only a one-line diagnostic (status, or field paths and error codes for a 422), never visitor text, headers, the key, or response bodies. In production the app refuses to boot with `AI_PROVIDER=typesafe` if `TYPESAFE_API_KEY` or `TYPESAFE_MODEL` is missing.

### Cost

TypeSafe's official website ([typesafe.ai](https://typesafe.ai), "Jev.Cost" section) publishes **$42 per billion input tokens, which is $0.042 per million**. The official [OpenAPI schema](https://api.typesafe.ai/openapi.json) states that output tokens are currently free of charge and that `usage.input_tokens` is the billable count. Each analysis here is a few hundred input tokens, so a call costs a fraction of a cent. Prices and model availability can change, so recheck the TypeSafe site and your account before relying on them. The response's `usage.input_tokens` is kept in the result JSON so cost can be estimated per call.

## Security and privacy

- **Shared login, no accounts.** One username/password from the environment. Comparison is constant time (SHA-256 digests compared with `secure_compare`, both fields always evaluated). Wrong username and wrong password return the same generic message. `reset_session` runs on sign-in (session-fixation protection) and on sign-out.
- **Session cookie.** Rails' signed, encrypted cookie store holds only `authenticated: true`; `HttpOnly`, `SameSite=Lax`, `Secure` in production, 12-hour expiry.
- **Everything is protected except `/login` and `/up`.** Unauthenticated requests are redirected and can never reach the analyzer (tested).
- **The key.** `TYPESAFE_API_KEY` is read only in `AppSettings`, sent only as a Bearer header over HTTPS (the adapter refuses non-HTTPS base URLs except loopback), and never appears in errors or logs (tested).
- **Rate limits** (per `request.remote_ip`, in process memory, reset on restart): failed sign-ins, and live analyses. Invalid input and built-in samples do not consume analysis quota. Failed provider calls do, since they may still be billed.
- **CSRF** protection on all forms. **CSP** is strict (`'self'` only, no inline scripts or styles, no third-party hosts; Pico CSS is vendored). Responses from the app pages are `Cache-Control: no-store`; pages are `noindex`.
- **Logging.** `text`, `message`, `input`, `username`, `password`, `api_key`, and `authorization` are filtered parameters; provider error bodies, request bodies, headers, and the API key are never logged (only the exception class and a short status line). A test asserts visitor text and passwords are absent from logs.
- **No persistence.** Inputs and results exist only for the duration of the request. The note beside the form tells visitors their text is sent to TypeSafe AI (when `AI_PROVIDER=typesafe`) and should not be sensitive; in fake mode it says nothing leaves the server.
- **Production** forces HTTPS: plain-HTTP requests are redirected using the proxy's forwarded protocol header (`assume_ssl` is deliberately off), HSTS is sent, and the session cookie is `Secure`, `HttpOnly`, `SameSite=Lax`. Only hostnames listed in `APP_HOSTS` are served (fail closed). `/up` is exempt from the redirect and host check so health probes succeed. Unhandled errors render the static error page with no details.

## Testing

`bundle exec rspec` runs the suite (RSpec, random order, no network, no real AI calls). To reproduce an order-dependent failure, pass the reported seed: `bundle exec rspec --seed 1234`. Specs live under `spec/`:

- `spec/models`, `spec/services`: input validation, response normalization, the deterministic summary, the fake provider, the TypeSafe adapter (stubbed transport, plus a loopback-only HTTP server), sample inputs, and the rate limiter.
- `spec/requests`: sign-in, sign-out, access control, the analysis flow with both providers, error rendering, rate limiting, and logging.
- `spec/support`: a per-example isolated environment (fixed demo credentials, fake provider, small rate limits, any real TypeSafe settings removed), shared helpers, and a network guard that fails any example reaching the real HTTP transport. Provider doubles are verifying doubles.

They cover:

- input length boundaries and error messages;
- sign-in, wrong credentials, fail-closed when unconfigured, sign-out, session reset, redirects for every protected route, login throttling, cookie flags;
- unauthenticated requests cannot invoke the analyzer or construct a provider;
- response normalization, probabilities and confidence mapping, malformed/incomplete provider output, and each provider error class;
- the TypeSafe adapter: request shape (one POST, three questions, Bearer header), 401/403, 429, 422, 5xx, timeouts, malformed JSON, missing answers, unknown choices, invalid probabilities, no retries, and no outbound request for invalid, sample, throttled, or unauthenticated input;
- friendly, non-leaking error messages; per-IP analysis throttling; samples bypass the provider and quota;
- CSRF enforcement, no-store caching, and log contents.

Specs never use a real TypeSafe key or spend credits. Not automated: a live Jev call (done once by hand), responsive layout and keyboard use were checked by hand in a browser at mobile (375 px) and desktop widths, and the deployed memory footprint, which must be rechecked on the server. The production image was built for `linux/amd64` and run locally under Colima with fake credentials (see the deployment guide).

## Performance and memory

One Puma worker, two threads, no background processes, no database, no Node. Measured locally in `RAILS_ENV=production` (macOS, Ruby 4.0.7): about **56 MB RSS after boot and five analyses, about 79 MB after 200 further requests**. A native rehearsal of the Docker build steps (production gems only, Bootsnap) measured about 88 MB RSS. Linux numbers will differ somewhat, so re-measure after deployment on the 1 GB Droplet, which also runs Docker and kamal-proxy. Rate-limit counters are capped at a 2 MB in-memory store.

## Deployment (Kamal 2 on DigitalOcean; not yet deployed)

The app deploys with [Kamal](https://kamal-deploy.org/) as one container on one DigitalOcean Droplet (Ubuntu LTS, 1 GB RAM, about $6/month), behind kamal-proxy for automatic HTTPS. The private image lives on `ghcr.io`. The complete guide (accounts, Droplet and firewall, registry token, secrets, DNS, `bin/kamal setup`, smoke tests, updates, logs, rollback, and teardown) is [docs/kamal-digitalocean-deployment.md](docs/kamal-digitalocean-deployment.md); commands that touch the outside world are marked **LIVE** there and have not been run.

Files: `Dockerfile` (multi-stage, production gems only, Bootsnap and assets precompiled, non-root user, Puma on port 3000), `.dockerignore` (keeps `.env`, `.git`, `.kamal`, keys, and logs out of the build), `config/deploy.yml` (one `web` server, amd64, `/up` health check, forwarded headers from the trusted proxy), and `.kamal/secrets.example` (variable references only).

- **Placeholders to replace at deploy time:** `REPLACE_ME_DROPLET_IP` and `REPLACE_ME_HOSTNAME` (in two places) in `config/deploy.yml`. They are deliberately invalid until edited.
- **Secrets (names only):** `KAMAL_REGISTRY_PASSWORD`, `SECRET_KEY_BASE`, `DEMO_USERNAME`, `DEMO_PASSWORD`, `TYPESAFE_API_KEY`. They come from your shell or a password manager, never from a committed file.
- **Non-secret production settings** (already in `config/deploy.yml`): `AI_PROVIDER=typesafe`, `TYPESAFE_MODEL=jev-latest`, `TYPESAFE_BASE_URL`, `AI_TIMEOUT_SECONDS`, `ANALYSES_PER_HOUR`, `FAILED_LOGINS_PER_15_MINUTES`, `RAILS_MAX_THREADS`, `PORT=3000`, `RAILS_LOG_LEVEL`, and `APP_HOSTS`.
- No database, Redis, worker, volume, accessory, or release command is needed.
- **Client IP:** the rate limiters key on `request.remote_ip`, which relies on kamal-proxy forwarding the real client address (`forward_headers: true`). The guide's live smoke test (a failed-login burst with forged `X-Forwarded-For` values) must confirm this before real use.
- Rate-limit state is per process and lost on restart, which is acceptable for a single instance. Set a provider-side spending limit or billing alert in TypeSafe.

Local checks: `bundle exec rspec`, `bin/kamal config` (parses the configuration; contacts nothing), and the local image build and run commands in the guide. Kamal builds with `docker buildx`, so the deploy machine needs the Buildx plugin (installation and configuration are in the guide).

## Roadmap and open decisions

Decisions still open (from the requirements and hosting plan): the pinned Jev model version and TypeSafe monthly cap; the final category vocabulary; whether samples stay fully precomputed (current behavior); the domain and registrar; the product subtitle and final palette; whether to publish the shared credentials openly.

Deferred by design: individual accounts, history, saved results, multiple providers in the UI, shareable links, metrics.

## Credits

[Pico CSS](https://picocss.com) 2.1.1 (MIT), vendored at `app/assets/stylesheets/pico.min.css`.
