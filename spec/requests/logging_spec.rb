require "rails_helper"

RSpec.describe "Logging", type: :request do
  it "never records visitor text, passwords, or upstream error text" do
    io = StringIO.new
    original = Rails.logger
    [ Rails, ActionController::Base ].each { |target| target.logger = ActiveSupport::Logger.new(io) }

    provider = provider_double
    allow(provider).to receive(:complete).and_raise(DecisionAnalyzer::ProviderError, "UPSTREAM-BODY-xyz")
    use_provider(provider)

    secret_text = "UNIQUE-VISITOR-TEXT-#{SecureRandom.hex(4)} the invoice looks wrong"
    sign_in
    post analyze_path, params: { decision: { text: secret_text } } # provider failure path
    post analyze_path, params: { decision: { text: "short" } }
    post login_path, params: { username: "someone", password: "hunter2-wrong" }
    delete logout_path

    log = io.string
    expect(log).to include("Processing by DecisionsController#create") # logging is actually active
    expect(log).to include("Decision analysis failed: DecisionAnalyzer::ProviderError")
    expect(log).not_to include("UNIQUE-VISITOR-TEXT")
    expect(log).not_to include(DemoEnvironment::PASSWORD)
    expect(log).not_to include("hunter2-wrong")
    expect(log).not_to include("UPSTREAM-BODY")
  ensure
    [ Rails, ActionController::Base ].each { |target| target.logger = original }
  end
end
