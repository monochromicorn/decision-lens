# Deterministic overall summary, built only from the normalized answers so it can
# never disagree with the three cards. No model generates prose.
module DecisionSummary
  ACTION_PHRASES = {
    "automate" => "automation",
    "review" => "review",
    "escalate" => "escalation"
  }.freeze

  module_function

  def call(category:, urgency:, action:)
    item = category == "other" ? "uncategorized item" : "#{category} item"
    "This appears to be a #{urgency}-urgency #{item}. " \
      "The recommended action is #{ACTION_PHRASES.fetch(action)}."
  end
end
