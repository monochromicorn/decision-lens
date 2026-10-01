# Built-in examples. Results are precomputed so demonstrations never spend paid
# inference and always work, even when the AI provider is down or capped. Each
# result goes through the same normalization (and deterministic summary) as a live one.
module SampleInputs
  Sample = Data.define(:label, :text, :result)

  def self.build(label:, text:, category:, urgency:, action:)
    raw = { category: category, urgency: urgency, action: action, provider: "precomputed" }
    Sample.new(label: label, text: text, result: DecisionAnalyzer.normalize(raw))
  end
  private_class_method :build

  ALL = [
    build(
      label: "Checkout is down",
      text: "Our checkout page has been returning errors for the last 30 minutes and customers are emailing us that they cannot complete purchases. We need someone to look at this right now.",
      category: { value: "support", confidence: 0.93,
                  probabilities: { "support" => 0.93, "sales" => 0.01, "billing" => 0.02, "feedback" => 0.01, "security" => 0.02, "other" => 0.01 } },
      urgency: { value: "high", confidence: 0.96,
                 probabilities: { "low" => 0.01, "medium" => 0.03, "high" => 0.96 } },
      action: { value: "escalate", confidence: 0.94,
                probabilities: { "automate" => 0.01, "review" => 0.05, "escalate" => 0.94 } }
    ),
    build(
      label: "Double charge",
      text: "I was charged twice for my March subscription. Could you refund the duplicate payment when you have a moment? Thanks!",
      category: { value: "billing", confidence: 0.91,
                  probabilities: { "support" => 0.03, "sales" => 0.01, "billing" => 0.91, "feedback" => 0.02, "security" => 0.01, "other" => 0.02 } },
      urgency: { value: "medium", confidence: 0.72,
                 probabilities: { "low" => 0.2, "medium" => 0.72, "high" => 0.08 } },
      action: { value: "review", confidence: 0.58,
                probabilities: { "automate" => 0.3, "review" => 0.58, "escalate" => 0.12 } }
    ),
    build(
      label: "Happy customer",
      text: "Just wanted to say the new dashboard is fantastic. The filters save me a lot of time. Thank you to the whole team!",
      category: { value: "feedback", confidence: 0.95,
                  probabilities: { "support" => 0.01, "sales" => 0.01, "billing" => 0.01, "feedback" => 0.95, "security" => 0.01, "other" => 0.01 } },
      urgency: { value: "low", confidence: 0.9,
                 probabilities: { "low" => 0.9, "medium" => 0.08, "high" => 0.02 } },
      action: { value: "automate", confidence: 0.88,
                probabilities: { "automate" => 0.88, "review" => 0.1, "escalate" => 0.02 } }
    )
  ].freeze

  def self.find_by_text(text)
    ALL.find { |sample| sample.text == text.to_s.strip }
  end
end
