require "rails_helper"

# Exercises the real Net::HTTP transport against a loopback-only server (127.0.0.1).
# Nothing leaves the machine and no TypeSafe host is contacted.
RSpec.describe "Providers::Typesafe over HTTP (loopback)", :loopback do
  let(:servers) { [] }

  after { servers.each(&:stop) }

  def start_server(**options)
    LoopbackServer.new(**options).tap { |server| servers << server }
  end

  def provider_for(server)
    Providers::Typesafe.new(api_key: "loopback-key", model: "jev-test", base_url: server.url)
  end

  it "sends one authenticated JSON POST and parses the answer" do
    server = start_server(body: JSON.generate(jev_body))

    result = DecisionAnalyzer.new(provider: provider_for(server)).call("I was charged twice, please fix it")

    expect(server.requests.length).to eq(1)
    request = server.requests.first
    expect(request.method).to eq("POST")
    expect(request.path).to eq("/v1/systemone")
    expect(request.headers["authorization"]).to eq("Bearer loopback-key")
    expect(request.headers["content-type"]).to eq("application/json")
    expect(JSON.parse(request.body)["state"]).to eq("I was charged twice, please fix it")
    expect(result).to include(provider: "typesafe", model: "jev-1.13.0")
  end

  it "makes no retry after a server error" do
    server = start_server(status: 500, body: "{}")

    expect { DecisionAnalyzer.new(provider: provider_for(server)).call("x" * 20) }
      .to raise_error(DecisionAnalyzer::ProviderError)
    expect(server.requests.length).to eq(1)
  end

  it "times out when the server is too slow, without retrying" do
    server = start_server(body: JSON.generate(jev_body), delay: 1.0)

    with_env("AI_TIMEOUT_SECONDS" => "0.2") do
      expect { DecisionAnalyzer.new(provider: provider_for(server)).call("x" * 20) }
        .to raise_error(DecisionAnalyzer::TimeoutError)
    end
    expect(server.requests.length).to eq(1)
  end

  it "reports a refused connection as a provider error" do
    server = start_server
    provider = provider_for(server)
    server.stop

    expect { DecisionAnalyzer.new(provider: provider).call("x" * 20) }.to raise_error(DecisionAnalyzer::ProviderError)
  end
end
