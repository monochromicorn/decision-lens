# Production boot warnings for APP_HOSTS. Values are never printed, only counts.
Rails.application.config.after_initialize do
  next unless Rails.env.production?

  result = AllowedHosts.parse(ENV["APP_HOSTS"])
  if result.rejected_count.positive?
    Rails.logger.warn("APP_HOSTS: ignored #{result.rejected_count} invalid entr#{result.rejected_count == 1 ? 'y' : 'ies'} (not exact hostnames)")
  end
  unless result.configured?
    Rails.logger.warn("APP_HOSTS is empty or has no valid hostnames: all requests except /up will be refused")
  end
end
