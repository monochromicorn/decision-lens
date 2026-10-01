require "rails_helper"

RSpec.describe Providers::Fake do
  def analyze(text) = DecisionAnalyzer.call(text)

  def verdict(result) = result.values_at(:category, :urgency, :action).map { |decision| decision[:value] }

  it "is deterministic" do
    text = "The app crashes with an error, please help immediately"

    expect(analyze(text)).to eq(analyze(text))
  end

  it "classifies an outage as support, high urgency, escalate" do
    expect(verdict(analyze("Production is down and customers cannot log in. Urgent!"))).to eq(%w[support high escalate])
  end

  it "classifies a duplicate charge as billing to review" do
    result = analyze("I was charged twice and need a refund for my subscription.")

    expect(result[:category][:value]).to eq("billing")
    expect(result[:action][:value]).to eq("review")
  end

  it "classifies thanks as low-urgency feedback to automate" do
    expect(verdict(analyze("Thank you, the new release is fantastic and I love it."))).to eq(%w[feedback low automate])
  end

  it "escalates security issues" do
    expect(analyze("Someone used my account without permission after a phishing email.")[:action][:value]).to eq("escalate")
  end

  it "falls back to 'other' with low confidence when nothing matches" do
    result = analyze("Lorem ipsum dolor sit amet consectetur")

    expect(result[:category][:value]).to eq("other")
    expect(result[:category][:confidence]).to be < DecisionAnalyzer::LOW_CONFIDENCE
  end

  it "returns JSON that the analyzer accepts without modification of vocabulary" do
    raw = described_class.new.complete("Production is down, urgent", timeout: 1.0)

    expect(JSON.parse(raw).keys).to match_array(%w[category urgency action summary])
  end
end
