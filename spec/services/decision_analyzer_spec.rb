require "rails_helper"

RSpec.describe DecisionAnalyzer do
  def good_response(overrides = {})
    {
      category: { value: "Support", confidence: 0.912 },
      urgency: { value: "high", confidence: 0.84 },
      action: { value: "escalate", confidence: 0.88 },
      summary: "  Urgent   support issue.  "
    }.merge(overrides)
  end

  def analyze(response, text = "x" * 10)
    described_class.new(provider: provider_double(response)).call(text)
  end

  describe "normalization" do
    it "turns a valid hash into the stable result shape" do
      result = analyze(good_response, "hello there friend")

      expect(result).to eq(
        category: { value: "support", confidence: 0.91 },
        urgency: { value: "high", confidence: 0.84 },
        action: { value: "escalate", confidence: 0.88 },
        summary: "Urgent support issue."
      )
      expect(result.keys).to eq(%i[category urgency action summary])
    end

    it "accepts JSON strings and clamps confidence to 0..1" do
      json = JSON.generate(good_response(urgency: { value: "low", confidence: 7 }))

      expect(analyze(json)[:urgency][:confidence]).to eq(1.0)
    end

    it "truncates long summaries" do
      result = analyze(good_response(summary: "word " * 200))

      expect(result[:summary].length).to be <= described_class::MAX_SUMMARY_LENGTH
    end
  end

  describe "invalid provider output" do
    {
      "non-JSON text" => "not json at all",
      "a JSON array" => "[1, 2]",
      "a category outside the vocabulary" => { category: { value: "weather", confidence: 0.9 } },
      "a missing urgency" => { urgency: nil },
      "a non-numeric confidence" => { action: { value: "escalate", confidence: "high" } },
      "an empty summary" => { summary: "" }
    }.each do |label, bad|
      it "rejects #{label}" do
        response = bad.is_a?(Hash) ? good_response(bad) : bad

        expect { analyze(response) }.to raise_error(described_class::InvalidResponse)
      end
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

  describe "configuration" do
    it "raises a configuration error for an unknown provider" do
      with_env("AI_PROVIDER" => "nonexistent") do
        expect { described_class.new }.to raise_error(described_class::ConfigurationError)
      end
    end

    it "builds the fake provider when configured" do
      expect(described_class.new.call("An invoice problem, please help")).to include(:category, :urgency, :action, :summary)
    end
  end

  it "sends exactly one request containing only the submitted text" do
    provider = provider_double(good_response)

    described_class.new(provider: provider).call("only this")

    expect(provider).to have_received(:complete).once.with("only this", timeout: a_kind_of(Float))
  end
end
