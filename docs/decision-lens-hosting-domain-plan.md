# Decision Lens — Hosting, Domain, Security, and Cost Plan

**Document status:** Agreed direction with implementation details  
**Date:** September 30, 2026  
**Related document:** `decision-lens-requirements.md`

## 1. Executive decision

Decision Lens will be a small Ruby on Rails portfolio application hosted on one always-running Koyeb Eco Micro instance. It will use one reusable personal-brand `.com` domain, with the app published on a subdomain such as `lens.example.com`.

Live AI usage will be protected by a shared demo login, per-IP rate limiting, strict input limits, and an AI-provider spending cap. The application will not contain individual user accounts or a database in its MVP.

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
| Hosting | Koyeb Eco Micro |
| Scaling | Exactly one always-running instance |
| Domain | Reusable personal-brand `.com` |
| Public URL | `lens.<chosen-domain>.com` |
| DNS registrar/provider | Cloudflare Registrar preferred |
| HTTPS | Automatic Koyeb TLS certificate |

## 3. Hosting configuration

### Koyeb service

- Instance type: **Eco Micro**.
- Region: Washington, D.C. is the likely choice for a primarily US hiring audience.
- Resources: 0.25 vCPU, 512 MB RAM, and 4 GB SSD.
- Scaling: fixed at one instance, or autoscaling minimum one and maximum one.
- Expected compute cost: approximately **$2.68 for a complete month** at the pricing checked on September 30, 2026.
- Account plan: Koyeb Starter, with no base subscription fee and a valid payment method.
- Health check: HTTP request to `/up`.
- Deploy source: public Git repository, automatically deployed from the main branch after tests pass.

The paid Eco Micro should not be configured to scale to zero. Keeping one instance allocated avoids the cold-start delay that could cause a prospective employer to leave before seeing the demo.

### Rails runtime limits

- One Puma worker.
- Small thread pool, initially two or three threads.
- No background worker process.
- No database process.
- No Node-based asset build.
- Memory usage should be measured after deployment and remain comfortably below 512 MB.
- If the application cannot operate reliably within 512 MB, move to Koyeb Eco Small at approximately $5.36 per month rather than weakening reliability.

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

### DNS connection to Koyeb

The recommended public hostname is a subdomain because it maps cleanly to Koyeb:

```text
Type:   CNAME
Name:   lens
Target: <value supplied by Koyeb>.cname.koyeb.app
```

Implementation sequence:

1. Register the domain.
2. Add `lens.<chosen-domain>.com` to the Koyeb application.
3. Copy Koyeb's assigned CNAME target.
4. Create the `lens` CNAME record in the DNS provider.
5. Ask Koyeb to validate the domain.
6. Confirm that the TLS certificate becomes active.
7. Configure Rails to force HTTPS in production.
8. Verify sign-in, sign-out, form submission, and health checks through the custom hostname.

Koyeb automatically provisions TLS for validated custom domains. The exact records shown by Koyeb at deployment time take precedence over examples in this document.

## 5. Shared demo access

The app will use a custom Rails login screen with one shared credential pair. This is access control for a portfolio demo, not a complete identity system.

### Included

- Shared username and password stored as Koyeb Secrets.
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

Expected production secrets:

| Secret | Purpose |
|---|---|
| `RAILS_MASTER_KEY` | Decrypt Rails credentials if used |
| `SECRET_KEY_BASE` | Sign/encrypt Rails sessions when required by deployment setup |
| `DEMO_USERNAME` | Shared portfolio-demo username |
| `DEMO_PASSWORD` or password digest | Shared portfolio-demo credential |
| Provider-specific API key | Authenticate the AI request |

Additional non-secret configuration may include the model name, provider endpoint, request timeout, rate limit, and maximum input length.

Secrets must exist only in local untracked environment configuration and Koyeb Secrets. The repository should contain a `.env.example` with placeholder names but no real values.

## 8. Cost estimate

### Recurring fixed costs

| Item | Monthly equivalent | Annual estimate |
|---|---:|---:|
| Koyeb Eco Micro | $2.68 | $32.16 |
| `.com` registration | ~$0.83–$1.00 | ~$10–$12 |
| DNS hosting | $0 | $0 |
| WHOIS privacy | $0 | $0 |
| TLS certificate | $0 | $0 |
| Database | $0 | $0 |
| **Fixed subtotal** | **~$3.51–$3.68** | **~$42–$44** |

### Variable cost

Target AI usage: **$0–$3 per month**, protected by the controls in this document.

Expected combined budget: approximately **$3.50–$6.70 per month**, or **$42–$80 per year**, depending on live AI usage and excluding taxes.

All prices are planning estimates, not contractual quotes. Recheck the registrar, Koyeb, and AI-provider prices immediately before purchase or deployment.

## 9. Deployment checklist

- [ ] Select and register the reusable domain.
- [ ] Enable registrar account two-factor authentication.
- [ ] Enable registrar lock, auto-renewal, WHOIS privacy, and DNSSEC.
- [ ] Create the Koyeb organization on the Starter plan.
- [ ] Add a payment method and a billing alert.
- [ ] Deploy the app to one Eco Micro instance.
- [ ] Confirm the scaling minimum and maximum both equal one.
- [ ] Add all production secrets.
- [ ] Configure `/up` as the HTTP health check.
- [ ] Attach `lens.<chosen-domain>.com` in Koyeb.
- [ ] Add the CNAME record at the DNS provider.
- [ ] Validate automatic TLS.
- [ ] Verify production HTTPS and secure cookies.
- [ ] Confirm unauthenticated users cannot invoke the AI service.
- [ ] Test the rate limit and provider-failure experience.
- [ ] Set the AI-provider spending cap or billing alert.
- [ ] Add the live URL and shared credential instructions to the résumé/portfolio presentation.
- [ ] Recheck memory usage and the first-load experience from a private browser session.

## 10. Decisions still needed

1. The exact personal-brand domain name.
2. Cloudflare Registrar or Spaceship after checking availability and final renewal cost.
3. The initial AI provider and monthly provider cap.
4. Whether to publish the shared credentials openly or provide them only with job applications.

## 11. Reference links

- [Koyeb instance types and pricing](https://www.koyeb.com/docs/reference/instances)
- [Koyeb scaling](https://www.koyeb.com/docs/reference/scaling)
- [Koyeb custom-domain setup](https://www.koyeb.com/docs/run-and-scale/domains)
- [Cloudflare Registrar](https://www.cloudflare.com/domains/)
- [Spaceship domain pricing](https://www.spaceship.com/domains/)

