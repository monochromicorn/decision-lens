require "active_support/core_ext/integer/time"
require_relative "../../lib/allowed_hosts"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # TLS ends at the hosting proxy, which talks plain HTTP to the app. Rails therefore
  # decides "is this HTTPS?" from the forwarded protocol header (X-Forwarded-Proto) and
  # redirects everything else. Do NOT enable assume_ssl: it would treat plain-HTTP
  # requests as secure and skip the redirect.
  config.force_ssl = true

  # The health check must work over plain HTTP from the platform, so it is not redirected.
  config.ssl_options = { redirect: { exclude: AllowedHosts.health_check_exclusion } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Host authorization: only the exact hostnames listed in APP_HOSTS are served (see
  # lib/allowed_hosts.rb). With nothing valid configured, everything but /up is refused.
  config.hosts = AllowedHosts.for_rails(ENV["APP_HOSTS"])
  config.host_authorization = { exclude: AllowedHosts.health_check_exclusion }
end
