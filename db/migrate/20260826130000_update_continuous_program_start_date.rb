class UpdateContinuousProgramStartDate < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE programs
      SET starts_on = '2026-09-03', updated_at = CURRENT_TIMESTAMP
      WHERE name = 'Continuous r-AI-ls.Builders Edition'
        AND starts_on = '2026-08-20'
        AND ends_on = '2026-12-17'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE programs
      SET starts_on = '2026-08-20', updated_at = CURRENT_TIMESTAMP
      WHERE name = 'Continuous r-AI-ls.Builders Edition'
        AND starts_on = '2026-09-03'
        AND ends_on = '2026-12-17'
    SQL
  end
end
