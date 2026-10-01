require "rails_helper"

RSpec.describe DecisionInput do
  describe "length boundaries (applied after trimming)" do
    it "accepts 10 through 2,000 characters" do
      expect(described_class.new("a" * 10)).to be_valid
      expect(described_class.new("   #{'a' * 10}   ")).to be_valid
      expect(described_class.new("a" * 2000)).to be_valid
    end

    it "rejects text that is too short, too long, blank, or nil" do
      expect(described_class.new("a" * 9)).not_to be_valid
      expect(described_class.new("   #{'a' * 9}   ")).not_to be_valid
      expect(described_class.new("a" * 2001)).not_to be_valid
      expect(described_class.new("     ")).not_to be_valid
      expect(described_class.new(nil)).not_to be_valid
    end

    it "strips surrounding whitespace from the stored text" do
      expect(described_class.new("  hello there friend \n").text).to eq("hello there friend")
    end
  end

  describe "error messages" do
    def message_for(text)
      described_class.new(text).tap(&:valid?).errors[:text].first
    end

    it "names the problem" do
      expect(message_for("")).to match(/blank/)
      expect(message_for("hi")).to match(/too short/)
      expect(message_for("a" * 2001)).to match(/too long/)
    end
  end
end
