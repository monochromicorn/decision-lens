# Response shapes taken from https://api.typesafe.ai/openapi.json (SystemOneResponse,
# ChoiceAnswer, ScoreAnswer, HTTPValidationError). Values are invented; there is no
# real account data, header, or key here.
module TypesafeResponses
  def jev_body(overrides = {})
    {
      "model" => "jev-1.13.0",
      "answers" => {
        "category" => { "type" => "choice", "choice" => "billing", "confidence" => 0.91,
                        "probabilities" => { "support" => 0.03, "sales" => 0.01, "billing" => 0.91,
                                             "feedback" => 0.01, "security" => 0.01, "other" => 0.03 } },
        "urgency" => { "type" => "score", "score" => 1.8, "confidence" => 0.84,
                       "legend" => { "0" => "Nothing is time-sensitive.", "1" => "Soon.", "2" => "Today." },
                       "probabilities" => { "0" => 0.04, "1" => 0.12, "2" => 0.84 } },
        "action" => { "type" => "choice", "choice" => "escalate", "confidence" => 0.88,
                      "probabilities" => { "automate" => 0.02, "review" => 0.1, "escalate" => 0.88 } }
      },
      "usage" => { "input_tokens" => 120, "output_tokens" => 14 }
    }.merge(overrides)
  end

  def jev_answers(**changes)
    body = jev_body
    changes.each { |name, answer| answer.nil? ? body["answers"].delete(name.to_s) : body["answers"][name.to_s] = answer }
    body
  end

  def validation_error_body
    JSON.generate("detail" => [ { "loc" => [ "body", "state" ], "msg" => "Field required",
                                  "type" => "missing", "input" => "VISITOR-TEXT-ECHO" } ])
  end
end

RSpec.configure { |config| config.include TypesafeResponses }
