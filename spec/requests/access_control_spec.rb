require "rails_helper"

RSpec.describe "Access control", type: :request do
  describe "anonymous visitors" do
    it "are redirected from the Decision Lens page" do
      get root_path

      expect(response).to redirect_to(login_path)
    end

    it "are redirected from the analysis endpoint" do
      post analyze_path, params: { decision: { text: valid_text } }

      expect(response).to redirect_to(login_path)
    end

    it "can never invoke the analyzer or build a provider" do
      allow(DecisionAnalyzer).to receive(:call).and_call_original
      allow(DecisionAnalyzer).to receive(:new).and_call_original
      allow(Providers::Fake).to receive(:new).and_call_original

      post analyze_path, params: { decision: { text: valid_text } }
      post analyze_path, params: { decision: { text: SampleInputs::ALL.first.text } }

      expect(DecisionAnalyzer).not_to have_received(:call)
      expect(DecisionAnalyzer).not_to have_received(:new)
      expect(Providers::Fake).not_to have_received(:new)
    end

    it "do not consume live-analysis quota" do
      5.times { post analyze_path, params: { decision: { text: valid_text } } }
      sign_in
      post analyze_path, params: { decision: { text: valid_text } }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the login page" do
    it "is public" do
      get login_path

      expect(response).to have_http_status(:ok)
      assert_select "form[action='#{login_path}']"
    end

    it "redirects signed-in visitors to the app" do
      sign_in
      get login_path

      expect(response).to redirect_to(root_path)
    end
  end
end
