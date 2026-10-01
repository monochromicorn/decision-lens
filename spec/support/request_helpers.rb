module RequestHelpers
  VALID_TEXT = "The invoice total looks wrong and I would like someone to check it this week.".freeze

  def sign_in
    post login_path, params: { username: DemoEnvironment::USERNAME, password: DemoEnvironment::PASSWORD }
  end

  def valid_text = VALID_TEXT

  # Routes DecisionAnalyzer.call through the given provider so no real provider is built.
  def use_provider(provider)
    allow(DecisionAnalyzer).to receive(:call) do |text|
      DecisionAnalyzer.new(provider: provider).call(text)
    end
  end

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
