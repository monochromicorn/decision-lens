#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

cleanup() {
  bundle exec dotenv -f .env.kamal -- bin/kamal registry logout || true
  colima stop || true
}

trap cleanup EXIT

colima start

bundle exec dotenv -f .env.kamal -- bin/kamal deploy

curl --fail --silent --show-error \
  --output /dev/null \
  --write-out 'Health check: HTTP %{http_code}\n' \
  https://lens.juanmoredemo.com/up