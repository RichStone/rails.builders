require "test_helper"

class GoogleWorkspace::MeetLinkTest < ActiveSupport::TestCase
  test "canonicalizes a valid Google Meet link" do
    assert_equal "abc-defg-hij", GoogleWorkspace::MeetLink.code("https://meet.google.com/ABC-DEFG-HIJ?authuser=1")
    assert_equal "https://meet.google.com/abc-defg-hij", GoogleWorkspace::MeetLink.url("https://meet.google.com/ABC-DEFG-HIJ?authuser=1")
  end

  test "rejects deceptive or malformed links" do
    assert_nil GoogleWorkspace::MeetLink.url("https://meet.google.com.example/abc-defg-hij")
    assert_nil GoogleWorkspace::MeetLink.url("https://user@meet.google.com/abc-defg-hij")
    assert_nil GoogleWorkspace::MeetLink.url("https://meet.google.com/invalid-code")
  end

  test "recognizes only the normalized URL as canonical" do
    assert GoogleWorkspace::MeetLink.canonical?("https://meet.google.com/abc-defg-hij")
    refute GoogleWorkspace::MeetLink.canonical?("https://meet.google.com/ABC-DEFG-HIJ")
    refute GoogleWorkspace::MeetLink.canonical?("https://meet.google.com/abc-defg-hij?authuser=1")
  end
end
