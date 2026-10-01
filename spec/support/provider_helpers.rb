module ProviderHelpers
  # A verifying double: it can only respond to what a real provider responds to,
  # so a provider whose interface drifts from Providers::Fake fails these specs.
  def provider_double(response = nil)
    instance_double(Providers::Fake).tap do |provider|
      allow(provider).to receive(:complete).and_return(response) unless response.nil?
    end
  end
end

RSpec.configure do |config|
  config.include ProviderHelpers, type: :request
  config.include ProviderHelpers, type: :service
end
