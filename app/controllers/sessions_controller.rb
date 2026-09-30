class SessionsController < ApplicationController
  skip_before_action :require_login
  before_action :redirect_if_logged_in, only: %i[new create]

  def new
  end

  def create
    return render_throttled if failed_logins.throttled?(request.remote_ip)

    if credentials_match?(params[:username], params[:password])
      reset_session # prevents session fixation
      session[:authenticated] = true
      redirect_to root_path
    else
      failed_logins.hit(request.remote_ip)
      flash.now[:alert] = "That username or password isn't correct."
      render :new, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "You've been signed out."
  end

  private

  # Limit is read at request time so configuration and tests can change it.
  def failed_logins
    RateLimiter.new(
      name: "login-failures",
      limit: AppSettings.failed_logins_per_15_minutes,
      period: 15.minutes
    )
  end

  def render_throttled
    flash.now[:alert] = "Too many failed attempts. Please wait a few minutes and try again."
    render :new, status: :too_many_requests
  end

  def redirect_if_logged_in
    redirect_to root_path if logged_in?
  end
end
