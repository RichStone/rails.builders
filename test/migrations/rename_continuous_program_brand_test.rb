require "test_helper"
require_relative "../../db/migrate/20261008090000_rename_continuous_program_brand"

class RenameContinuousProgramBrandTest < ActiveSupport::TestCase
  test "renaming the cohort preserves its configuration and other programs" do
    program = Program.create!(name: "Continuous r-AI-ls.Builders Edition", starts_on: Date.new(2026, 9, 3), ends_on: Date.new(2026, 12, 17), capacity: 7, format_points: "Keep this format", readiness_points: "Keep this checklist")
    other_program = Program.create!(name: "Another cohort", starts_on: program.starts_on, ends_on: program.ends_on, capacity: 3)
    original_attributes = program.attributes.except("name", "updated_at")
    other_attributes = other_program.attributes
    migration = RenameContinuousProgramBrand.new

    migration.up
    migration.up

    assert_equal "Continuous Rails.Builders Edition", program.reload.name
    assert_equal original_attributes, program.attributes.except("name", "updated_at")
    assert_equal other_attributes, other_program.reload.attributes

    migration.down

    assert_equal "Continuous r-AI-ls.Builders Edition", program.reload.name
    assert_equal original_attributes, program.attributes.except("name", "updated_at")
    assert_equal other_attributes, other_program.reload.attributes
  end
end
