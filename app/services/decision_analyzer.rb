require "json"

# Single entry point for AI analysis. Controllers and views only know this class;
# provider-specific request/response handling lives in app/services/providers.
#
# A provider responds to #complete(text, timeout:) and returns (as a Hash or JSON
# String) one entry per decision plus optional metadata:
#
#   category/urgency/action: { value:, confidence:, probabilities: { name => p } }
#   provider: "typesafe", model: "jev-x", usage: { input_tokens: 120 }
#
# It raises DecisionAnalyzer::Error subclasses on transport failures. The analyzer
# validates everything, generates the summary itself, and returns the stable shape
# documented in the README.
class DecisionAnalyzer
  CATEGORIES = %w[support sales billing feedback security other].freeze
  URGENCIES  = %w[low medium high].freeze # ordered least to most urgent
  ACTIONS    = %w[automate review escalate].freeze
  VOCABULARIES = { category: CATEGORIES, urgency: URGENCIES, action: ACTIONS }.freeze

  LOW_CONFIDENCE = 0.6
  PROBABILITY_SUM_TOLERANCE = 0.05

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class InvalidInput < Error; end
  class TimeoutError < Error; end
  class RateLimited < Error; end
  class AuthenticationFailed < Error; end
  class ProviderError < Error; end
  class InvalidResponse < Error; end

  PROVIDERS = {
    "fake" => "Providers::Fake",
    "typesafe" => "Providers::Typesafe"
  }.freeze

  def self.call(text, provider: nil)
    new(provider: provider).call(text)
  end

  def self.normalize(raw)
    data = raw.is_a?(String) ? JSON.parse(raw) : raw
    raise InvalidResponse, "response is not an object" unless data.is_a?(Hash)
    data = data.deep_stringify_keys

    decisions = VOCABULARIES.to_h { |key, allowed| [ key, decision(data, key.to_s, allowed) ] }
    decisions.merge(
      summary: DecisionSummary.call(**decisions.transform_values { |d| d[:value] }),
      provider: data["provider"].to_s.presence || "custom",
      model: data["model"].to_s.presence,
      usage: usage(data["usage"])
    ).compact
  rescue JSON::ParserError
    raise InvalidResponse, "response is not valid JSON"
  end

  def initialize(provider: nil)
    @provider = provider || build_provider
  end

  def call(text)
    input = DecisionInput.new(text)
    raise InvalidInput, "input is not valid" unless input.valid?

    self.class.normalize(@provider.complete(input.text, timeout: AppSettings.ai_timeout))
  end

  def self.decision(data, key, allowed)
    entry = data[key]
    raise InvalidResponse, "#{key} missing" unless entry.is_a?(Hash)

    value = entry["value"].to_s.strip.downcase
    raise InvalidResponse, "#{key} has unexpected value" unless allowed.include?(value)

    {
      value: value,
      confidence: unit_number(entry["confidence"], "#{key} confidence"),
      probabilities: probabilities(entry["probabilities"], key, allowed)
    }
  end
  private_class_method :decision

  def self.probabilities(raw, key, allowed)
    raise InvalidResponse, "#{key} probabilities missing" unless raw.is_a?(Hash)

    raw = raw.transform_keys(&:to_s)
    raise InvalidResponse, "#{key} probabilities have unexpected keys" unless raw.keys.sort == allowed.sort

    values = allowed.to_h { |name| [ name, unit_number(raw[name], "#{key} probability") ] }
    unless (values.values.sum - 1.0).abs <= PROBABILITY_SUM_TOLERANCE
      raise InvalidResponse, "#{key} probabilities do not sum to 1"
    end

    values
  end
  private_class_method :probabilities

  # A finite number within 0..1, otherwise the provider response is rejected.
  def self.unit_number(raw, label)
    unless raw.is_a?(Numeric) && raw.to_f.finite? && raw.between?(0, 1)
      raise InvalidResponse, "#{label} is not a number between 0 and 1"
    end

    raw.to_f.round(4)
  end
  private_class_method :unit_number

  def self.usage(raw)
    return unless raw.is_a?(Hash) && raw["input_tokens"].is_a?(Integer) && raw["input_tokens"] >= 0

    { input_tokens: raw["input_tokens"] }
  end
  private_class_method :usage

  private

  def build_provider
    klass = PROVIDERS[AppSettings.ai_provider] or
      raise ConfigurationError, "Unknown AI provider #{AppSettings.ai_provider.inspect}"
    klass.constantize.new
  end
end
