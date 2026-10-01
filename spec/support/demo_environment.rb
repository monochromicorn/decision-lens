# Gives every example a known, isolated environment: fixed demo credentials, the
# fake AI provider, small rate limits, and empty rate-limit counters. ENV is
# restored afterwards so nothing leaks between examples (or from a developer's .env).
module DemoEnvironment
  USERNAME = "demo-user".freeze
  PASSWORD = "demo-pass-123".freeze

  DEFAULTS = {
    "DEMO_USERNAME" => USERNAME,
    "DEMO_PASSWORD" => PASSWORD,
    "AI_PROVIDER" => "fake",
    "ANALYSES_PER_HOUR" => "3",
    "FAILED_LOGINS_PER_15_MINUTES" => "3"
  }.freeze

  # Temporarily overrides environment variables for the block.
  def with_env(overrides)
    saved = overrides.keys.to_h { |key| [ key, ENV[key] ] }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end

RSpec.configure do |config|
  config.include DemoEnvironment

  config.around do |example|
    original = ENV.to_h
    DemoEnvironment::DEFAULTS.each { |key, value| ENV[key] = value }
    RateLimiter.reset!
    example.run
  ensure
    ENV.replace(original)
  end
end
