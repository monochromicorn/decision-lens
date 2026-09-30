# Built-in examples. Results are precomputed so demonstrations never spend paid
# inference and always work, even when the AI provider is down or capped.
module SampleInputs
  Sample = Data.define(:label, :text, :result)

  ALL = [
    Sample.new(
      label: "Checkout is down",
      text: "Our checkout page has been returning errors for the last 30 minutes and customers are emailing us that they cannot complete purchases. We need someone to look at this right now.",
      result: {
        category: { value: "support", confidence: 0.93 },
        urgency: { value: "high", confidence: 0.96 },
        action: { value: "escalate", confidence: 0.94 },
        summary: "This is an active, revenue-affecting outage reported by customers. It needs an engineer immediately."
      }
    ),
    Sample.new(
      label: "Double charge",
      text: "I was charged twice for my March subscription. Could you refund the duplicate payment when you have a moment? Thanks!",
      result: {
        category: { value: "billing", confidence: 0.91 },
        urgency: { value: "medium", confidence: 0.72 },
        action: { value: "review", confidence: 0.58 },
        summary: "A routine billing correction. The refund should be checked against the payment record before it is approved."
      }
    ),
    Sample.new(
      label: "Happy customer",
      text: "Just wanted to say the new dashboard is fantastic. The filters save me a lot of time. Thank you to the whole team!",
      result: {
        category: { value: "feedback", confidence: 0.95 },
        urgency: { value: "low", confidence: 0.9 },
        action: { value: "automate", confidence: 0.88 },
        summary: "Positive product feedback that needs no follow-up beyond a friendly automated thank-you."
      }
    )
  ].freeze

  def self.find_by_text(text)
    ALL.find { |sample| sample.text == text.to_s.strip }
  end
end
