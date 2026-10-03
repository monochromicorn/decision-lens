# syntax=docker/dockerfile:1
# check=error=true

# Production image for Decision Lens: Rails 8.1 on Puma, no database, no workers.
# Kamal builds and runs it (see docs/kamal-digitalocean-deployment.md). Manual build:
#   docker build --platform linux/amd64 -t decision-lens .

# Keep in sync with .ruby-version
ARG RUBY_VERSION=4.0.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime packages only. jemalloc lowers Ruby's memory use and fragmentation.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libjemalloc2 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Production environment. Development and test gems are never installed.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    PORT="3000"


# Build stage: compilers and headers live only here.
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

# Precompile bootsnap code caches, then assets (Propshaft: pure Ruby, no Node).
# The dummy secret exists only for this command and is not stored in the image.
RUN bundle exec bootsnap precompile app/ lib/
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage: runtime packages, gems, and the precompiled app only.
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run as an unprivileged user. Application code stays owned by root and is read-only for
# that user; only log/ and tmp/ are writable by it.
#
# `chmod -R a+rX` guarantees every file under /rails is readable, and every directory
# searchable, by the unprivileged user. It protects builds whose context was created under
# a restrictive umask (for example a clone or worktree made with umask 077), where COPY
# would otherwise carry source files in as mode 600, unreadable by UID 1000. It adds no
# write permission and changes nothing when modes are already fine.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin && \
    chmod -R a+rX /rails && \
    chown -R rails:rails log tmp
USER 1000:1000

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
