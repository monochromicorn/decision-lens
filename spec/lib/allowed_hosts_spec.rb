require "rails_helper"

RSpec.describe AllowedHosts do
  describe ".parse" do
    it "accepts exact hostnames, trims whitespace, lower-cases, and removes duplicates" do
      result = described_class.parse(" Lens.Example.com , www.example.com,WWW.example.com ")

      expect(result.hosts).to eq(%w[lens.example.com www.example.com])
      expect(result.rejected_count).to eq(0)
      expect(result).to be_configured
    end

    it "accepts a single-label name such as localhost" do
      expect(described_class.parse("localhost").hosts).to eq([ "localhost" ])
    end

    [
      [ "an unrestricted wildcard", ".*" ],
      [ "a wildcard pattern", "*.example.com" ],
      [ "a lone asterisk", "*" ],
      [ "a leading-dot subdomain match", ".example.com" ],
      [ "a URL with a scheme", "https://lens.example.com" ],
      [ "a host with a port", "lens.example.com:3000" ],
      [ "a host with a path", "lens.example.com/path" ],
      [ "an IPv4 address", "203.0.113.7" ],
      [ "a trailing dot", "lens.example.com." ],
      [ "an underscore", "my_app.example.com" ],
      [ "a leading hyphen", "-lens.example.com" ],
      [ "a space inside", "lens example.com" ],
      [ "an empty label", "lens..example.com" ],
      [ "a label over 63 characters", "#{'a' * 64}.example.com" ],
      [ "a name over 253 characters", ([ "a" * 60 ] * 5).join(".") + ".example.com" ],
      [ "a regular-expression-looking value", "/.*/" ]
    ].each do |label, value|
      it "rejects #{label}" do
        result = described_class.parse(value)

        expect(result.hosts).to be_empty
        expect(result.rejected_count).to eq(1)
      end
    end

    it "keeps valid entries and counts the rejected ones" do
      result = described_class.parse("lens.example.com,*.example.com,,https://x.test")

      expect(result.hosts).to eq([ "lens.example.com" ])
      expect(result.rejected_count).to eq(3)
    end

    it "treats nil, empty, and blank configuration as nothing configured" do
      [ nil, "", "   ", ",,," ].each do |raw|
        expect(described_class.parse(raw).hosts).to be_empty
        expect(described_class.parse(raw)).not_to be_configured
      end
    end
  end

  describe ".for_rails" do
    it "returns the parsed hosts" do
      expect(described_class.for_rails("lens.example.com")).to eq([ "lens.example.com" ])
    end

    it "falls back to a deny-all placeholder, never to an open list" do
      [ nil, "", ".*", "*.example.com", "https://lens.example.com" ].each do |raw|
        expect(described_class.for_rails(raw)).to eq([ described_class::DENY_ALL ])
      end
    end
  end

  # Exercises the real Rack middleware with the same hosts list and exclusion production uses.
  describe "as host authorization middleware" do
    let(:app) { ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] } }

    def status_for(raw_hosts, host:, path: "/")
      hosts = described_class.for_rails(raw_hosts)
      middleware = ActionDispatch::HostAuthorization.new(app, hosts, exclude: described_class.health_check_exclusion)
      middleware.call(Rack::MockRequest.env_for("http://#{host}#{path}", "HTTP_HOST" => host)).first
    end

    it "serves every configured hostname" do
      raw = "lens.example.com,www.example.com"

      expect(status_for(raw, host: "www.example.com")).to eq(200)
      expect(status_for(raw, host: "lens.example.com")).to eq(200)
      expect(status_for(raw, host: "LENS.example.com")).to eq(200)
    end

    it "serves a configured hostname when the request includes a port" do
      expect(status_for("lens.example.com", host: "lens.example.com:8000")).to eq(200)
    end

    it "also checks X-Forwarded-Host, which the proxy sets to the requested domain" do
      hosts = described_class.for_rails("lens.example.com")
      middleware = ActionDispatch::HostAuthorization.new(app, hosts, exclude: described_class.health_check_exclusion)
      env = lambda do |forwarded|
        Rack::MockRequest.env_for("http://lens.example.com/", "HTTP_HOST" => "lens.example.com", "HTTP_X_FORWARDED_HOST" => forwarded)
      end

      expect(middleware.call(env.call("lens.example.com")).first).to eq(200)
      expect(middleware.call(env.call("evil.test")).first).to eq(403)
    end

    it "rejects unknown hostnames and look-alikes" do
      raw = "lens.example.com"

      [ "evil.test", "example.com", "x.lens.example.com", "lens.example.com.evil.test", "lens-example.com" ].each do |host|
        expect(status_for(raw, host: host)).to eq(403), host
      end
    end

    it "refuses everything except /up when nothing valid is configured" do
      [ nil, "", ".*", "*" ].each do |raw|
        expect(status_for(raw, host: "lens.example.com")).to eq(403)
        expect(status_for(raw, host: "anything.test")).to eq(403)
        expect(status_for(raw, host: "10.0.0.5", path: "/up")).to eq(200)
      end
    end

    it "keeps /up reachable under any Host header, and only /up" do
      raw = "lens.example.com"

      expect(status_for(raw, host: "10.1.2.3:8000", path: "/up")).to eq(200)
      expect(status_for(raw, host: "10.1.2.3:8000", path: "/up/extra")).to eq(403)
      expect(status_for(raw, host: "10.1.2.3:8000", path: "/login")).to eq(403)
    end

    it "does not reveal the allowed hosts in the refusal body" do
      middleware = ActionDispatch::HostAuthorization.new(
        app, described_class.for_rails("lens.example.com"), exclude: described_class.health_check_exclusion
      )
      _status, _headers, body = middleware.call(Rack::MockRequest.env_for("http://evil.test/", "HTTP_HOST" => "evil.test"))

      expect(body.each.to_a.join).not_to include("lens.example.com")
    end
  end
end
