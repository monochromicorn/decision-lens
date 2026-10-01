require "rails_helper"

# Renders unhandled exceptions the way production does (public error page, no details).
RSpec.describe "Unexpected errors", type: :request do
  around do |example|
    env_config = Rails.application.env_config
    saved = env_config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    env_config["action_dispatch.show_exceptions"] = :all
    env_config["action_dispatch.show_detailed_exceptions"] = false
    example.run
  ensure
    env_config.merge!(saved)
  end

  it "shows the generic error page without stack traces, internals, or visitor text" do
    sign_in
    provider = provider_double
    allow(provider).to receive(:complete).and_raise(RuntimeError, "INTERNAL-DETAIL sk-secret-key #{valid_text}")
    use_provider(provider)

    post analyze_path, params: { decision: { text: valid_text } }

    expect(response).to have_http_status(:internal_server_error)
    expect(response.body).to include("We're sorry, but something went wrong")
    expect(response.body).not_to match(/INTERNAL-DETAIL|sk-secret-key|invoice total|\.rb:\d+|app\/|Backtrace|RuntimeError/)
  end

  it "shows the generic 404 page for unknown routes" do
    get "/definitely-not-a-route"

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to match(/Routing Error|Rails\.root|\.rb:\d+/)
  end
end
