module DecisionsHelper
  ICONS = {
    "low" => "▽", "medium" => "◇", "high" => "△",
    "automate" => "↻", "review" => "◉", "escalate" => "⇧"
  }.freeze

  CARD_TITLES = { category: "Category", urgency: "Urgency", action: "Recommended action" }.freeze

  def decision_badge(kind, value)
    icon = ICONS.fetch(value, "●")
    tag.span(class: "badge badge-#{kind}-#{value}") do
      safe_join([ tag.span(icon, "aria-hidden": "true"), value.humanize ], " ")
    end
  end

  def confidence_percent(decision)
    (decision[:confidence] * 100).round
  end

  def low_confidence?(decision)
    decision[:confidence] < DecisionAnalyzer::LOW_CONFIDENCE
  end

  def overall_low_confidence?(result)
    %i[category urgency action].any? { |key| low_confidence?(result[key]) }
  end
end
