# Shared-credential gate. The session holds only an authenticated flag.
module DemoAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_login
    helper_method :logged_in?
  end

  private

  def logged_in?
    session[:authenticated] == true
  end

  def require_login
    redirect_to login_path unless logged_in?
  end

  def credentials_match?(username, password)
    return false unless AppSettings.credentials_configured?

    # Digest first so comparison is constant-time regardless of length; evaluate both.
    user_ok = secure_equal?(username, AppSettings.demo_username)
    pass_ok = secure_equal?(password, AppSettings.demo_password)
    user_ok && pass_ok
  end

  def secure_equal?(given, expected)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(given.to_s),
      Digest::SHA256.hexdigest(expected.to_s)
    )
  end
end
