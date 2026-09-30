require "test_helper"

class ProvidersFakeTest < ActiveSupport::TestCase
  def analyze(text) = DecisionAnalyzer.call(text)

  test "is deterministic" do
    assert_equal analyze("The app crashes with an error, please help immediately"),
                 analyze("The app crashes with an error, please help immediately")
  end

  test "classifies representative messages" do
    outage = analyze("Production is down and customers cannot log in. Urgent!")
    assert_equal %w[support high escalate], outage.values_at(:category, :urgency, :action).map { _1[:value] }

    billing = analyze("I was charged twice and need a refund for my subscription.")
    assert_equal "billing", billing[:category][:value]
    assert_equal "review", billing[:action][:value]

    thanks = analyze("Thank you, the new release is fantastic and I love it.")
    assert_equal %w[feedback low automate], thanks.values_at(:category, :urgency, :action).map { _1[:value] }

    security = analyze("Someone used my account without permission after a phishing email.")
    assert_equal "escalate", security[:action][:value]
  end

  test "falls back to other with low confidence" do
    result = analyze("Lorem ipsum dolor sit amet consectetur")
    assert_equal "other", result[:category][:value]
    assert_operator result[:category][:confidence], :<, DecisionAnalyzer::LOW_CONFIDENCE
  end

  test "precomputed sample results satisfy the normalized schema" do
    SampleInputs::ALL.each do |sample|
      normalized = DecisionAnalyzer.new(provider: RecordingProvider.new(sample.result)).call(sample.text)
      assert_equal sample.result, normalized, sample.label
      assert_operator sample.text.length, :>=, AppSettings::MIN_INPUT_LENGTH
    end
  end
end
