require "test_helper"

class LoggingTest < ActionDispatch::IntegrationTest
  test "visitor input, passwords, and upstream errors never reach the logs" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    original = Rails.logger
    [ Rails, ActionController::Base ].each { |t| t.logger = logger }

    secret_text = "UNIQUE-VISITOR-TEXT-#{SecureRandom.hex(4)} the invoice looks wrong"
    post login_path, params: { username: "demo-user", password: "demo-pass-123" }
    post analyze_path, params: { decision: { text: secret_text } }
    post analyze_path, params: { decision: { text: "short" } }
    post login_path, params: { username: "someone", password: "hunter2-wrong" }
    delete logout_path

    log = io.string
    assert_includes log, "Processing by DecisionsController#create" # logging is actually active
    refute_includes log, secret_text
    refute_includes log, "UNIQUE-VISITOR-TEXT"
    refute_includes log, "demo-pass-123"
    refute_includes log, "hunter2-wrong"
  ensure
    [ Rails, ActionController::Base ].each { |t| t.logger = original }
  end
end
