require "test_helper"

class HomeHelperTest < ActionView::TestCase
  test "anonymous builder names have at least ten thousand distinct combinations" do
    combinations = HomeHelper::ANONYMOUS_ADJECTIVES.uniq.size * HomeHelper::ANONYMOUS_NOUNS.uniq.size

    assert_operator combinations, :>=, 10_000
  end
end
