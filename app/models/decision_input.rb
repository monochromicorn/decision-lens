# Validated visitor input. Plain ActiveModel: nothing is persisted.
class DecisionInput
  include ActiveModel::Model

  attr_reader :text

  validate :length_within_bounds

  def initialize(text = nil)
    @text = text.to_s.strip
  end

  private

  def length_within_bounds
    if text.empty?
      errors.add(:text, "can't be blank. Paste a message or pick a sample.")
    elsif text.length < AppSettings::MIN_INPUT_LENGTH
      errors.add(:text, "is too short. Write at least #{AppSettings::MIN_INPUT_LENGTH} characters.")
    elsif text.length > AppSettings::MAX_INPUT_LENGTH
      errors.add(:text, "is too long. Keep it under #{AppSettings::MAX_INPUT_LENGTH} characters (currently #{text.length}).")
    end
  end
end
