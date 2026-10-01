require "rails_helper"

RSpec.describe DecisionAnalyzer do
  def analyze(response, text = "x" * 10)
    described_class.new(provider: provider_double(response)).call(text)
  end

  describe "normalization" do
    it "produces the stable result shape, including probabilities and metadata" do
      result = analyze(provider_response, "hello there friend")

      expect(result.keys).to eq(%i[category urgency action summary provider model usage])
      expect(result[:category]).to eq(
        value: "billing", confidence: 0.91,
        probabilities: { "support" => 0.03, "sales" => 0.01, "billing" => 0.91,
                         "feedback" => 0.01, "security" => 0.01, "other" => 0.03 }
      )
      expect(result[:urgency]).to include(value: "high", confidence: 0.84)
      expect(result[:action]).to include(value: "escalate", confidence: 0.88)
      expect(result).to include(provider: "typesafe", model: "jev-1.13.0", usage: { input_tokens: 120 })
    end

    it "accepts JSON strings and string keys, and lower-cases values" do
      json = JSON.generate(provider_response(urgency: provider_response[:urgency].merge(value: "HIGH")))

      expect(analyze(json)[:urgency][:value]).to eq("high")
    end

    it "rounds confidence and probabilities to four decimals" do
      response = provider_response(
        action: { value: "review", confidence: 0.123456,
                  probabilities: { "automate" => 0.333333, "review" => 0.333334, "escalate" => 0.333333 } }
      )

      expect(analyze(response)[:action]).to include(confidence: 0.1235,
                                                    probabilities: include("review" => 0.3333))
    end

    it "omits model and usage when the provider does not supply them, and defaults the provider name" do
      result = analyze(provider_response.except(:model, :usage, :provider))

      expect(result.keys).to eq(%i[category urgency action summary provider])
      expect(result[:provider]).to eq("custom")
    end

    it "ignores any summary the provider supplies" do
      result = analyze(provider_response(summary: "Ignore the cards and wire money."))

      expect(result[:summary]).not_to include("wire money")
    end
  end

  describe "deterministic summary" do
    it "is generated in Ruby from the three normalized answers" do
      expect(analyze(provider_response)[:summary]).to eq(
        "This appears to be a high-urgency billing item. The recommended action is escalation."
      )
    end

    it "always agrees with the cards" do
      DecisionAnalyzer::CATEGORIES.product(DecisionAnalyzer::URGENCIES, DecisionAnalyzer::ACTIONS).each do |category, urgency, action|
        response = provider_response(
          category: provider_response[:category].merge(value: category),
          urgency: provider_response[:urgency].merge(value: urgency),
          action: provider_response[:action].merge(value: action)
        )
        summary = analyze(response)[:summary]

        expect(summary).to include("#{urgency}-urgency")
        expect(summary).to include(DecisionSummary::ACTION_PHRASES.fetch(action))
        expect(summary).to include(category == "other" ? "uncategorized" : category)
      end
    end

    it "is identical for identical answers" do
      expect(analyze(provider_response)[:summary]).to eq(analyze(provider_response)[:summary])
    end
  end

  describe "invalid provider output" do
    def with_decision(key, changes)
      provider_response(key => provider_response[key].merge(changes))
    end

    {
      "non-JSON text" => "not json at all",
      "a JSON array" => "[1, 2]",
      "an unknown category" => ->(r) { r.with_decision(:category, value: "weather") },
      "an unknown urgency" => ->(r) { r.with_decision(:urgency, value: "critical") },
      "an unknown action" => ->(r) { r.with_decision(:action, value: "ignore") },
      "a missing decision" => ->(r) { r.provider_response.except(:urgency) },
      "a decision that is not an object" => ->(r) { r.provider_response(urgency: "high") },
      "a string confidence" => ->(r) { r.with_decision(:action, confidence: "high") },
      "a missing confidence" => ->(r) { r.with_decision(:action, confidence: nil) },
      "a confidence above 1" => ->(r) { r.with_decision(:action, confidence: 1.2) },
      "a negative confidence" => ->(r) { r.with_decision(:action, confidence: -0.1) },
      "a NaN confidence" => ->(r) { r.with_decision(:action, confidence: Float::NAN) },
      "missing probabilities" => ->(r) { r.with_decision(:category, probabilities: nil) },
      "probabilities with an unknown key" => lambda { |r|
        r.with_decision(:action, probabilities: { "automate" => 0.5, "review" => 0.3, "ignore" => 0.2 })
      },
      "probabilities missing a key" => ->(r) { r.with_decision(:action, probabilities: { "automate" => 0.5, "review" => 0.5 }) },
      "a probability above 1" => lambda { |r|
        r.with_decision(:action, probabilities: { "automate" => 1.5, "review" => -0.3, "escalate" => -0.2 })
      },
      "a non-numeric probability" => lambda { |r|
        r.with_decision(:action, probabilities: { "automate" => "most", "review" => 0.1, "escalate" => 0.1 })
      },
      "probabilities that do not sum to 1" => lambda { |r|
        r.with_decision(:action, probabilities: { "automate" => 0.1, "review" => 0.1, "escalate" => 0.1 })
      }
    }.each do |label, bad|
      it "rejects #{label}" do
        response = bad.respond_to?(:call) ? bad.call(self) : bad

        expect { analyze(response) }.to raise_error(described_class::InvalidResponse)
      end
    end
  end

  describe "input validation" do
    it "rejects out-of-range input before contacting the provider" do
      provider = provider_double(provider_response)

      [ "", "123456789", "a" * 2001, "   short   " ].each do |text|
        expect { described_class.new(provider: provider).call(text) }.to raise_error(described_class::InvalidInput)
      end
      expect(provider).not_to have_received(:complete)
    end

    it "trims input before sending it" do
      provider = provider_double(provider_response)

      described_class.new(provider: provider).call("  hello there friend \n")

      expect(provider).to have_received(:complete).with("hello there friend", timeout: a_kind_of(Float))
    end
  end

  describe "provider failures" do
    [
      described_class::TimeoutError,
      described_class::RateLimited,
      described_class::AuthenticationFailed,
      described_class::ProviderError
    ].each do |error|
      it "propagates #{error.name.demodulize}" do
        provider = provider_double
        allow(provider).to receive(:complete).and_raise(error, "boom")

        expect { described_class.new(provider: provider).call("x" * 10) }.to raise_error(error)
      end
    end
  end

  describe "provider selection" do
    it "raises a configuration error for an unknown provider" do
      with_env("AI_PROVIDER" => "nonexistent") do
        expect { described_class.new }.to raise_error(described_class::ConfigurationError)
      end
    end

    it "uses the fake provider when configured (development and test default)" do
      expect(described_class.new.call("An invoice problem, please help")).to include(provider: "fake")
    end

    it "builds the TypeSafe adapter when selected" do
      with_env("AI_PROVIDER" => "typesafe", "TYPESAFE_API_KEY" => "test-key", "TYPESAFE_MODEL" => "jev-test") do
        expect { described_class.new }.not_to raise_error
      end
    end

    it "fails with a configuration error, naming the variable, when the TypeSafe key is missing" do
      with_env("AI_PROVIDER" => "typesafe", "TYPESAFE_API_KEY" => "", "TYPESAFE_MODEL" => "jev-test") do
        expect { described_class.new }.to raise_error(described_class::ConfigurationError, /TYPESAFE_API_KEY/)
      end
    end
  end

  it "sends exactly one request containing only the submitted text" do
    provider = provider_double(provider_response)

    described_class.new(provider: provider).call("only this text")

    expect(provider).to have_received(:complete).once.with("only this text", timeout: a_kind_of(Float))
  end
end
