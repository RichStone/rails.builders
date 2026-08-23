require "test_helper"

class HomeHelperTest < ActionView::TestCase
  test "anonymous builder names have one million possible combinations" do
    vocabulary_sizes = [
      HomeHelper::ANONYMOUS_ADJECTIVES.size,
      HomeHelper::ANONYMOUS_FIRST_NAMES.size,
      HomeHelper::ANONYMOUS_LAST_NAMES.size
    ]

    assert_equal [ 100, 100, 100 ], vocabulary_sizes
    assert_equal 1_000_000, vocabulary_sizes.inject(:*)
  end
end
