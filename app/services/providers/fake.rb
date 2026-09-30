require "json"

module Providers
  # Deterministic, offline stand-in for a real model. Keyword rules only; the
  # same text always yields the same JSON. Used in development and tests.
  class Fake
    CATEGORY_KEYWORDS = {
      "security" => %w[password breach hacked hack phishing unauthorized compromised],
      "billing"  => %w[charge charged refund invoice payment billed subscription],
      "sales"    => %w[pricing quote demo purchase buy upgrade plan],
      "support"  => %w[error broken bug crash cannot can't outage down help issue],
      "feedback" => %w[thanks thank love great fantastic suggest feedback]
    }.freeze
    HIGH_URGENCY   = ["urgent", "asap", "immediately", "right now", "outage", "breach", "critical", "unauthorized", "cannot", "can't"].freeze
    MEDIUM_URGENCY = ["soon", "problem", "issue", "refund", "twice", "this week", "error"].freeze

    def complete(text, timeout: nil)
      words = text.downcase
      category, hits = categorize(words)
      urgency, urgency_hits = urgency_for(words)
      action = action_for(category, urgency)

      JSON.generate(
        category: { value: category, confidence: category == "other" ? 0.5 : [ 0.55 + 0.12 * hits, 0.95 ].min.round(2) },
        urgency: { value: urgency, confidence: urgency == "low" ? 0.7 : [ 0.6 + 0.1 * urgency_hits, 0.95 ].min.round(2) },
        action: { value: action, confidence: action == "review" ? 0.62 : 0.85 },
        summary: summary_for(category, urgency, action)
      )
    end

    private

    def categorize(words)
      scored = CATEGORY_KEYWORDS.map { |name, list| [ name, count(words, list) ] }
      name, hits = scored.max_by { |(_, n)| n }
      hits.zero? ? [ "other", 0 ] : [ name, hits ]
    end

    def urgency_for(words)
      high = count(words, HIGH_URGENCY)
      return [ "high", high ] if high.positive?

      medium = count(words, MEDIUM_URGENCY)
      medium.positive? ? [ "medium", medium ] : [ "low", 0 ]
    end

    def action_for(category, urgency)
      return "escalate" if urgency == "high" || category == "security"
      return "automate" if urgency == "low" && %w[feedback sales].include?(category)

      "review"
    end

    def summary_for(category, urgency, action)
      tail = {
        "escalate" => "It needs prompt human attention.",
        "review" => "A person should look at it before anything is sent.",
        "automate" => "A standard automated reply is appropriate."
      }.fetch(action)
      "This looks like a #{urgency}-urgency #{category} message. #{tail}"
    end

    def count(words, list)
      list.count { |term| words.include?(term) }
    end
  end
end
