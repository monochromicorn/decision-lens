require "net/http"
require "json"
require "uri"

module Providers
  # TypeSafe AI "Jev" adapter. One POST /v1/systemone request carries all three
  # questions (Choice, Score, Choice) and is translated into the analyzer's
  # provider contract. Authority: https://api.typesafe.ai/openapi.json
  #
  # Safety rules enforced here:
  #   * exactly one HTTP request per #complete, never retried
  #   * the API key only travels in the Authorization header, over HTTPS
  #   * visitor text, headers and response bodies are never logged or put in errors
  class Typesafe
    NAME = "typesafe"

    CATEGORY_CRITERIA = {
      "support" => "The sender reports something broken or not working (an error, bug, crash, or outage) or asks for help using the product.",
      "sales" => "The sender is a prospect or customer asking about pricing, plans, quotes, demos, or buying or upgrading.",
      "billing" => "The message is about money already charged or owed: charges, invoices, refunds, payments, or subscription billing.",
      "feedback" => "The sender shares praise, a complaint about their experience, or a product suggestion, without asking for something to be fixed.",
      "security" => "The message reports or fears unauthorized access, a compromised account, phishing, a data breach, or leaked credentials.",
      "other" => "The message does not clearly fit any other category: unrelated, ambiguous, or too vague to tell."
    }.freeze

    # Position in this array is the score (0, 1, 2) and maps to DecisionAnalyzer::URGENCIES.
    URGENCY_CRITERIA = [
      "Nothing is time-sensitive. A routine, informational, or positive message that can wait several days.",
      "Something needs handling soon, within a day or two. Limited impact, or a workaround exists.",
      "Needs attention today. An active outage, money being lost, a security risk, or an explicit demand for immediate help."
    ].freeze

    ACTION_CRITERIA = {
      "automate" => "A routine message where a standard templated reply or automatic handling is enough and no human judgment is needed.",
      "review" => "A person should read it and decide before anything is sent or changed: it needs verification, judgment, or is ambiguous.",
      "escalate" => "Needs prompt attention from a senior person or specialist team: an outage, security incident, legal or financial risk, or severe frustration."
    }.freeze

    QUESTIONS = {
      "category" => {
        "type" => "choice",
        "instructions" => "What kind of message is this?",
        "criteria" => CATEGORY_CRITERIA
      },
      "urgency" => {
        "type" => "score",
        "instructions" => "How urgently does this message need a response?",
        "criteria" => URGENCY_CRITERIA
      },
      "action" => {
        "type" => "choice",
        "instructions" => "What should the team do with this message?",
        "criteria" => ACTION_CRITERIA
      }
    }.freeze

    # Real HTTP. Injectable so specs never touch the network. No retries, and every
    # phase (connect, write, read) is bounded by the timeout.
    class NetHttpTransport
      def request(method, uri, headers:, timeout:, body: nil)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = http.write_timeout = timeout
        http.max_retries = 0

        request = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri.request_uri, headers)
        request.body = body if body
        response = http.request(request)
        [ response.code.to_i, response.body.to_s ]
      end
    end

    def initialize(api_key: AppSettings.typesafe_api_key, model: AppSettings.typesafe_model,
                   base_url: AppSettings.typesafe_base_url, transport: NetHttpTransport.new)
      raise DecisionAnalyzer::ConfigurationError, "TYPESAFE_API_KEY is not set" if api_key.blank?
      raise DecisionAnalyzer::ConfigurationError, "TYPESAFE_MODEL is not set" if model.blank?

      @api_key = api_key
      @model = model
      @base_uri = secure_base_uri(base_url)
      @transport = transport
    end

    def complete(text, timeout: AppSettings.ai_timeout)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      payload = JSON.generate(state: text, model: @model, questions: QUESTIONS)
      body = checked_body(:post, "/v1/systemone", payload, timeout)
      result = translate(parse(body))
      Rails.logger.info(
        "[typesafe] ok model=#{result[:model]} input_tokens=#{result.dig(:usage, :input_tokens)} " \
        "duration_ms=#{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round}"
      )
      result
    end

    # GET /v1/models: names and release dates only. Used by `rake typesafe:models`.
    def list_models(timeout: AppSettings.ai_timeout)
      models = parse(checked_body(:get, "/v1/models", nil, timeout))["models"]
      raise DecisionAnalyzer::InvalidResponse, "models missing" unless models.is_a?(Array)

      models.filter_map do |entry|
        { name: entry["name"], release_date: entry["release_date"] } if entry.is_a?(Hash)
      end
    end

    private

    def secure_base_uri(base_url)
      uri = URI.parse(base_url.to_s)
      loopback = %w[localhost 127.0.0.1 ::1].include?(uri.host)
      unless uri.is_a?(URI::HTTPS) || (uri.is_a?(URI::HTTP) && loopback)
        raise DecisionAnalyzer::ConfigurationError, "TYPESAFE_BASE_URL must be an https URL"
      end

      uri
    rescue URI::InvalidURIError
      raise DecisionAnalyzer::ConfigurationError, "TYPESAFE_BASE_URL is not a valid URL"
    end

    def headers
      {
        "Authorization" => "Bearer #{@api_key}",
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => "decision-lens"
      }
    end

    def checked_body(method, path, payload, timeout)
      uri = @base_uri.dup
      uri.path = path
      status, body = @transport.request(method, uri, headers: headers, body: payload, timeout: timeout)
      raise_for_status(status, body) unless status == 200
      body
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
      log_failure("timeout")
      raise DecisionAnalyzer::TimeoutError, "TypeSafe request timed out"
    rescue SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError
      log_failure("connection error")
      raise DecisionAnalyzer::ProviderError, "TypeSafe connection failed"
    end

    def raise_for_status(status, body)
      case status
      when 401, 403
        log_failure("HTTP #{status}")
        raise DecisionAnalyzer::AuthenticationFailed, "TypeSafe rejected the credentials"
      when 429
        log_failure("HTTP 429")
        raise DecisionAnalyzer::RateLimited, "TypeSafe rate limit reached"
      when 408, 504
        log_failure("HTTP #{status}")
        raise DecisionAnalyzer::TimeoutError, "TypeSafe timed out"
      when 400, 422
        log_failure("HTTP #{status} #{validation_summary(body)}".strip)
        raise DecisionAnalyzer::ProviderError, "TypeSafe rejected the request"
      else
        log_failure("HTTP #{status}")
        raise DecisionAnalyzer::ProviderError, "TypeSafe returned an error"
      end
    end

    # Field paths and error codes only: the "input"/"msg" fields can echo visitor text.
    def validation_summary(body)
      details = JSON.parse(body)["detail"]
      return "" unless details.is_a?(Array)

      details.first(5).filter_map do |detail|
        next unless detail.is_a?(Hash)

        "#{Array(detail['loc']).join('.')}:#{detail['type']}"
      end.join(",").gsub(/[^\w.:,\-]/, "")
    rescue JSON::ParserError
      ""
    end

    def log_failure(reason)
      Rails.logger.warn("[typesafe] request failed: #{reason}")
    end

    def parse(body)
      data = JSON.parse(body)
      raise DecisionAnalyzer::InvalidResponse, "response is not an object" unless data.is_a?(Hash)

      data
    rescue JSON::ParserError
      raise DecisionAnalyzer::InvalidResponse, "response is not valid JSON"
    end

    # Jev response -> provider contract. Unknown values are rejected later by the analyzer.
    def translate(data)
      answers = data["answers"]
      raise DecisionAnalyzer::InvalidResponse, "answers missing" unless answers.is_a?(Hash)

      {
        category: choice_decision(answers["category"], "category"),
        urgency: score_decision(answers["urgency"]),
        action: choice_decision(answers["action"], "action"),
        provider: NAME,
        model: data["model"],
        usage: { input_tokens: data.dig("usage", "input_tokens") }
      }
    end

    def choice_decision(answer, name)
      unless answer.is_a?(Hash) && answer["type"] == "choice" && answer["choice"].is_a?(String)
        raise DecisionAnalyzer::InvalidResponse, "#{name} answer missing or wrong type"
      end

      { value: answer["choice"], confidence: answer["confidence"], probabilities: answer["probabilities"] }
    end

    # Score levels are numbered by position; the most probable level is the decision.
    def score_decision(answer)
      unless answer.is_a?(Hash) && answer["type"] == "score" && answer["probabilities"].is_a?(Hash)
        raise DecisionAnalyzer::InvalidResponse, "urgency answer missing or wrong type"
      end

      levels = DecisionAnalyzer::URGENCIES
      raw = answer["probabilities"]
      unless raw.keys.sort == levels.each_index.map(&:to_s) && raw.values.all?(Numeric)
        raise DecisionAnalyzer::InvalidResponse, "urgency probabilities malformed"
      end

      probabilities = levels.each_with_index.to_h { |name, index| [ name, raw[index.to_s] ] }
      { value: probabilities.max_by { |_name, probability| probability }.first,
        confidence: answer["confidence"], probabilities: probabilities }
    end
  end
end
