require "minitest/autorun"

load File.expand_path("hetzner-status", __dir__)

class HetznerStatusTest < Minitest::Test
  NOW = Time.utc(2026, 9, 4, 8)

  def test_reports_healthy_read_only_aggregates
    result = status(
      server: {
        "id" => 123,
        "status" => "running",
        "backup_window" => "unused fixture value",
        "protection" => { "delete" => true, "rebuild" => true }
      },
      backups: [ { "created" => (NOW - 24 * 60 * 60).iso8601 } ]
    )

    assert_equal(
      {
        "server_running" => true,
        "backups_enabled" => true,
        "backup_fresh" => true,
        "deletion_protected" => true,
        "rebuild_protected" => true
      },
      result
    )
  end

  def test_marks_stale_backup_and_missing_protection_for_attention
    result = status(
      server: {
        "id" => 123,
        "status" => "running",
        "backup_window" => "unused fixture value",
        "protection" => { "delete" => false, "rebuild" => false }
      },
      backups: [ { "created" => (NOW - 49 * 60 * 60).iso8601 } ]
    )

    assert_equal false, result.fetch("backup_fresh")
    assert_equal false, result.fetch("deletion_protected")
    assert_equal false, result.fetch("rebuild_protected")
  end

  def test_refuses_to_guess_when_token_scope_contains_multiple_servers
    error = assert_raises(HetznerStatus::Unavailable) do
      HetznerStatus.new(fetch: ->(_path) { { "servers" => [ {}, {} ] } }, now: NOW).call
    end

    assert_equal "project_scope_ambiguous", error.message
  end

  private

  def status(server:, backups:)
    fetch = lambda do |path|
      path == "servers" ? { "servers" => [ server ] } : { "images" => backups }
    end

    HetznerStatus.new(fetch:, now: NOW).call
  end
end
