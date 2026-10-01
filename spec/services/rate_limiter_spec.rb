require "rails_helper"

RSpec.describe RateLimiter do
  it "throttles after the limit and is keyed per client" do
    limiter = described_class.new(name: "t", limit: 2, period: 1.hour)

    expect(limiter.throttled?("a")).to be false
    2.times { limiter.hit("a") }

    expect(limiter.throttled?("a")).to be true
    expect(limiter.throttled?("b")).to be false
  end

  it "stops throttling when the window expires" do
    limiter = described_class.new(name: "t", limit: 1, period: 1.minute)
    limiter.hit("a")
    expect(limiter.throttled?("a")).to be true

    travel_to(2.minutes.from_now) do
      expect(limiter.throttled?("a")).to be false
    end
  end
end
