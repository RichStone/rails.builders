class CreateCommunityStatistics < ActiveRecord::Migration[8.1]
  def up
    create_table :community_statistics do |t|
      t.integer :cohorts_count, null: false, default: 6
      t.integer :cohort_finishers_count, null: false, default: 35
      t.integer :registrants_count, null: false, default: 0
    end

    execute <<~SQL
      INSERT INTO community_statistics (id, registrants_count)
      SELECT 1, COUNT(*) FROM users WHERE verified_at >= '2026-09-01 00:00:00'
    SQL
  end

  def down
    drop_table :community_statistics
  end
end
