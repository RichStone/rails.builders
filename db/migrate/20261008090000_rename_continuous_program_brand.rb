class RenameContinuousProgramBrand < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE programs
      SET name = 'Continuous Rails.Builders Edition', updated_at = CURRENT_TIMESTAMP
      WHERE name = 'Continuous r-AI-ls.Builders Edition'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE programs
      SET name = 'Continuous r-AI-ls.Builders Edition', updated_at = CURRENT_TIMESTAMP
      WHERE name = 'Continuous Rails.Builders Edition'
    SQL
  end
end
