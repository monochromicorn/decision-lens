require "rails_helper"

RSpec.describe "Decisions", type: :request do
  let(:billing_json) do
    JSON.generate(
      provider_response(
        urgency: { value: "medium", confidence: 0.8,
                   probabilities: { "low" => 0.1, "medium" => 0.8, "high" => 0.1 } },
        action: { value: "review", confidence: 0.5,
                  probabilities: { "automate" => 0.25, "review" => 0.5, "escalate" => 0.25 } }
      )
    )
  end

  before { sign_in }

  describe "GET /" do
    before { get root_path }

    it "shows the form, privacy note, samples, and sign-out" do
      expect(response).to have_http_status(:ok)
      assert_select "label[for=decision_text]"
      assert_select "textarea#decision_text"
      assert_select "a.sample", 3
      assert_select "form button", text: "Analyze decision"
      assert_select "button", text: "Sign out"
      expect(response.body).to match(/nothing leaves this server/) # fake provider in tests
    end

    it "shows the empty state and no results" do
      assert_select ".empty-state"
      assert_select "#results", 0
    end

    it "is not cacheable" do
      expect(response.headers["Cache-Control"]).to match(/no-store/)
    end
  end

  describe "GET /?sample=N (no-JavaScript fallback)" do
    it "prefills the textarea with the sample" do
      get root_path(sample: 1)

      assert_select "textarea", text: /charged twice/
    end
  end

  describe "POST /analyze" do
    context "with valid text" do
      it "sends only the text to the provider and renders three cards" do
        provider = provider_double(billing_json)
        use_provider(provider)

        post analyze_path, params: { decision: { text: valid_text } }

        expect(response).to have_http_status(:ok)
        expect(provider).to have_received(:complete).once.with(valid_text, timeout: a_kind_of(Float))
        assert_select ".card", 3
        assert_select "progress.confidence-bar", 3
        assert_select ".badge-urgency-medium", /Medium/
        assert_select ".confidence-text", text: "91% confidence"
        assert_select ".summary", /medium-urgency billing item. The recommended action is review/
        assert_select ".low-confidence", 1 # the action decision is at 50%
        assert_select ".summary", /Tentative recommendation/
        assert_select "details pre code", /"category"/
        assert_select "textarea", text: valid_text # input preserved
      end

      it "works end to end with the fake provider" do
        post analyze_path, params: { decision: { text: "Production is down, customers cannot pay. Urgent!" } }

        expect(response).to have_http_status(:ok)
        assert_select ".badge-urgency-high"
        assert_select ".badge-action-escalate"
      end

      it "renders identical results for identical input" do
        post analyze_path, params: { decision: { text: valid_text } }
        first = response.body[%r{<section class="results".*</section>}m]
        post analyze_path, params: { decision: { text: valid_text } }

        expect(response.body[%r{<section class="results".*</section>}m]).to eq(first)
      end

      it "does not flag a fully confident result as tentative" do
        post analyze_path, params: { decision: { text: "Production is down, customers cannot pay. Urgent!" } }

        assert_select ".summary", text: /\ARecommendation/
      end
    end

    context "with the TypeSafe provider selected" do
      it "tells the visitor their text goes to TypeSafe AI" do
        with_env("AI_PROVIDER" => "typesafe") do
          get root_path
        end

        expect(response.body).to include("sent to TypeSafe AI")
      end

      it "credits TypeSafe Jev and the answering model on live results" do
        use_provider(provider_double(billing_json))
        post analyze_path, params: { decision: { text: valid_text } }

        assert_select ".source-note", /TypeSafe Jev \(jev-1\.13\.0\)/
      end
    end

    context "with the real TypeSafe adapter (transport stubbed)" do
      let(:transport) { instance_double(Providers::Typesafe::NetHttpTransport) }

      around do |example|
        with_env("AI_PROVIDER" => "typesafe", "TYPESAFE_API_KEY" => "test-key", "TYPESAFE_MODEL" => "jev-test") { example.run }
      end

      before do
        allow(Providers::Typesafe::NetHttpTransport).to receive(:new).and_return(transport)
        allow(transport).to receive(:request).and_return([ 200, JSON.generate(jev_body) ])
      end

      it "makes exactly one outbound request per accepted analysis and renders the answers" do
        post analyze_path, params: { decision: { text: valid_text } }

        expect(transport).to have_received(:request).once
        expect(response).to have_http_status(:ok)
        assert_select ".badge-urgency-high"
        assert_select ".summary", /high-urgency billing item. The recommended action is escalation/
        assert_select ".source-note", /TypeSafe Jev \(jev-1\.13\.0\)/
      end

      it "makes no outbound request for invalid input, samples, or throttled clients" do
        post analyze_path, params: { decision: { text: "short" } }
        post analyze_path, params: { decision: { text: SampleInputs::ALL.first.text } }
        expect(transport).not_to have_received(:request)

        3.times { post analyze_path, params: { decision: { text: valid_text } } }
        post analyze_path, params: { decision: { text: valid_text } }

        expect(response).to have_http_status(:too_many_requests)
        expect(transport).to have_received(:request).exactly(3).times
      end

      it "shows a generic message when TypeSafe rejects the credentials and preserves the text" do
        allow(transport).to receive(:request).and_return([ 401, '{"detail":"bad key test-key"}' ])

        post analyze_path, params: { decision: { text: valid_text } }

        expect(response).to have_http_status(:service_unavailable)
        assert_select ".notice-alert", /temporarily unavailable/
        assert_select "textarea", text: valid_text
        expect(response.body).not_to include("test-key")
      end

      it "shows a timeout message" do
        allow(transport).to receive(:request).and_raise(Net::ReadTimeout)

        post analyze_path, params: { decision: { text: valid_text } }

        assert_select ".notice-alert", /too long/
      end

      it "treats a missing key as a safe, generic error" do
        with_env("TYPESAFE_API_KEY" => "") do
          post analyze_path, params: { decision: { text: valid_text } }
        end

        expect(response).to have_http_status(:service_unavailable)
        assert_select ".notice-alert", /temporarily unavailable/
        expect(transport).not_to have_received(:request)
      end
    end

    context "with a built-in sample" do
      it "serves the precomputed result without calling a provider" do
        use_provider(provider_double)
        allow(DecisionAnalyzer).to receive(:call)

        4.times do
          post analyze_path, params: { decision: { text: SampleInputs::ALL.first.text } }
          expect(response).to have_http_status(:ok)
        end

        expect(DecisionAnalyzer).not_to have_received(:call)
        assert_select ".source-note"
      end
    end

    context "with invalid text" do
      it "shows inline validation and never calls the analyzer" do
        allow(DecisionAnalyzer).to receive(:call)

        [ "", "short", "a" * 2001 ].each do |text|
          post analyze_path, params: { decision: { text: text } }

          expect(response).to have_http_status(:unprocessable_content)
          assert_select "#text-error"
          assert_select "textarea[aria-invalid=true]"
        end
        expect(DecisionAnalyzer).not_to have_received(:call)
      end

      it "does not consume live-analysis quota" do
        5.times { post analyze_path, params: { decision: { text: "hi" } } }
        post analyze_path, params: { decision: { text: valid_text } }

        expect(response).to have_http_status(:ok)
      end
    end

    context "when the provider fails" do
      {
        DecisionAnalyzer::TimeoutError => /too long/,
        DecisionAnalyzer::RateLimited => /busy/,
        DecisionAnalyzer::AuthenticationFailed => /temporarily unavailable/,
        DecisionAnalyzer::ProviderError => /temporarily unavailable/
      }.each do |error, message|
        it "shows a friendly message for #{error.name.demodulize} and leaks nothing" do
          provider = provider_double
          allow(provider).to receive(:complete).and_raise(error, "sk-secret-key upstream body")
          use_provider(provider)

          post analyze_path, params: { decision: { text: valid_text } }

          expect(response).to have_http_status(:service_unavailable)
          assert_select ".notice-alert", message
          expect(response.body).not_to match(/sk-secret|upstream body/)
          assert_select "textarea", text: valid_text
        end
      end

      it "treats malformed provider output as a safe error" do
        use_provider(provider_double("{{{ not json"))

        post analyze_path, params: { decision: { text: valid_text } }

        expect(response).to have_http_status(:service_unavailable)
        assert_select ".notice-alert", /couldn't read/
      end

      it "treats an unconfigured provider as a safe error" do
        with_env("AI_PROVIDER" => "") do
          post analyze_path, params: { decision: { text: valid_text } }
        end

        expect(response).to have_http_status(:service_unavailable)
        assert_select ".notice-alert", /temporarily unavailable/
      end
    end

    context "with rate limiting" do
      it "limits live analyses per client and leaves samples and other clients unaffected" do
        3.times do
          post analyze_path, params: { decision: { text: valid_text } }
          expect(response).to have_http_status(:ok)
        end

        post analyze_path, params: { decision: { text: valid_text } }
        expect(response).to have_http_status(:too_many_requests)
        assert_select ".notice-alert", /hourly limit/

        post analyze_path, params: { decision: { text: SampleInputs::ALL.last.text } }
        expect(response).to have_http_status(:ok)

        post analyze_path, params: { decision: { text: valid_text } }, headers: { "REMOTE_ADDR" => "203.0.113.9" }
        expect(response).to have_http_status(:ok)
      end

      it "counts failed provider calls against the quota" do
        provider = provider_double
        allow(provider).to receive(:complete).and_raise(DecisionAnalyzer::ProviderError)
        use_provider(provider)

        3.times { post analyze_path, params: { decision: { text: valid_text } } }
        post analyze_path, params: { decision: { text: valid_text } }

        expect(response).to have_http_status(:too_many_requests)
        expect(provider).to have_received(:complete).exactly(3).times
      end
    end

    it "enforces CSRF protection" do
      with_forgery_protection do
        post analyze_path, params: { decision: { text: valid_text } }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
