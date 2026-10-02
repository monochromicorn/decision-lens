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

  describe "rate-limit defaults" do
    it "allows 100 live analyses per client IP per hour when unset" do
      with_env("ANALYSES_PER_HOUR" => nil) do
        expect(described_class.analyses_per_hour).to eq(100)
      end
    end

    it "honors an explicit ANALYSES_PER_HOUR" do
      with_env("ANALYSES_PER_HOUR" => "2") do
        expect(described_class.analyses_per_hour).to eq(2)
      end
    end

    it "keeps the failed-login default at 10 per 15 minutes" do
      with_env("FAILED_LOGINS_PER_15_MINUTES" => nil) do
        expect(described_class.failed_logins_per_15_minutes).to eq(10)
      end
    end
  end
end
