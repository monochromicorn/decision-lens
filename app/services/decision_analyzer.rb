require "json"

# Single entry point for AI analysis. Controllers and views only know this class;
# provider-specific request/response handling lives in app/services/providers.
#
# A provider responds to #complete(text, timeout:) and returns the model's raw
# JSON (String or Hash) with keys category/urgency/action (each {value, confidence})
# and summary. It raises DecisionAnalyzer::Error subclasses on transport failures.
class DecisionAnalyzer
  CATEGORIES = %w[support sales billing feedback security other].freeze
  URGENCIES  = %w[low medium high].freeze
  ACTIONS    = %w[automate review escalate].freeze
  LOW_CONFIDENCE = 0.6
  MAX_SUMMARY_LENGTH = 280

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TimeoutError < Error; end
  class RateLimited < Error; end
  class AuthenticationFailed < Error; end
  class ProviderError < Error; end
  class InvalidResponse < Error; end

  PROVIDERS = {
    "fake" => "Providers::Fake"
  }.freeze

  def self.call(text, provider: nil)
    new(provider: provider).call(text)
  end

  def initialize(provider: nil)
    @provider = provider || build_provider
  end

  def call(text)
    normalize(@provider.complete(text, timeout: AppSettings.ai_timeout))
  end

  private

  def build_provider
    klass = PROVIDERS[AppSettings.ai_provider] or
      raise ConfigurationError, "Unknown AI provider #{AppSettings.ai_provider.inspect}"
    klass.constantize.new
  end

  def normalize(raw)
    data = raw.is_a?(String) ? JSON.parse(raw) : raw
    raise InvalidResponse, "response is not an object" unless data.is_a?(Hash)
    data = data.deep_stringify_keys

    {
      category: decision(data, "category", CATEGORIES),
      urgency: decision(data, "urgency", URGENCIES),
      action: decision(data, "action", ACTIONS),
      summary: summary(data)
    }
  rescue JSON::ParserError
    raise InvalidResponse, "response is not valid JSON"
  end

  def decision(data, key, allowed)
    entry = data[key]
    raise InvalidResponse, "#{key} missing" unless entry.is_a?(Hash)

    value = entry["value"].to_s.strip.downcase
    raise InvalidResponse, "#{key} has unexpected value" unless allowed.include?(value)

    confidence = entry["confidence"]
    raise InvalidResponse, "#{key} confidence missing" unless confidence.is_a?(Numeric)

    { value: value, confidence: confidence.to_f.clamp(0.0, 1.0).round(2) }
  end

  def summary(data)
    text = data["summary"].to_s.squish
    raise InvalidResponse, "summary missing" if text.empty?

    text.truncate(MAX_SUMMARY_LENGTH, separator: " ")
  end
end
