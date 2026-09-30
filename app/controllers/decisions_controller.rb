class DecisionsController < ApplicationController
  before_action :prevent_caching

  ERROR_MESSAGES = {
    DecisionAnalyzer::TimeoutError => "The AI provider took too long to respond. Please try again in a moment.",
    DecisionAnalyzer::RateLimited => "The AI provider is busy right now. Please try again shortly.",
    DecisionAnalyzer::InvalidResponse => "The AI provider returned something we couldn't read. Please try again."
  }.freeze
  GENERIC_ERROR = "Analysis is temporarily unavailable. Please try again later; the built-in samples still work."

  def new
    sample = SampleInputs::ALL[params[:sample].to_i] if params[:sample].present?
    @input = DecisionInput.new(sample&.text)
  end

  def create
    @input = DecisionInput.new(params.dig(:decision, :text))
    return render :new, status: :unprocessable_content unless @input.valid?

    if (sample = SampleInputs.find_by_text(@input.text))
      @result = sample.result
      @source = :sample
      return render :new
    end

    return render_error("You've reached the hourly limit for live analyses. Try a built-in sample or come back later.", :too_many_requests) if analyses.throttled?(request.remote_ip)

    analyses.hit(request.remote_ip) # counted before the call: failed calls can still cost money
    @result = DecisionAnalyzer.call(@input.text)
    @source = :live
    render :new
  rescue DecisionAnalyzer::Error => e
    Rails.logger.warn("Decision analysis failed: #{e.class}") # never log input or upstream bodies
    render_error(ERROR_MESSAGES.fetch(e.class, GENERIC_ERROR), :service_unavailable)
  end

  private

  def analyses
    RateLimiter.new(name: "analyses", limit: AppSettings.analyses_per_hour, period: 1.hour)
  end

  def render_error(message, status)
    flash.now[:alert] = message
    render :new, status: status
  end

  def prevent_caching
    response.headers["Cache-Control"] = "no-store"
  end
end
