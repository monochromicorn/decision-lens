require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "anonymous visitors are redirected from every protected page" do
    get root_path
    assert_redirected_to login_path

    post analyze_path, params: { decision: { text: valid_text } }
    assert_redirected_to login_path
  end

  test "health check and login page are public" do
    get rails_health_check_path
    assert_response :success

    get login_path
    assert_response :success
    assert_select "form[action='#{login_path}']"
  end

  test "valid credentials sign in" do
    sign_in
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_select "h1"
    assert_equal true, session[:authenticated]
  end

  test "wrong username and wrong password produce the same generic error" do
    post login_path, params: { username: "demo-user", password: "wrong" }
    wrong_password = response.body[/notice-alert[^<]*<|notice notice-alert.*?<\/p>/m]
    assert_response :unauthorized

    post login_path, params: { username: "wrong", password: "demo-pass-123" }
    wrong_user = response.body[/notice-alert[^<]*<|notice notice-alert.*?<\/p>/m]
    assert_response :unauthorized

    assert_equal wrong_password, wrong_user
    assert_includes response.body, "That username or password isn&#39;t correct."
    assert_not session[:authenticated]
  end

  test "login fails closed when credentials are not configured" do
    with_env("DEMO_USERNAME" => "", "DEMO_PASSWORD" => "") do
      post login_path, params: { username: "", password: "" }
      assert_response :unauthorized
      get root_path
      assert_redirected_to login_path
    end
  end

  test "sign out clears the session" do
    sign_in
    delete logout_path
    assert_redirected_to login_path

    get root_path
    assert_redirected_to login_path
  end

  test "signed in visitors skip the login page" do
    sign_in
    get login_path
    assert_redirected_to root_path
  end

  test "repeated failed sign-ins are throttled, even with the right password afterwards" do
    3.times { post login_path, params: { username: "demo-user", password: "bad" } }
    assert_response :unauthorized

    post login_path, params: { username: "demo-user", password: "demo-pass-123" }
    assert_response :too_many_requests
    assert_not session[:authenticated]
  end

  test "successful logins do not count against the failure limit" do
    5.times do
      sign_in
      delete logout_path
    end
    sign_in
    assert_redirected_to root_path
  end

  test "session cookie is http-only and same-site" do
    sign_in
    cookie = response.headers["Set-Cookie"]
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
  end
end
