require "test_helper"

class DecisionsTest < ActionDispatch::IntegrationTest
  setup { sign_in }

  def good_json
    JSON.generate(
      category: { value: "billing", confidence: 0.9 },
      urgency: { value: "medium", confidence: 0.8 },
      action: { value: "review", confidence: 0.5 },
      summary: "Check the invoice."
    )
  end

  test "landing page shows the form, samples, privacy note and empty state" do
    get root_path
    assert_response :success
    assert_select "label[for=decision_text]"
    assert_select "textarea#decision_text"
    assert_select "a.sample", 3
    assert_select "form button", text: "Analyze decision"
    assert_select "button", text: "Sign out"
    assert_match(/external AI provider/, response.body)
    assert_select ".empty-state"
    assert_select "#results", 0
  end

  test "sample links prefill the text without JavaScript" do
    get root_path(sample: 1)
    assert_select "textarea", text: /charged twice/
  end

  test "analyzes custom text and renders three cards, confidence and JSON" do
    provider = RecordingProvider.new(good_json)
    stub_analyzer(provider) do
      post analyze_path, params: { decision: { text: valid_text } }
    end

    assert_response :success
    assert_equal [ valid_text ], provider.calls
    assert_select ".card", 3
    assert_select "progress.confidence-bar", 3
    assert_select ".badge-urgency-medium", /Medium/
    assert_select ".confidence-text", text: "90% confidence"
    assert_select ".low-confidence", 1 # action is at 50%
    assert_select ".summary", /Tentative recommendation/
    assert_select "details pre code", /"category"/
    assert_select "textarea", text: valid_text # input preserved
  end

  test "works end to end with the fake provider" do
    post analyze_path, params: { decision: { text: "Production is down, customers cannot pay. Urgent!" } }
    assert_response :success
    assert_select ".badge-urgency-high"
    assert_select ".badge-action-escalate"
  end

  test "built-in samples are served without calling the provider or using quota" do
    provider = RecordingProvider.new { raise "provider must not be called" }
    stub_analyzer(provider) do
      4.times do
        post analyze_path, params: { decision: { text: SampleInputs::ALL.first.text } }
        assert_response :success
      end
    end

    assert_empty provider.calls
    assert_select ".source-note"
  end

  test "invalid input shows inline validation and makes no AI call" do
    provider = RecordingProvider.new { raise "provider must not be called" }
    stub_analyzer(provider) do
      [ "", "short", "a" * 2001 ].each do |text|
        post analyze_path, params: { decision: { text: text } }
        assert_response :unprocessable_content
        assert_select "#text-error"
        assert_select "textarea[aria-invalid=true]"
      end
    end
    assert_empty provider.calls
  end

  test "provider failures show friendly messages and leak nothing" do
    {
      DecisionAnalyzer::TimeoutError => /too long/,
      DecisionAnalyzer::RateLimited => /busy/,
      DecisionAnalyzer::AuthenticationFailed => /temporarily unavailable/,
      DecisionAnalyzer::ProviderError => /temporarily unavailable/
    }.each do |error, pattern|
      RateLimiter.reset!
      provider = RecordingProvider.new { raise error, "sk-secret-key upstream body" }
      stub_analyzer(provider) { post analyze_path, params: { decision: { text: valid_text } } }

      assert_response :service_unavailable
      assert_select ".notice-alert", pattern
      assert_no_match(/sk-secret|upstream body/, response.body)
      assert_select "textarea", text: valid_text
    end
  end

  test "malformed provider output is a safe error" do
    stub_analyzer(RecordingProvider.new("{{{ not json")) do
      post analyze_path, params: { decision: { text: valid_text } }
    end
    assert_response :service_unavailable
    assert_select ".notice-alert", /couldn't read/
  end

  test "unconfigured provider in production-like setting is a safe error" do
    with_env("AI_PROVIDER" => "") do
      post analyze_path, params: { decision: { text: valid_text } }
    end
    assert_response :service_unavailable
    assert_select ".notice-alert", /temporarily unavailable/
  end

  test "live analyses are rate limited per client" do
    3.times do
      post analyze_path, params: { decision: { text: valid_text } }
      assert_response :success
    end

    post analyze_path, params: { decision: { text: valid_text } }
    assert_response :too_many_requests
    assert_select ".notice-alert", /hourly limit/

    # A different client address is unaffected; samples still work for the limited one.
    post analyze_path, params: { decision: { text: SampleInputs::ALL.last.text } }
    assert_response :success
    post analyze_path, params: { decision: { text: valid_text } }, headers: { "REMOTE_ADDR" => "203.0.113.9" }
    assert_response :success
  end

  test "invalid input does not consume live analyses" do
    5.times { post analyze_path, params: { decision: { text: "hi" } } }
    post analyze_path, params: { decision: { text: valid_text } }
    assert_response :success
  end

  test "CSRF protection is enforced" do
    with_forgery_protection do
      post analyze_path, params: { decision: { text: valid_text } }
      assert_response :unprocessable_content
    end
  end

  test "responses are not cacheable" do
    get root_path
    assert_match(/no-store/, response.headers["Cache-Control"])
  end

  private

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
