require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:generic_error) { "That username or password isn&#39;t correct." }

  describe "POST /login" do
    it "signs in with the shared credentials" do
      sign_in

      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      assert_select "h1"
      expect(session[:authenticated]).to be true
    end

    it "gives the same generic error for a wrong password and a wrong username" do
      post login_path, params: { username: DemoEnvironment::USERNAME, password: "wrong" }
      wrong_password_body = response.body[%r{notice notice-alert.*?</p>}m]
      expect(response).to have_http_status(:unauthorized)

      post login_path, params: { username: "wrong", password: DemoEnvironment::PASSWORD }
      wrong_username_body = response.body[%r{notice notice-alert.*?</p>}m]
      expect(response).to have_http_status(:unauthorized)

      expect(wrong_username_body).to eq(wrong_password_body)
      expect(response.body).to include(generic_error)
      expect(session[:authenticated]).to be_falsey
    end

    it "fails closed when credentials are not configured, even for blank input" do
      with_env("DEMO_USERNAME" => "", "DEMO_PASSWORD" => "") do
        post login_path, params: { username: "", password: "" }
        expect(response).to have_http_status(:unauthorized)

        get root_path
        expect(response).to redirect_to(login_path)
      end
    end

    it "sets an HTTP-only, same-site session cookie" do
      sign_in
      cookie = response.headers["Set-Cookie"]

      expect(cookie).to match(/httponly/i)
      expect(cookie).to match(/samesite=lax/i)
    end

    it "throttles repeated failures, even if the right password follows" do
      3.times { post login_path, params: { username: DemoEnvironment::USERNAME, password: "bad" } }
      expect(response).to have_http_status(:unauthorized)

      sign_in
      expect(response).to have_http_status(:too_many_requests)
      expect(session[:authenticated]).to be_falsey
    end

    it "does not count successful sign-ins toward the failure limit" do
      5.times do
        sign_in
        delete logout_path
      end
      sign_in

      expect(response).to redirect_to(root_path)
    end

    it "does not throttle other client addresses" do
      3.times { post login_path, params: { username: "x", password: "y" } }
      post login_path,
           params: { username: DemoEnvironment::USERNAME, password: DemoEnvironment::PASSWORD },
           headers: { "REMOTE_ADDR" => "203.0.113.7" }

      expect(response).to redirect_to(root_path)
    end
  end

  describe "DELETE /logout" do
    it "clears the session so protected pages redirect again" do
      sign_in
      delete logout_path

      expect(response).to redirect_to(login_path)
      expect(session[:authenticated]).to be_falsey
      get root_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "session fixation" do
    it "calls reset_session when signing in" do
      expect_any_instance_of(SessionsController).to receive(:reset_session).and_call_original

      sign_in
    end
  end
end
