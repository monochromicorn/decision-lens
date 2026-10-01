require "rails_helper"

# The rate limiters key on request.remote_ip. These specs document that arbitrary
# forwarded headers cannot be used to dodge or to poison them.
RSpec.describe "Client IP handling", type: :request do
  def failed_login(headers = {})
    post login_path, params: { username: "nope", password: "nope" }, headers: headers
  end

  # Koyeb appends the connecting IP to the END of X-Forwarded-For and documents that last
  # entry as the only one it certifies. Rails takes the rightmost entry that is not a trusted
  # proxy, so anything a client forges to its left never matters.
  it "keys on the rightmost X-Forwarded-For entry, never on forged entries to its left" do
    3.times { |i| failed_login("REMOTE_ADDR" => "198.51.100.20", "X-Forwarded-For" => "203.0.113.#{i}, 198.51.100.7") }

    failed_login("REMOTE_ADDR" => "198.51.100.20", "X-Forwarded-For" => "203.0.113.99, 198.51.100.7")

    expect(response).to have_http_status(:too_many_requests)
  end

  it "uses the rightmost untrusted address behind a private proxy, ignoring spoofed earlier entries" do
    3.times { |i| failed_login("REMOTE_ADDR" => "10.0.0.1", "X-Forwarded-For" => "6.6.6.#{i}, 198.51.100.7") }

    failed_login("REMOTE_ADDR" => "10.0.0.1", "X-Forwarded-For" => "7.7.7.7, 198.51.100.7")
    expect(response).to have_http_status(:too_many_requests)

    failed_login("REMOTE_ADDR" => "10.0.0.1", "X-Forwarded-For" => "198.51.100.8")
    expect(response).to have_http_status(:unauthorized) # a different real client has its own allowance
  end

  it "does not treat a public peer's claim of being a proxy as trusted" do
    failed_login("REMOTE_ADDR" => "198.51.100.20", "X-Forwarded-For" => "10.0.0.1")
    expect(response).to have_http_status(:unauthorized)

    ip = nil
    allow(RateLimiter).to receive(:new).and_wrap_original do |original, **kwargs|
      original.call(**kwargs).tap { |limiter| allow(limiter).to receive(:hit) { |key| ip = key } }
    end
    failed_login("REMOTE_ADDR" => "198.51.100.20", "X-Forwarded-For" => "10.0.0.1")

    expect(ip).to eq("198.51.100.20")
  end
end
