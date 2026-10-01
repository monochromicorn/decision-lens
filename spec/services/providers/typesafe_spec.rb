require "rails_helper"

RSpec.describe Providers::Typesafe do
  let(:transport) { instance_double(Providers::Typesafe::NetHttpTransport) }
  let(:api_key) { "test-key-not-real" }
  let(:provider) do
    described_class.new(api_key: api_key, model: "jev-test", base_url: "https://api.typesafe.ai", transport: transport)
  end

  def respond_with(status, body)
    body = JSON.generate(body) unless body.is_a?(String)
    allow(transport).to receive(:request).and_return([ status, body ])
  end

  def analyze(text = "I was charged twice and need the duplicate charge fixed today.")
    DecisionAnalyzer.new(provider: provider).call(text)
  end

  describe "request" do
    before { respond_with(200, jev_body) }

    it "makes exactly one POST /v1/systemone with all three questions" do
      analyze("My invoice is wrong")

      expect(transport).to have_received(:request).once
      expect(transport).to have_received(:request) do |method, uri, headers:, body:, timeout:|
        payload = JSON.parse(body)

        expect(method).to eq(:post)
        expect(uri.to_s).to eq("https://api.typesafe.ai/v1/systemone")
        expect(timeout).to eq(AppSettings.ai_timeout)
        expect(payload.keys).to match_array(%w[state model questions])
        expect(payload["state"]).to eq("My invoice is wrong")
        expect(payload["model"]).to eq("jev-test")
        expect(payload["questions"].keys).to eq(%w[category urgency action])
        expect(headers["Authorization"]).to eq("Bearer #{api_key}")
      end
    end

    it "asks Choice, Score, Choice with fully described options" do
      analyze
      questions = nil
      expect(transport).to have_received(:request) { |*_, body:, **| questions = JSON.parse(body)["questions"] }

      expect(questions.values.map { |q| q["type"] }).to eq(%w[choice score choice])
      expect(questions["category"]["criteria"].keys).to eq(DecisionAnalyzer::CATEGORIES)
      expect(questions["action"]["criteria"].keys).to eq(DecisionAnalyzer::ACTIONS)
      expect(questions["urgency"]["criteria"].length).to eq(DecisionAnalyzer::URGENCIES.length)
      questions.values.flat_map { |q| q["criteria"].is_a?(Hash) ? q["criteria"].values : q["criteria"] }.each do |description|
        expect(description.length).to be > 40 # a real description, not a bare label
      end
    end

    it "does not ask for prose" do
      analyze
      payload = nil
      expect(transport).to have_received(:request) { |*_, body:, **| payload = body }

      expect(JSON.parse(payload)["questions"].keys).not_to include("summary")
    end
  end

  describe "response normalization" do
    it "maps all three answer types, probabilities, confidence, model, and usage" do
      respond_with(200, jev_body)

      result = analyze

      expect(result[:category]).to include(value: "billing", confidence: 0.91)
      expect(result[:category][:probabilities]).to include("billing" => 0.91, "support" => 0.03)
      expect(result[:urgency]).to include(value: "high", confidence: 0.84)
      expect(result[:urgency][:probabilities]).to eq("low" => 0.04, "medium" => 0.12, "high" => 0.84)
      expect(result[:action]).to include(value: "escalate", confidence: 0.88)
      expect(result).to include(provider: "typesafe", model: "jev-1.13.0", usage: { input_tokens: 120 })
      expect(result[:summary]).to eq("This appears to be a high-urgency billing item. The recommended action is escalation.")
    end

    it "reports the model the API says answered, not the alias requested" do
      respond_with(200, jev_body("model" => "jev-1.99.0"))

      expect(analyze[:model]).to eq("jev-1.99.0")
    end

    it "picks the most probable urgency level rather than rounding the weighted score" do
      # The weighted score (0.9) would round to level 1, but level 0 is the most probable.
      urgency = jev_body["answers"]["urgency"].merge(
        "score" => 0.9, "probabilities" => { "0" => 0.5, "1" => 0.1, "2" => 0.4 }
      )
      respond_with(200, jev_answers(urgency: urgency))

      expect(analyze[:urgency][:value]).to eq("low")
    end
  end

  describe "HTTP failures" do
    it "maps 401 and 403 to AuthenticationFailed" do
      [ 401, 403 ].each do |status|
        respond_with(status, '{"detail":"Invalid API key"}')
        expect { analyze }.to raise_error(DecisionAnalyzer::AuthenticationFailed)
      end
    end

    it "maps 429 to RateLimited without retrying" do
      respond_with(429, "{}")

      expect { analyze }.to raise_error(DecisionAnalyzer::RateLimited)
      expect(transport).to have_received(:request).once
    end

    it "maps 422 to ProviderError and logs only field paths and codes, never visitor text" do
      respond_with(422, validation_error_body)
      allow(Rails.logger).to receive(:warn)

      expect { analyze }.to raise_error(DecisionAnalyzer::ProviderError)
      expect(Rails.logger).to have_received(:warn).with(a_string_including("HTTP 422 body.state:missing"))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(/VISITOR-TEXT-ECHO|Field required/))
    end

    it "maps 5xx and unexpected statuses to ProviderError without retrying" do
      [ 500, 502, 503, 418 ].each do |status|
        respond_with(status, "<html>upstream secret</html>")
        expect { analyze }.to raise_error(DecisionAnalyzer::ProviderError) { |e| expect(e.message).not_to include("secret") }
      end
      expect(transport).to have_received(:request).exactly(4).times
    end

    it "maps gateway timeouts to TimeoutError" do
      [ 408, 504 ].each do |status|
        respond_with(status, "")
        expect { analyze }.to raise_error(DecisionAnalyzer::TimeoutError)
      end
    end

    it "maps network timeouts to TimeoutError" do
      [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout ].each do |error|
        allow(transport).to receive(:request).and_raise(error)
        expect { analyze }.to raise_error(DecisionAnalyzer::TimeoutError)
      end
    end

    it "maps connection failures to ProviderError" do
      [ Errno::ECONNREFUSED, SocketError, EOFError, OpenSSL::SSL::SSLError ].each do |error|
        allow(transport).to receive(:request).and_raise(error)
        expect { analyze }.to raise_error(DecisionAnalyzer::ProviderError)
      end
    end

    it "never puts the API key or response bodies in error messages or logs" do
      lines = []
      allow(Rails.logger).to receive(:warn) { |line| lines << line }
      respond_with(500, "BODY-WITH-#{api_key}")

      expect { analyze }.to raise_error(DecisionAnalyzer::ProviderError) do |error|
        expect(error.message).not_to include(api_key)
      end
      expect(lines.join).not_to include(api_key)
      expect(lines.join).not_to include("BODY-WITH")
    end
  end

  describe "malformed responses" do
    it "rejects non-JSON bodies" do
      respond_with(200, "<html>not json</html>")
      expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse)
    end

    it "rejects JSON that is not an object" do
      respond_with(200, "[1,2,3]")
      expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse)
    end

    it "rejects a response with no answers" do
      respond_with(200, { "model" => "jev-test", "usage" => {} })
      expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse)
    end

    %w[category urgency action].each do |name|
      it "rejects a response missing the #{name} answer" do
        respond_with(200, jev_answers(name.to_sym => nil))
        expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse)
      end
    end

    it "rejects an answer of the wrong type" do
      respond_with(200, jev_answers(category: { "type" => "noul", "noul" => 0.9 }))
      expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse)
    end

    it "rejects an unknown choice value" do
      answer = jev_body["answers"]["category"].merge("choice" => "weather")
      respond_with(200, jev_answers(category: answer))

      expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse, /unexpected value/)
    end

    it "rejects score probabilities for the wrong number of levels" do
      answer = jev_body["answers"]["urgency"].merge("probabilities" => { "0" => 0.5, "1" => 0.5 })
      respond_with(200, jev_answers(urgency: answer))

      expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse)
    end

    it "rejects a confidence outside 0..1" do
      answer = jev_body["answers"]["action"].merge("confidence" => 1.4)
      respond_with(200, jev_answers(action: answer))

      expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse)
    end

    it "rejects invalid probabilities" do
      answer = jev_body["answers"]["action"].merge("probabilities" => { "automate" => 0.9, "review" => 0.9, "escalate" => 0.9 })
      respond_with(200, jev_answers(action: answer))

      expect { analyze }.to raise_error(DecisionAnalyzer::InvalidResponse)
    end
  end

  describe "configuration" do
    it "requires an API key" do
      expect { described_class.new(api_key: "", model: "jev-test") }
        .to raise_error(DecisionAnalyzer::ConfigurationError, /TYPESAFE_API_KEY/)
    end

    it "requires a model" do
      expect { described_class.new(api_key: api_key, model: "") }
        .to raise_error(DecisionAnalyzer::ConfigurationError, /TYPESAFE_MODEL/)
    end

    it "refuses to send the key over plain HTTP to a non-local host" do
      expect { described_class.new(api_key: api_key, model: "m", base_url: "http://api.typesafe.ai") }
        .to raise_error(DecisionAnalyzer::ConfigurationError, /https/)
      expect { described_class.new(api_key: api_key, model: "m", base_url: "not a url") }
        .to raise_error(DecisionAnalyzer::ConfigurationError)
    end

    it "reads settings from the environment" do
      with_env("TYPESAFE_API_KEY" => "env-key", "TYPESAFE_MODEL" => "jev-env", "TYPESAFE_BASE_URL" => "https://example.invalid") do
        allow(transport).to receive(:request).and_return([ 200, JSON.generate(jev_body) ])
        described_class.new(transport: transport).complete("hello there friend")
      end

      expect(transport).to have_received(:request) do |_method, uri, headers:, body:, **|
        expect(uri.host).to eq("example.invalid")
        expect(headers["Authorization"]).to eq("Bearer env-key")
        expect(JSON.parse(body)["model"]).to eq("jev-env")
      end
    end
  end

  describe "#list_models" do
    it "returns names and release dates only" do
      respond_with(200, "models" => [ { "name" => "jev-latest", "description" => "General", "release_date" => "2026-09-15" } ])

      expect(provider.list_models).to eq([ { name: "jev-latest", release_date: "2026-09-15" } ])
      expect(transport).to have_received(:request).with(:get, anything, headers: anything, body: nil, timeout: anything)
    end
  end
end
