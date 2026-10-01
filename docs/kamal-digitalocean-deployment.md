# Decision Lens: Kamal 2 on DigitalOcean

**Status:** preparation is finished and verified locally, including a local build and run of the production image. **Nothing has been deployed.** No Droplet, domain, DNS record, registry login, or token exists yet.
**Related:** `decision-lens-hosting-domain-plan.md`, `README.md`, `config/deploy.yml`, `Dockerfile`.

## How to read this guide

Every section is labeled:

- **[LOCAL: safe now]** touches only your machine and contacts no server, registry, or API.
- **[LIVE]** creates or changes something outside this repository (cloud resources, DNS, a registry, a server). **Do not run these until the live-deployment phase.** Each live command block says so.

## Architecture

```text
browser ──HTTPS──▶ kamal-proxy (ports 80/443, Let's Encrypt) ──HTTP──▶ app container (Puma :3000)
                          Droplet: Ubuntu LTS, 1 GB RAM, Docker
```

- One Droplet, one web container, no database, no Redis, no worker, no volume, no accessory. The app stores nothing; a redeploy or reboot loses nothing.
- Kamal builds the image on your machine, pushes it to a **private** image on GitHub Container Registry (`ghcr.io`), and runs it on the Droplet behind **kamal-proxy**, which provides automatic HTTPS and zero-downtime swaps.
- The app trusts the proxy for the forwarded protocol and client address (`proxy.forward_headers: true`). The live smoke tests below verify this before any real use.

## What you need

| Item | Notes |
|---|---|
| DigitalOcean account | With a payment method. The intended Droplet is **Basic, Regular (shared CPU), 1 GB RAM / 1 vCPU / 25 GB SSD, about $6/month**. Recheck current pricing. |
| GitHub account | Owns the private image. `config/deploy.yml` uses the account name already in the repository's remote. |
| A domain you control | The app is served at a subdomain such as `lens.yourdomain.example`. No domain is purchased yet. |
| SSH key pair | For key-only server access (`ssh-keygen -t ed25519 -C "decision-lens"`). |
| Docker and Buildx on your machine | Kamal builds the image locally with `docker buildx`, so the **Buildx plugin is required**. On macOS: `brew install colima docker docker-buildx`, then configure the plugin as described under "Install Docker and Buildx" below. Colima is a lightweight alternative to Docker Desktop. |
| Ruby and Bundler | Already used by this repository. `bin/kamal` is Kamal 2.12 from the Gemfile (development group only; it is not in the production image). |

## Values to replace (LIVE phase)

`config/deploy.yml` contains these on purpose-invalid placeholders (underscores are not valid in hostnames, so the file cannot serve traffic until edited):

| Placeholder | Where | Replace with |
|---|---|---|
| `REPLACE_ME_DROPLET_IP` | `servers.web` | The Droplet's public IPv4 address. |
| `REPLACE_ME_HOSTNAME` | `proxy.host` **and** `env.clear.APP_HOSTS` | The final hostname, for example `lens.yourdomain.example`. Both must match exactly. |

Also confirm `image` and `registry.username` (`monochromicorn`) are the GitHub account that owns the token. The server IP and hostname are not secrets, but they become public if you commit them to a public repository; that is acceptable here.

## Secrets

Kamal reads five values by **name** from `.kamal/secrets`, a git-ignored file. The tracked `.kamal/secrets.example` contains only variable references (`NAME=$NAME`), never values.

| Variable | Purpose |
|---|---|
| `KAMAL_REGISTRY_PASSWORD` | GitHub token used to push and pull the image. |
| `SECRET_KEY_BASE` | Signs and encrypts the session cookie. |
| `DEMO_USERNAME` | Shared demo username. |
| `DEMO_PASSWORD` | Shared demo password. |
| `TYPESAFE_API_KEY` | TypeSafe API key. |

`RAILS_MASTER_KEY` is not needed (no credentials file).

### Create the registry token **[LIVE: external account change]**

1. GitHub: *Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token (classic)*. Fine-grained tokens do not support GitHub Container Registry.
2. Name it `decision-lens-kamal`, set a short expiry (for example 90 days), and select **only** `write:packages` (read access is included). Do not select `repo` or `delete:packages`; the repository is public.
3. Copy the token once and store it in your password manager. The server keeps a copy in its Docker login after the first deploy, so treat the token as server-resident and revoke it when you tear down.
4. The first push creates the package as **private**. Leave it private.

### Generate a new `SECRET_KEY_BASE` **[LOCAL: safe now]**

Do not reuse any development value. Keep it in your shell only, never printing it:

```bash
export SECRET_KEY_BASE="$(openssl rand -hex 64)"
```

### Populate secrets without printing or committing them **[LOCAL: safe now to prepare; values are used only in the LIVE phase]**

```bash
cp .kamal/secrets.example .kamal/secrets        # references only; the file is git-ignored
chmod 600 .kamal/secrets

# Enter each value silently (nothing is echoed or stored in shell history):
read -rs KAMAL_REGISTRY_PASSWORD; export KAMAL_REGISTRY_PASSWORD
read -rs DEMO_USERNAME;           export DEMO_USERNAME
read -rs DEMO_PASSWORD;           export DEMO_PASSWORD
read -rs TYPESAFE_API_KEY;        export TYPESAFE_API_KEY
# SECRET_KEY_BASE was exported above.
```

Confirm all five are set **without displaying them** (Kamal does not check this for you; `bin/kamal config` succeeds even when secrets are missing):

```bash
for v in KAMAL_REGISTRY_PASSWORD SECRET_KEY_BASE DEMO_USERNAME DEMO_PASSWORD TYPESAFE_API_KEY; do
  [ -n "$(printenv "$v")" ] && echo "$v: set" || echo "$v: MISSING"
done
```

Variables exist only in that terminal session. Open a new terminal for deploys and repeat this step, or resolve them from a password manager with a Kamal secrets adapter (`bin/kamal secrets --help`). Never put values in `config/deploy.yml`, `.env.example`, or the example file. The real `.env` is for local development only and is **not** read by Kamal.

## Non-secret production settings

Set in `config/deploy.yml` (`env.clear`), already filled in:

| Name | Value |
|---|---|
| `AI_PROVIDER` | `typesafe` |
| `TYPESAFE_MODEL` | `jev-latest` |
| `TYPESAFE_BASE_URL` | `https://api.typesafe.ai` |
| `AI_TIMEOUT_SECONDS` | `10` |
| `ANALYSES_PER_HOUR` | `8` |
| `FAILED_LOGINS_PER_15_MINUTES` | `10` |
| `RAILS_MAX_THREADS` | `2` |
| `PORT` | `3000` |
| `RAILS_LOG_LEVEL` | `info` |
| `APP_HOSTS` | the final hostname (placeholder until the live phase) |

`RAILS_ENV=production` is set in the `Dockerfile`. `WEB_CONCURRENCY` is ignored: `config/puma.rb` pins a single process. In production the app refuses to boot with `AI_PROVIDER=typesafe` if `TYPESAFE_API_KEY` or `TYPESAFE_MODEL` is missing, and serves only exact hostnames listed in `APP_HOSTS` (an unset or invalid value refuses everything except `/up`).

## Verify the configuration locally **[LOCAL: safe now]**

```bash
bundle exec rspec          # includes deployment-configuration specs
bin/kamal config           # parses config/deploy.yml; contacts no server or registry
```

`bin/kamal config` shows the resolved settings and never prints secret values. Validation done during preparation also confirmed (with fake values, network denied): TLS on, proxy host and `app_port` 3000, health check `/up`, `forward-headers` true, five secrets resolved by name.

### Install Docker and Buildx **[LOCAL: safe now]**

This is the procedure that was tested (macOS on Apple Silicon, Homebrew):

```bash
brew install colima docker docker-buildx
```

Homebrew installs Buildx as a Docker CLI plugin but does not register it. Its caveat (`brew info docker-buildx`) says to add the plugin directory to `~/.docker/config.json`. **Merge** this key into the existing JSON and keep every other key (for example `auths`); do not replace the file:

```json
"cliPluginsExtraDirs": [
  "/opt/homebrew/lib/docker/cli-plugins"
]
```

(On an Intel Mac Homebrew's prefix is `/usr/local`; use the path printed by `brew info docker-buildx`.) Do not symlink the plugin by hand. Then confirm:

```bash
docker buildx version        # prints "github.com/docker/buildx v0.37.2 Homebrew" (or newer)
```

### Build and run the production image locally **[LOCAL: safe now]**

On Apple Silicon, start Colima once with Rosetta so the amd64 build runs at near-native speed, and stop it when you are done. Colima provides a working Buildx builder named `colima` (docker driver); no extra builder had to be created.

```bash
colima start --vm-type vz --vz-rosetta --cpu 4 --memory 6 --disk 30
docker buildx ls                                              # shows the "colima" builder, running
docker buildx build --check --platform linux/amd64 .          # Dockerfile lint: "Check complete, no warnings found."
docker buildx build --platform linux/amd64 --load -t decision-lens-local .
docker run -d --name decision-lens-local --platform linux/amd64 -p 127.0.0.1::3000 \
  -e SECRET_KEY_BASE=local-test-not-a-real-secret-$(openssl rand -hex 16) \
  -e DEMO_USERNAME=fake -e DEMO_PASSWORD=fake -e AI_PROVIDER=fake \
  -e APP_HOSTS=localhost decision-lens-local
PORT_ON_HOST=$(docker port decision-lens-local 3000/tcp | head -1 | sed 's/.*://')
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$PORT_ON_HOST/up                                              # 200
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: localhost' -H 'X-Forwarded-Proto: https' http://127.0.0.1:$PORT_ON_HOST/login   # 200
docker rm -f decision-lens-local && docker rmi decision-lens-local     # clean up
docker buildx prune -f                                                 # optional: clear the build cache
colima stop
```

Use fake values only; never pass real secrets or mount `.env` into a local container. The app enforces HTTPS, so the `Host` and `X-Forwarded-Proto` headers stand in for kamal-proxy (plain `http://` to `/` correctly returns a 301 to HTTPS). The Dockerfile's `# syntax` and `# check=error=true` lines are processed by BuildKit through Buildx (a deliberately bad Dockerfile with the same check line fails the lint). Without Buildx, `docker build` falls back to the deprecated legacy builder, which ignores those lines. Kamal manages its own Buildx builder when it deploys; that step has not been exercised yet.

**Verified during preparation** (Colima 0.10.3, Docker 29.8.2, Buildx 0.37.2, Rosetta): the amd64 image builds in about 80 seconds and is about 130 MB; it runs as UID 1000 with no database, answers `/up` with 200 and `/login` with 200, redirects plain HTTP to HTTPS, rejects unknown hosts, sets an HTTPS-only `Secure; HttpOnly; SameSite=Lax` session cookie, signs in and analyzes with the fake provider, uses about 90 MB of memory, and runs the analyzer with no network at all. The image history and every layer contain no `.env`, `.git`, `.kamal`, key files, specs, or docs.

## Create the server **[LIVE: creates a billable cloud resource]**

1. DigitalOcean control panel: *Create → Droplets*.
2. **Image:** the newest Ubuntu LTS offered. **Plan:** Basic → Regular → 1 GB / 1 vCPU / 25 GB ($6/month). **Region:** the one nearest your audience (for US East, New York). Skip paid Backups: the server is stateless.
3. **Authentication:** SSH key (upload your public key). Do not use a password. Enable free Monitoring.
4. Create the Droplet and note its public IPv4 address.

### Firewall **[LIVE]**

Attach a DigitalOcean Cloud Firewall to the Droplet:

| Direction | Port | Source |
|---|---|---|
| Inbound | TCP 22 (SSH) | your own IP address (preferred) or all |
| Inbound | TCP 80 (HTTP) | all (needed for the certificate challenge and redirect) |
| Inbound | TCP 443 (HTTPS) | all |
| Outbound | all | all (image pulls, Let's Encrypt, TypeSafe) |

Do not open 3000: the app container is never published to the host. Prefer the Cloud Firewall over `ufw`, because Docker-published ports bypass `ufw` rules.

### Add swap on the 1 GB server **[LIVE]**

```bash
ssh root@DROPLET_IP
fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
exit
```

### Point DNS at the Droplet before the first deploy **[LIVE: changes DNS]**

Create an **A** record `lens` (or your chosen subdomain) pointing at the Droplet's IPv4 address, TTL 300. If the DNS provider can proxy traffic (Cloudflare), set the record to **DNS only**: kamal-proxy must receive the Let's Encrypt challenge directly. Confirm propagation before deploying:

```bash
dig +short lens.yourdomain.example     # must print the Droplet IP
```

Automatic HTTPS fails (and retries) if the name does not yet resolve to the server.

## First deployment **[LIVE]**

1. Replace the two placeholders in `config/deploy.yml` (see above) and commit that change.
2. Export the five secrets in your terminal and run the check above.
3. Run:

   ```bash
   bin/kamal setup
   ```

   This connects over SSH, installs Docker on the Droplet if missing, starts kamal-proxy, builds the amd64 image locally, pushes it to `ghcr.io` (this is the first registry login and push), and starts the app. On Apple Silicon the amd64 build runs under emulation and can take several minutes. A remote builder is possible but a 1 GB Droplet is a poor build host.

## Smoke tests after the first deploy **[LIVE]**

Replace `HOST` and `DROPLET_IP`.

| # | Check | Expected |
|---|---|---|
| 1 | `curl -sI http://HOST/` | `301` to `https://HOST/` |
| 2 | `curl -sI https://HOST/up` | `200`, valid Let's Encrypt certificate |
| 3 | `curl -sI https://HOST/` | `302` to `/login`, `strict-transport-security` header present |
| 4 | `curl -sI https://HOST/login` | `200` with **no** `Location` header (a redirect loop means the proxy is not sending `X-Forwarded-Proto: https`; stop and fix before use) |
| 5 | `curl -sk -o /dev/null -w '%{http_code}' https://DROPLET_IP/` | not the app (no sign-in page): kamal-proxy only routes the configured host |
| 6 | `nc -zv -w 3 DROPLET_IP 3000` | fails (the app port is not exposed) |
| 7 | `curl -s -o /dev/null -w '%{http_code}' --resolve other.example:443:DROPLET_IP https://other.example/login` | not `200` (unknown hosts never reach the app) |
| 8 | `curl -s -o /dev/null -w '%{http_code}' -H 'X-Forwarded-Host: evil.example' https://HOST/login` | `403` if the proxy forwards the header (Rails refuses it), `200` if the proxy overwrites it; both are safe |
| 9 | Sign in with the real demo credentials in a private window; browser dev tools show the session cookie `Secure`, `HttpOnly`, `SameSite=Lax` | signed in; sign out works |
| 10 | Failed-login throttle and client-IP trust test (below) | `401` ten times, then `429` |
| 11 | One custom analysis through the UI | three cards, summary, "Analyzed by TypeSafe Jev" note; one live Jev request, a fraction of a cent |
| 12 | `ssh root@DROPLET_IP docker stats --no-stream` | app memory well under 512 MB |
| 13 | `bin/kamal app logs` | request lines, no visitor text, no passwords, no API key |

### Client-IP trust and rate-limit test (check 10)

This proves the throttle uses the real client address and that a client-supplied `X-Forwarded-For` cannot dodge it. It uses up your own failed-login allowance for 15 minutes.

```bash
HOST=lens.yourdomain.example
JAR=$(mktemp)
for i in $(seq 1 12); do
  TOKEN=$(curl -s -c "$JAR" -b "$JAR" "https://$HOST/login" | grep -o 'name="authenticity_token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"$//')
  curl -s -o /dev/null -w "attempt $i: %{http_code}\n" -c "$JAR" -b "$JAR" \
    -H "X-Forwarded-For: 203.0.113.$i" \
    --data-urlencode "authenticity_token=$TOKEN" -d username=nobody -d password=wrong "https://$HOST/login"
done
rm -f "$JAR"
```

Expected: attempts 1–10 return `401`, then `429`. If every attempt returns `401`, the forged header is being trusted: **stop**, set `forward_headers: false` for a test deploy, and re-run (check 4 will show whether HTTPS detection still works). The analysis limit (`ANALYSES_PER_HOUR=8`) uses the same client address; to test it cheaply, set `ANALYSES_PER_HOUR: 2` temporarily and run `bin/kamal deploy`, then restore 8.

### TypeSafe and cost controls **[LIVE]**

Set a monthly spending limit or alert in TypeSafe. Make one approved Jev request (check 11). Pricing and model availability: see the README and TypeSafe's current documentation.

## Routine updates **[LIVE]**

```bash
git push origin main                      # code is built from the committed state
# export the five secrets in this terminal, then:
bin/kamal deploy
```

Deploys swap containers with no downtime and keep `retain_containers: 3` old containers. To change a non-secret setting, edit `config/deploy.yml` and redeploy; to change a secret, update your environment and redeploy.

## Logs and status **[LIVE]**

```bash
bin/kamal app details                  # container state and image version
bin/kamal app logs -f                  # follow application logs (Ctrl-C to stop)
bin/kamal proxy logs                   # kamal-proxy and certificate messages
bin/kamal details                      # app and proxy containers on every server
bin/kamal app containers               # available versions (git SHAs) for rollback
ssh root@DROPLET_IP docker stats --no-stream
```

## Rollback and recovery **[LIVE]**

- **Bad release:** `bin/kamal app containers` to find the previous version, then `bin/kamal rollback VERSION`. Or revert the commit and `bin/kamal deploy`.
- **Deploy stuck or "lock" error:** `bin/kamal lock status`, and if a previous run died, `bin/kamal lock release`.
- **App unhealthy after deploy:** Kamal keeps the old container serving if the new one fails its `/up` health check. Read `bin/kamal app logs` for the cause (a missing secret, `APP_HOSTS` or `TYPESAFE_*` configuration error fails the boot on purpose).
- **Certificate not issued:** check DNS (`dig`), ports 80/443 in the firewall, and `bin/kamal proxy logs`; fix, then `bin/kamal deploy` again. Avoid repeated rapid retries (Let's Encrypt rate limits).
- **Proxy broken:** `bin/kamal proxy reboot`.
- **Server unreachable or corrupted:** reboot from the DigitalOcean panel; if needed create a new Droplet, update `servers.web` and DNS, and run `bin/kamal setup`. The app has no state to restore.
- **Compromised or leaked secret:** rotate it (new `SECRET_KEY_BASE` signs everyone out; new demo password; new TypeSafe or GitHub token), update your environment, `bin/kamal deploy`, and revoke the old credential at its source.

## Stop billing: destroy the Droplet **[LIVE: destructive]**

> **Warning: destroying a Droplet is permanent and cannot be undone.** Everything on it is deleted. This app keeps no data, but you will lose the server and its IP address. A powered-off Droplet **still bills**; only destroying it stops charges.

1. Optional clean removal: `bin/kamal remove` (stops and removes the app and kamal-proxy containers).
2. DigitalOcean panel: *Droplet → Destroy* (confirm the name). Also delete the Cloud Firewall and any reserved IP if you created one.
3. Remove the DNS `A` record.
4. Revoke the GitHub token and delete the `decision-lens` package in GitHub.
5. Remove or rotate the TypeSafe key if it should no longer be valid.

## What is not configured

No CI deployment, no database, no Redis, no background jobs, no volumes, no accessories, no log shipping, no backups. Deployment is a manual `bin/kamal deploy` from your machine; automating it from CI is a possible later step.
