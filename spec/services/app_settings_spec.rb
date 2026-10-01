require "rails_helper"

RSpec.describe AppSettings do
  describe ".validate_ai_configuration!" do
    it "passes for the fake provider without any TypeSafe settings" do
      with_env("AI_PROVIDER" => "fake", "TYPESAFE_API_KEY" => "", "TYPESAFE_MODEL" => "") do
        expect { described_class.validate_ai_configuration! }.not_to raise_error
      end
    end

    it "names every missing TypeSafe variable, without values" do
      with_env("AI_PROVIDER" => "typesafe", "TYPESAFE_API_KEY" => "", "TYPESAFE_MODEL" => "") do
        expect { described_class.validate_ai_configuration! }
          .to raise_error(DecisionAnalyzer::ConfigurationError, "AI_PROVIDER=typesafe requires TYPESAFE_API_KEY, TYPESAFE_MODEL")
      end
    end

    it "passes when the TypeSafe settings are present" do
      with_env("AI_PROVIDER" => "typesafe", "TYPESAFE_API_KEY" => "k", "TYPESAFE_MODEL" => "jev-test") do
        expect { described_class.validate_ai_configuration! }.not_to raise_error
      end
    end
  end

  describe ".ai_provider" do
    it "defaults to fake outside production" do
      with_env("AI_PROVIDER" => nil) do
        expect(described_class.ai_provider).to eq("fake")
      end
    end
  end
end
