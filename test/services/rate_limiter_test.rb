require "test_helper"

class RateLimiterTest < ActiveSupport::TestCase
  test "throttles after the limit and is keyed per client" do
    limiter = RateLimiter.new(name: "t", limit: 2, period: 1.hour)

    refute limiter.throttled?("a")
    2.times { limiter.hit("a") }
    assert limiter.throttled?("a")
    refute limiter.throttled?("b")
  end

  test "window expires" do
    limiter = RateLimiter.new(name: "t", limit: 1, period: 1.minute)
    limiter.hit("a")
    assert limiter.throttled?("a")

    travel 2.minutes do
      refute limiter.throttled?("a")
    end
  end
end
