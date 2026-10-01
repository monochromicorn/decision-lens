require "rails_helper"

RSpec.describe "Health check", type: :request do
  it "is public and returns success" do
    get rails_health_check_path

    expect(response).to have_http_status(:ok)
  end
end
