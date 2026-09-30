# Central, read-at-call-time access to environment configuration.
module AppSettings
  MIN_INPUT_LENGTH = 10
  MAX_INPUT_LENGTH = 2_000

  module_function

  def demo_username = ENV["DEMO_USERNAME"].to_s
  def demo_password = ENV["DEMO_PASSWORD"].to_s

  def credentials_configured?
    demo_username.present? && demo_password.present?
  end

  # "fake" is the deterministic offline provider. Production has no default on
  # purpose: a real provider must be chosen explicitly.
  def ai_provider
    ENV.fetch("AI_PROVIDER") { Rails.env.production? ? "" : "fake" }.to_s.downcase
  end

  def ai_timeout = ENV.fetch("AI_TIMEOUT_SECONDS", 10).to_f
  def analyses_per_hour = ENV.fetch("ANALYSES_PER_HOUR", 8).to_i
  def failed_logins_per_15_minutes = ENV.fetch("FAILED_LOGINS_PER_15_MINUTES", 10).to_i
end
