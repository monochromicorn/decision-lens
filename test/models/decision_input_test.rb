require "test_helper"

class DecisionInputTest < ActiveSupport::TestCase
  test "length boundaries apply after trimming" do
    assert DecisionInput.new("a" * 10).valid?
    assert DecisionInput.new("   #{'a' * 10}   ").valid?
    assert DecisionInput.new("a" * 2000).valid?

    refute DecisionInput.new("a" * 9).valid?
    refute DecisionInput.new("   #{'a' * 9}   ").valid?
    refute DecisionInput.new("a" * 2001).valid?
    refute DecisionInput.new("     ").valid?
    refute DecisionInput.new(nil).valid?
  end

  test "error messages name the problem" do
    assert_match(/blank/, DecisionInput.new("").tap(&:valid?).errors[:text].first)
    assert_match(/too short/, DecisionInput.new("hi").tap(&:valid?).errors[:text].first)
    assert_match(/too long/, DecisionInput.new("a" * 2001).tap(&:valid?).errors[:text].first)
  end
end
