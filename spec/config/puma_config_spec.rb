require "rails_helper"
require "puma/configuration"

RSpec.describe "Puma configuration" do
  def load_options(env = {})
    with_env({ "PORT" => nil, "RAILS_MAX_THREADS" => nil, "WEB_CONCURRENCY" => nil }.merge(env)) do
      conf = Puma::Configuration.new({}, {}, ENV.to_h) { |user| user.load(Rails.root.join("config/puma.rb").to_s) }
      conf.clamp
      %i[min_threads max_threads workers binds].to_h { |key| [ key, conf.options[key] ] }
    end
  end

  it "defaults to two threads in single-process mode" do
    options = load_options

    expect(options[:min_threads]).to eq(2)
    expect(options[:max_threads]).to eq(2)
    expect(options[:workers]).to eq(0)
  end

  it "takes the thread count from RAILS_MAX_THREADS" do
    options = load_options("RAILS_MAX_THREADS" => "3")

    expect([ options[:min_threads], options[:max_threads] ]).to eq([ 3, 3 ])
  end

  it "stays single-process even when the platform sets WEB_CONCURRENCY" do
    expect(load_options("WEB_CONCURRENCY" => "4")[:workers]).to eq(0)
  end

  it "listens on all interfaces on the port named by PORT" do
    expect(load_options("PORT" => "8123")[:binds]).to eq([ "tcp://0.0.0.0:8123" ])
  end
end
