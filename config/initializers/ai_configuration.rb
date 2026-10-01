# Production boot check. Skipped during asset precompilation, which runs without secrets.
Rails.application.config.after_initialize do
  AppSettings.validate_ai_configuration! if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
end
