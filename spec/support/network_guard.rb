# Any example that reaches the real HTTP transport fails loudly, so a protected path
# that accidentally calls TypeSafe can never spend credits. Only examples tagged
# :loopback (which talk to 127.0.0.1) are exempt.
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:loopback]

    allow_any_instance_of(Providers::Typesafe::NetHttpTransport) # rubocop:disable RSpec/AnyInstance
      .to receive(:request).and_raise("Real HTTP transport used in a spec; inject a transport double")
  end
end
