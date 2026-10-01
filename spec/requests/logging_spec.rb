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

  it "keeps visitor text, the API key and upstream bodies out of logs through the TypeSafe adapter" do
    io = StringIO.new
    original = Rails.logger
    [ Rails, ActionController::Base ].each { |target| target.logger = ActiveSupport::Logger.new(io) }
    transport = instance_double(Providers::Typesafe::NetHttpTransport)
    allow(Providers::Typesafe::NetHttpTransport).to receive(:new).and_return(transport)

    secret_text = "UNIQUE-VISITOR-TEXT-#{SecureRandom.hex(4)} the invoice looks wrong"
    with_env("AI_PROVIDER" => "typesafe", "TYPESAFE_API_KEY" => "KEY-SHOULD-NEVER-APPEAR", "TYPESAFE_MODEL" => "jev-test") do
      sign_in
      allow(transport).to receive(:request).and_return([ 200, JSON.generate(jev_body) ])
      post analyze_path, params: { decision: { text: secret_text } } # success path
      allow(transport).to receive(:request).and_return([ 500, "UPSTREAM-BODY #{secret_text}" ])
      post analyze_path, params: { decision: { text: secret_text } } # failure path
      allow(transport).to receive(:request).and_return([ 422, validation_error_body ])
      post analyze_path, params: { decision: { text: secret_text } } # validation path
    end

    log = io.string
    expect(log).to include("[typesafe] ok model=jev-1.13.0 input_tokens=120")
    expect(log).to include("[typesafe] request failed: HTTP 500")
    expect(log).not_to include("UNIQUE-VISITOR-TEXT")
    expect(log).not_to include("KEY-SHOULD-NEVER-APPEAR")
    expect(log).not_to include("UPSTREAM-BODY")
    expect(log).not_to include("VISITOR-TEXT-ECHO")
  ensure
    [ Rails, ActionController::Base ].each { |target| target.logger = original }
  end

  it "filters sensitive parameter names from request logs" do
    io = StringIO.new
    original = Rails.logger
    [ Rails, ActionController::Base ].each { |target| target.logger = ActiveSupport::Logger.new(io) }

    post login_path, params: { username: "u", password: "PW-SHOULD-NOT-LOG", message: "MSG-SHOULD-NOT-LOG",
                               input: "INPUT-SHOULD-NOT-LOG", api_key: "APIKEY-SHOULD-NOT-LOG",
                               authorization: "AUTH-SHOULD-NOT-LOG" }

    log = io.string
    expect(log).to include("Parameters:")
    %w[PW MSG INPUT APIKEY AUTH].each { |marker| expect(log).not_to include("#{marker}-SHOULD-NOT-LOG") }
  ensure
    [ Rails, ActionController::Base ].each { |target| target.logger = original }
  end
end
