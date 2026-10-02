# Decision Lens — Hosting, Domain, Security, and Cost Plan

**Document status:** Agreed direction with implementation details; hosting target revised to Kamal 2 on DigitalOcean

**Date:** September 30, 2026 (hosting revised October 1, 2026)

**Related document:** `decision-lens-requirements.md`

## 1. Executive decision

Decision Lens will be a small Ruby on Rails portfolio application deployed with **Kamal 2** to one always-running **DigitalOcean Droplet** (Ubuntu LTS, 1 GB RAM). It will use one reusable personal-brand `.com` domain, with the app published on a subdomain such as `lens.example.com`.

Live AI usage will be protected by a shared demo login, per-IP rate limiting, strict input limits, and an AI-provider spending cap. The application will not contain individual user accounts or a database in its MVP.

An earlier draft targeted a managed platform-as-a-service. Hosting moved to Kamal and DigitalOcean; the application's security behavior and architecture are unchanged. The step-by-step guide is `kamal-digitalocean-deployment.md`.

## 2. Selected architecture

| Area | Decision |
|---|---|
| Application | Minimal Ruby on Rails 8.1 application |
| Rendering | Server-rendered ERB |
| Styling | Pico CSS plus a small custom stylesheet |
| JavaScript | None or minimal vanilla JavaScript only |
| Data storage | No database for the MVP |
| AI integration | One provider adapter behind a Rails service object |
| Access control | One shared username/password and Rails session cookie |
| Hosting | One DigitalOcean Droplet (Ubuntu LTS, 1 GB RAM, 1 vCPU, 25 GB SSD) |
| Deployment tool | Kamal 2 (`bin/kamal`), run from the developer's machine |
| Container registry | GitHub Container Registry (`ghcr.io`), private image |
| Scaling | Exactly one always-running container |
| Domain | Reusable personal-brand `.com` |
| Public URL | `lens.<chosen-domain>.com` |
| DNS registrar/provider | Cloudflare Registrar preferred (DNS-only records) |
| HTTPS | Automatic Let's Encrypt certificate from kamal-proxy |

## 3. Hosting configuration

### DigitalOcean Droplet

- Plan: Basic, Regular (shared CPU), 1 GB RAM, 1 vCPU, 25 GB SSD, approximately **$6 per month**. Recheck pricing before creating it.
- Image: the newest Ubuntu LTS DigitalOcean offers. Region: nearest the audience (New York for a primarily US hiring audience).
- Access: SSH keys only. Cloud Firewall allowing TCP 22 (ideally from your own IP), 80, and 443.
- A 1 GB swap file as a safety margin; no paid Backups (the server holds no state).
- A powered-off Droplet still bills; destroying it is the only way to stop charges.

### Kamal 2 and kamal-proxy

- One `web` role, one server, no accessories, no volumes, no database, no workers.
- kamal-proxy listens on ports 80 and 443, obtains and renews a Let's Encrypt certificate for the configured hostname, redirects HTTP to HTTPS, health-checks `GET /up`, and swaps containers with no downtime. The app container (Puma on port 3000) is never published to the host.
- The Docker image is built on the developer's machine for amd64, pushed to a private `ghcr.io` image, and pulled by the server using a narrowly scoped GitHub token.
- Deployment is a manual `bin/kamal deploy` from the developer's machine. Automatic deployment from CI is a possible later addition.

### Rails runtime limits

- One Puma process (no forked workers) with two threads.
- No background worker process, no database process, no Node-based asset build.
- Memory: the application measures roughly 60 to 90 MB resident locally. The Droplet shares its 1 GB with Docker and kamal-proxy; measure after deployment and keep the app comfortably small. If the server proves too tight, move to the next Droplet size rather than weakening reliability.

## 4. Domain strategy

### Recommended purchase

Purchase one broadly reusable personal-brand `.com` domain. Do not purchase a name tied only to Decision Lens or described as a temporary demo.

The chosen domain should be:

- Short and easy to spell aloud.
- Suitable for a résumé and professional email signature.
- Broad enough to host multiple projects.
- Free of hyphens and unusual spelling when possible.
- Purchased based on renewal cost, not only a first-year promotion.

Example structure:

```text
example.com             future portfolio or redirect
lens.example.com        Decision Lens
another.example.com     future project
```

One registered domain can support any number of project subdomains without additional registration charges.

### Registrar and DNS

**Preferred option: Cloudflare Registrar**

- Registration and renewal at the registry's wholesale price.
- Free authoritative DNS hosting.
- Free WHOIS contact redaction where supported.
- Free DNSSEC.
- No intentionally inflated renewal price.

**Low-price alternative: Spaceship**

- `.com` pricing checked at approximately $8.88 for the first year and $9.98 for renewal, plus the applicable ICANN fee.
- Free eligible-domain privacy.
- Acceptable if its exact checkout and renewal price is lower for the chosen name.

Avoid selecting a promotional extension solely because its first year costs less than a dollar. Renewal prices for promotional extensions can be much higher than `.com` pricing.

### DNS connection to the Droplet

The recommended public hostname is a subdomain pointing at the Droplet's IPv4 address:

```text
Type:   A
Name:   lens
Target: <Droplet public IPv4 address>
TTL:    300
```

If the DNS provider can proxy traffic (Cloudflare), keep the record **DNS only** so Let's Encrypt can reach kamal-proxy directly.

Implementation sequence:

1. Register the domain.
2. Create the Droplet and note its IP address.
3. Create the `lens` A record and confirm it resolves to the Droplet.
4. Put the hostname in `config/deploy.yml` (`proxy.host` and `APP_HOSTS`).
5. Run `bin/kamal setup`; kamal-proxy obtains the certificate once DNS resolves.
6. Confirm HTTPS works and HTTP redirects to it.
7. Rails forces HTTPS in production and trusts the proxy's forwarded protocol and client address.
8. Verify sign-in, sign-out, form submission, and health checks through the custom hostname.

The exact commands and smoke tests are in `kamal-digitalocean-deployment.md`.

## 5. Shared demo access

The app will use a custom Rails login screen with one shared credential pair. This is access control for a portfolio demo, not a complete identity system.

### Included

- Shared username and password supplied to the container as Kamal secrets.
- Rails signed and encrypted session cookie.
- Session reset after successful sign-in.
- Secure, HTTP-only, same-site cookie settings in production.
- Generic error message for invalid credentials.
- Logout action that clears the session.
- Authentication required for the main page and analysis endpoint.
- Unauthenticated access permitted only to login and `/up`.

### Excluded

- Users table.
- Registration.
- Password resets.
- Email verification.
- Social login.
- Roles or permissions.
- Persistent sessions stored in a database.

The credential may be included discreetly beside the project link in an application or résumé. It should not be embedded directly in public page source or committed to the repository.

## 6. AI usage protection

The shared password reduces casual public use but must not be the only financial control because credentials can be forwarded or discovered.

Use all of the following protections:

- Maximum input length of 2,000 characters.
- Exactly one AI request for each accepted analysis.
- No conversation history, agent loop, retrieval, or tool calls.
- Per-IP allowance of approximately 5–10 analyses per hour.
- Modest limit on failed sign-in attempts.
- Provider request timeout.
- Provider-side monthly spending limit or the strongest available billing alert.
- Three sample results cached or precomputed where practical.
- No automatic retries for errors that could multiply paid calls; use only carefully bounded retries when justified.
- Never log submitted text, credentials, or API keys.

If the monthly AI allowance is exhausted, show a graceful message and keep the precomputed examples available so the portfolio page still demonstrates the intended experience.

## 7. Secrets and configuration

Production secrets, supplied to Kamal from the deployer's environment (never from a committed file):

| Secret | Purpose |
|---|---|
| `KAMAL_REGISTRY_PASSWORD` | GitHub token used to push and pull the private image |
| `SECRET_KEY_BASE` | Sign and encrypt Rails session cookies |
| `DEMO_USERNAME` | Shared portfolio-demo username |
| `DEMO_PASSWORD` | Shared portfolio-demo credential |
| `TYPESAFE_API_KEY` | Authenticate the AI request |

`RAILS_MASTER_KEY` is not used (the app has no credentials file).

Non-secret configuration (the model name, provider endpoint, request timeout, rate limits, thread count, and the allowed hostname) lives in `config/deploy.yml`.

Secrets must exist only in the deployer's local untracked environment (or `.kamal/secrets`, which is git-ignored) and, at runtime, in the container environment. The repository contains `.env.example` and `.kamal/secrets.example` with placeholder names but no real values.

## 8. Cost estimate

### Recurring fixed costs

| Item | Monthly equivalent | Annual estimate |
|---|---:|---:|
| DigitalOcean Droplet (1 GB) | $6.00 | $72.00 |
| `.com` registration | ~$0.83–$1.00 | ~$10–$12 |
| DNS hosting | $0 | $0 |
| WHOIS privacy | $0 | $0 |
| TLS certificate (Let's Encrypt) | $0 | $0 |
| Container registry (private image) | $0 | $0 |
| Database | $0 | $0 |
| **Fixed subtotal** | **~$6.83–$7.00** | **~$82–$84** |

### Variable cost

Target AI usage: **$0–$3 per month**, protected by the controls in this document.

Expected combined budget: approximately **$6.83–$10 per month**, or **$82–$120 per year**, depending on live AI usage and excluding taxes.

All prices are planning estimates, not contractual quotes. Recheck DigitalOcean, the registrar, and AI-provider prices immediately before purchase or deployment.

## 9. Deployment checklist

Steps marked live create or change something outside the repository; see `kamal-digitalocean-deployment.md`.

- [ ] Select and register the reusable domain.
- [ ] Enable registrar account two-factor authentication.
- [ ] Enable registrar lock, auto-renewal, WHOIS privacy, and DNSSEC.
- [ ] Create a DigitalOcean account, add a payment method, and set a billing alert.
- [ ] Create an SSH key pair for server access.
- [ ] Create the 1 GB Ubuntu LTS Droplet with SSH-key authentication.
- [ ] Attach a Cloud Firewall allowing only TCP 22, 80, and 443; add a swap file.
- [ ] Create a GitHub classic token with only `write:packages`, and export the five Kamal secrets locally.
- [ ] Create the `A` record for `lens.<chosen-domain>.com` (DNS only) and confirm it resolves.
- [x] Set the server IP and hostname in `config/deploy.yml` (`164.90.142.242`, `lens.juanmoredemo.com`).
- [ ] Run `bin/kamal setup`.
- [ ] Confirm the private `ghcr.io` package, the health check on `/up`, and automatic TLS.
- [ ] Verify production HTTPS, secure cookies, host authorization, and the client-IP / rate-limit test.
- [ ] Confirm unauthenticated users cannot invoke the AI service.
- [ ] Test the provider-failure experience.
- [ ] Set the AI-provider spending cap or billing alert.
- [ ] Add the live URL and shared credential instructions to the résumé/portfolio presentation.
- [ ] Recheck memory usage and the first-load experience from a private browser session.

## 10. Decisions still needed

1. The exact personal-brand domain name.
2. Cloudflare Registrar or Spaceship after checking availability and final renewal cost.
3. The monthly TypeSafe spending cap, and the concrete Jev model version once the API reports one that it accepts.
4. Whether to publish the shared credentials openly or provide them only with job applications.
5. The Droplet region and which SSH key and registry token to use.

## 11. Reference links

- [Kamal](https://kamal-deploy.org/)
- [kamal-proxy](https://github.com/basecamp/kamal-proxy)
- [DigitalOcean Droplet pricing](https://www.digitalocean.com/pricing/droplets)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Cloudflare Registrar](https://www.cloudflare.com/domains/)
- [Spaceship domain pricing](https://www.spaceship.com/domains/)

