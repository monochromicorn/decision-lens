module ProviderHelpers
  # A verifying double: it can only respond to what a real provider responds to,
  # so a provider whose interface drifts from Providers::Fake fails these specs.
  def provider_double(response = nil)
    instance_double(Providers::Fake).tap do |provider|
      allow(provider).to receive(:complete).and_return(response) unless response.nil?
    end
  end

  # A well-formed provider response (analyzer contract). Override any top-level key.
  def provider_response(overrides = {})
    {
      category: { value: "billing", confidence: 0.91,
                  probabilities: { "support" => 0.03, "sales" => 0.01, "billing" => 0.91,
                                   "feedback" => 0.01, "security" => 0.01, "other" => 0.03 } },
      urgency: { value: "high", confidence: 0.84,
                 probabilities: { "low" => 0.04, "medium" => 0.12, "high" => 0.84 } },
      action: { value: "escalate", confidence: 0.88,
                probabilities: { "automate" => 0.02, "review" => 0.10, "escalate" => 0.88 } },
      provider: "typesafe",
      model: "jev-1.13.0",
      usage: { input_tokens: 120 }
    }.merge(overrides)
  end
end

RSpec.configure do |config|
  config.include ProviderHelpers, type: :request
  config.include ProviderHelpers, type: :service
end
