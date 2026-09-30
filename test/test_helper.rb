ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    TEST_ENV = {
      "DEMO_USERNAME" => "demo-user",
      "DEMO_PASSWORD" => "demo-pass-123",
      "AI_PROVIDER" => "fake",
      "ANALYSES_PER_HOUR" => "3",
      "FAILED_LOGINS_PER_15_MINUTES" => "3"
    }.freeze

    setup do
      @original_env = ENV.to_h
      TEST_ENV.each { |key, value| ENV[key] = value }
      RateLimiter.reset!
    end

    teardown do
      ENV.replace(@original_env)
    end

    def with_env(overrides)
      saved = overrides.keys.to_h { |key| [ key, ENV[key] ] }
      overrides.each { |key, value| ENV[key] = value }
      yield
    ensure
      saved.each { |key, value| ENV[key] = value }
    end
  end
end

class ActionDispatch::IntegrationTest
  # Routes DecisionAnalyzer.call through a test provider for one block.
  def stub_analyzer(provider)
    original = DecisionAnalyzer.method(:call)
    DecisionAnalyzer.define_singleton_method(:call) { |text, **| new(provider: provider).call(text) }
    yield
  ensure
    DecisionAnalyzer.define_singleton_method(:call, original)
  end

  def sign_in
    post login_path, params: { username: "demo-user", password: "demo-pass-123" }
  end

  def valid_text
    "The invoice total looks wrong and I would like someone to check it this week."
  end
end

# Replaces the provider for one block so tests never reach a real AI service.
class RecordingProvider
  attr_reader :calls

  def initialize(response = nil, &block)
    @response = response
    @block = block
    @calls = []
  end

  def complete(text, timeout: nil)
    @calls << text
    @block ? @block.call(text) : @response
  end
end
