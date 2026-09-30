# Decision Lens — MVP Requirements

**Document status:** Draft for implementation  
**Date:** September 30, 2026  
**Product type:** Public portfolio demo  
**Primary stack:** Ruby on Rails

## 1. Product summary

Decision Lens is a small, visually polished AI demonstration that turns a short piece of text into a few clear, structured judgments. It is intended to show prospective employers that the developer can build and deploy a thoughtful Rails application with an AI integration—not merely another chat interface.

The application should be quick to understand, inexpensive to operate, responsive on mobile and desktop, and small enough to build and maintain without unnecessary framework or frontend complexity.

## 2. Goals

- Demonstrate practical Ruby on Rails and AI-integration skills.
- Give a visitor a useful result within one short interaction.
- Present AI output as structured decisions rather than an open-ended conversation.
- Protect live AI usage behind one shared portfolio-demo credential.
- Look intentional and professional without a JavaScript framework.
- Keep generated-code volume, model-token usage, hosting cost, and maintenance low.
- Remain immediately available when a prospective employer opens it.

## 3. Non-goals for the MVP

- Individual user accounts, registration, password reset, email verification, or roles.
- Conversation history or a chatbot interface.
- Saving visitor inputs or results.
- A database, background jobs, email, uploads, or an administration panel.
- Multiple AI providers exposed in the interface.
- Retrieval-augmented generation, embeddings, autonomous agents, or tool loops.
- Billing, subscriptions, or production-scale traffic handling.

## 4. Primary user flow

1. A visitor opens the application and sees a branded sign-in page.
2. The visitor enters the shared demo username and password supplied with the portfolio link.
3. After successful sign-in, the visitor reaches the Decision Lens landing page and immediately understands the demo.
4. The visitor selects a sample input or writes up to 2,000 characters.
5. The visitor presses **Analyze decision**.
6. The server validates the input and makes one AI request.
7. The page displays three result cards:
   - **Category** — what kind of request or message this is.
   - **Urgency** — low, medium, or high.
   - **Recommended action** — automate, review, or escalate.
8. Each card displays the answer and confidence visually. A short summary explains the overall recommendation.
9. The visitor can edit the input, run another analysis, or sign out.

## 5. Functional requirements

### 5.1 Shared demo access

- Present a custom, visually consistent sign-in page rather than the browser’s HTTP Basic Authentication dialog.
- Accept one shared username and password configured through server-side environment variables or hosting secrets.
- Do not create a users table or store credentials in source control.
- Compare credentials using a constant-time comparison.
- Reset the session after successful sign-in to prevent session fixation.
- Store only an authenticated flag in Rails’ signed, encrypted session cookie.
- Protect every application page and analysis endpoint except sign-in and the health check.
- Provide a visible sign-out action that clears the session.
- Return the same generic error for an incorrect username or password.
- Apply a modest limit to failed sign-in attempts to discourage automated guessing.
- Do not offer registration, password recovery, or persistent individual accounts.

### 5.2 Input

- Provide one clearly labeled multiline text field.
- Accept between 10 and 2,000 characters after whitespace is trimmed.
- Display a character count.
- Include three sample inputs that populate the field with one action.
- Disable duplicate submissions while a request is in progress when JavaScript is available.
- Continue to work through a normal HTML form submission when JavaScript is unavailable.

### 5.3 Analysis

- Make exactly one external AI request per submission.
- Ask a fixed set of structured questions.
- Require a machine-readable response and normalize it into a stable internal result shape.
- Do not send previous submissions, browser history, or unrelated application context.
- Set a strict request timeout and handle provider errors without exposing credentials or raw internal errors.

Suggested normalized result:

```ruby
{
  category: { value: "support", confidence: 0.91 },
  urgency: { value: "high", confidence: 0.84 },
  action: { value: "escalate", confidence: 0.88 },
  summary: "This appears to be an urgent support issue requiring human attention."
}
```

The initial provider may be Jev or another inexpensive model that supports reliable structured output. Provider-specific request and response handling must be isolated behind one Rails service object so it can be replaced without changing controllers or views.

### 5.4 Results

- Show category, urgency, and recommended action as separate cards.
- Use a badge and confidence bar for each decision.
- Round displayed confidence to a whole percentage.
- Include one concise overall summary, capped at approximately two sentences.
- Provide an expandable section for the normalized JSON result.
- Preserve the submitted text when displaying the result or an error.
- Clearly distinguish low-confidence results from definitive recommendations.

### 5.5 Errors and empty states

- Display inline validation for missing, too-short, or too-long input.
- Show a friendly retry message for timeouts, rate limits, and provider failures.
- Never show an API key, stack trace, upstream response body, or internal exception to a visitor.
- Include a polished initial state before the first analysis.

## 6. Visual and interaction requirements

- Use server-rendered ERB and semantic HTML.
- Use Pico CSS, preferably pinned to a specific version, plus a small custom stylesheet.
- Give the sign-in page the same visual identity and level of polish as the main application.
- Do not introduce React, Vue, Tailwind, a Node build pipeline, or a component framework.
- Give the page a distinctive “decision instrument” feel rather than a generic form appearance.
- Use a restrained palette with clear status colors for low, medium, and high urgency.
- Support common mobile and desktop widths.
- Meet basic accessibility expectations:
  - Associated form labels.
  - Keyboard-operable controls.
  - Visible focus styles.
  - Sufficient color contrast.
  - Status information not conveyed by color alone.
- Avoid excessive animation; a subtle loading state and result entrance are sufficient.

## 7. Rails implementation

### 7.1 Application shape

- Use the current stable Rails 8.1 release and a supported Ruby version.
- Generate a minimal Rails application.
- Omit Active Record for the MVP.
- Use a conventional controller and views rather than a separate frontend application.
- Keep AI communication in a dedicated service, such as `DecisionAnalyzer`.
- Store secrets only in environment variables or the hosting provider’s secret manager.

Expected custom application files:

- `config/routes.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/decisions_controller.rb`
- `app/controllers/concerns/demo_authentication.rb`
- `app/services/decision_analyzer.rb`
- `app/views/sessions/new.html.erb`
- `app/views/decisions/new.html.erb`
- `app/views/decisions/_results.html.erb`
- `app/assets/stylesheets/application.css`
- Focused controller/request and service tests

### 7.2 Suggested routes

```text
GET    /          decisions#new (authentication required)
POST   /analyze   decisions#create (authentication required)
GET    /login     sessions#new
POST   /login     sessions#create
DELETE /logout    sessions#destroy
GET    /up        Rails health check (no authentication)
```

### 7.3 Performance and runtime constraints

- Run one Puma worker with a small thread pool.
- Target operation within a 512 MB memory limit.
- Avoid background processes and persistent local state.
- Keep the initial HTML useful before any external script finishes loading.
- Target a fast server response excluding unavoidable AI-provider latency.

## 8. Security, privacy, and cost controls

- Keep the AI API credential server-side.
- Keep the shared demo username and password server-side in Koyeb Secrets.
- Require HTTPS and use secure, HTTP-only, same-site session cookies in production.
- Use Rails’ CSRF protection for the submission form.
- Never log request bodies containing visitor input.
- Do not persist inputs or results.
- State near the form that submitted text is sent to an external AI provider and should not contain sensitive information.
- Limit input to 2,000 characters before making an external request.
- Apply a modest per-IP rate limit even after authentication, initially targeting 5–10 live analyses per hour.
- Configure a hard monthly spending limit or alert with the AI provider when available.
- Cache or precompute the three built-in sample results where practical so repeated portfolio demonstrations do not require paid inference.
- Add abuse protection only if traffic warrants it; avoid collecting unnecessary personal information.

## 9. Hosting and operations

- Deploy the Rails web service to a **Koyeb Eco Micro** instance.
- Configure fixed scaling at one instance, or minimum one and maximum one.
- Expected compute allocation: 0.25 vCPU, 512 MB RAM, and 4 GB SSD.
- Current estimated maximum compute cost: approximately **$2.68 per full month**, billed by usage. Pricing must be rechecked before deployment.
- Use a custom subdomain such as `lens.example.com` for the public application.
- Register one broadly reusable personal-brand `.com` domain rather than a domain limited to this single demo.
- Use free DNS hosting and WHOIS privacy through the selected registrar; Cloudflare Registrar is the preferred long-term option.
- Retain the generated Koyeb hostname for deployment diagnostics, but use the custom hostname in the portfolio and README.
- Connect the subdomain to Koyeb with the CNAME record supplied by Koyeb.
- Use Koyeb's automatically provisioned TLS certificate for HTTPS.
- Configure an HTTP health check against `/up`.
- Store the Rails master key, AI API key, demo username, and demo password as Koyeb secrets.
- Deploy automatically from the public source repository after the main branch passes tests.
- Provide a clear README with local setup, architecture notes, screenshots, deployment notes, and an explicit explanation of the AI decision schema.

Current hosting references:

- [Koyeb instance types and pricing](https://www.koyeb.com/docs/reference/instances)
- [Koyeb scaling options](https://www.koyeb.com/docs/reference/scaling)
- [Koyeb custom domains](https://www.koyeb.com/docs/run-and-scale/domains)
- [Cloudflare Registrar](https://www.cloudflare.com/domains/)

## 10. Cost targets

| Item | MVP target |
|---|---:|
| Koyeb hosting | Approximately $2.68/month maximum |
| Database | $0; none used |
| Domain registration | Approximately $10–12/year for one `.com` |
| DNS, WHOIS privacy, and TLS | $0 |
| AI API | Target $0–$3/month with strict limits |
| Total | Target under $7/month on average |

## 11. Testing requirements

- Validate the input length boundaries.
- Verify successful and unsuccessful sign-in, access redirects, sign-out, and session reset behavior.
- Verify that unauthenticated requests cannot invoke the AI service.
- Verify successful normalization of a provider response.
- Verify graceful handling of malformed responses, timeouts, authentication failures, and rate limits.
- Stub all external AI calls in the automated test suite.
- Verify that secrets and visitor input are absent from logs.
- Test the main flow at representative mobile and desktop sizes.
- Confirm the deployed application stays within its memory limit.

## 12. MVP acceptance criteria

The MVP is complete when:

- A first-time visitor can understand the application without instructions.
- A visitor with the shared credentials can sign in and sign out.
- An unauthenticated visitor cannot access Decision Lens or invoke a paid AI request.
- All three sample inputs work.
- A visitor can submit custom text and receive the three structured decisions.
- Results include confidence indicators and a concise summary.
- Invalid input and provider failures produce clear, safe messages.
- No input or result is stored after the request.
- The app is responsive, keyboard usable, and visually polished.
- Tests pass without making real AI calls.
- The public deployment is accessible without a prolonged cold start.
- The repository README explains the problem, technical choices, setup, and live demo.

## 13. Possible follow-up features

These are intentionally deferred until the MVP is working:

- Shareable result links with explicit user consent.
- Anonymous aggregate usage metrics.
- Additional decision templates, such as idea triage or message coaching.
- Side-by-side comparison of two model providers.
- Exporting a result as an image.
- Optional accounts and saved analyses.

## 14. Open decisions before implementation

1. Select the initial AI provider based on API access, structured-output reliability, and price.
2. Finalize the category vocabulary for the first public demo.
3. Decide whether built-in examples should be entirely precomputed or call the live provider once per visitor.
4. Choose and register the reusable personal-brand domain.
5. Choose the product subtitle and final visual palette.
