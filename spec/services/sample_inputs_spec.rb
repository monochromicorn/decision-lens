require "rails_helper"

RSpec.describe SampleInputs do
  described_class::ALL.each do |sample|
    describe sample.label do
      it "has a precomputed result that satisfies the normalized schema" do
        provider = instance_double(Providers::Fake, complete: sample.result)

        expect(DecisionAnalyzer.new(provider: provider).call(sample.text)).to eq(sample.result)
      end

      it "has text long enough to be valid input" do
        expect(DecisionInput.new(sample.text)).to be_valid
      end

      it "is found by its exact text, ignoring surrounding whitespace" do
        expect(described_class.find_by_text("  #{sample.text}\n")).to eq(sample)
      end
    end
  end

  it "does not match arbitrary text" do
    expect(described_class.find_by_text("something else entirely")).to be_nil
  end
end
