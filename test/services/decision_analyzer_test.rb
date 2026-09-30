require "test_helper"

class DecisionAnalyzerTest < ActiveSupport::TestCase
  def good_response(overrides = {})
    {
      category: { value: "Support", confidence: 0.912 },
      urgency: { value: "high", confidence: 0.84 },
      action: { value: "escalate", confidence: 0.88 },
      summary: "  Urgent   support issue.  "
    }.merge(overrides)
  end

  test "normalizes a valid hash into the stable result shape" do
    result = DecisionAnalyzer.new(provider: RecordingProvider.new(good_response)).call("hello there friend")

    assert_equal({ value: "support", confidence: 0.91 }, result[:category])
    assert_equal({ value: "high", confidence: 0.84 }, result[:urgency])
    assert_equal({ value: "escalate", confidence: 0.88 }, result[:action])
    assert_equal "Urgent support issue.", result[:summary]
    assert_equal %i[category urgency action summary], result.keys
  end

  test "accepts JSON strings and clamps confidence" do
    json = JSON.generate(good_response(urgency: { value: "low", confidence: 7 }))
    result = DecisionAnalyzer.new(provider: RecordingProvider.new(json)).call("x" * 10)

    assert_equal 1.0, result[:urgency][:confidence]
  end

  test "truncates long summaries" do
    long = "word " * 200
    result = DecisionAnalyzer.new(provider: RecordingProvider.new(good_response(summary: long))).call("x" * 10)

    assert_operator result[:summary].length, :<=, DecisionAnalyzer::MAX_SUMMARY_LENGTH
  end

  test "rejects malformed or incomplete responses" do
    [
      "not json at all",
      "[1, 2]",
      good_response(category: { value: "weather", confidence: 0.9 }),
      good_response(urgency: nil),
      good_response(action: { value: "escalate", confidence: "high" }),
      good_response(summary: "")
    ].each do |bad|
      assert_raises(DecisionAnalyzer::InvalidResponse, "expected #{bad.inspect} to be rejected") do
        DecisionAnalyzer.new(provider: RecordingProvider.new(bad)).call("x" * 10)
      end
    end
  end

  test "provider errors propagate as analyzer errors" do
    [ DecisionAnalyzer::TimeoutError, DecisionAnalyzer::RateLimited,
      DecisionAnalyzer::AuthenticationFailed, DecisionAnalyzer::ProviderError ].each do |error|
      provider = RecordingProvider.new { raise error, "boom" }
      assert_raises(error) { DecisionAnalyzer.new(provider: provider).call("x" * 10) }
    end
  end

  test "unknown provider is a configuration error" do
    with_env("AI_PROVIDER" => "nonexistent") do
      assert_raises(DecisionAnalyzer::ConfigurationError) { DecisionAnalyzer.new }
    end
  end

  test "sends exactly the submitted text and nothing else" do
    provider = RecordingProvider.new(good_response)
    DecisionAnalyzer.new(provider: provider).call("only this")

    assert_equal [ "only this" ], provider.calls
  end
end
