class AddFormatPointsToPrograms < ActiveRecord::Migration[8.1]
  FORMAT_POINTS = <<~TEXT.strip
    🚂 Forever free & community-led
    💪 Weekly live sessions. OBLIGATORY: Missing 3 sessions in a row opens a spot for the waitlist ☠️
    🎯 ~1 hour: everyone takes a random turn to share one business challenge, one AI-building thing, and one thing they want to achieve by the next session
    🛋️ (optional) ~30m just for a fun hangout to go deeper on anything or talk current events
    🏃‍♂️ Learn from others during the sessions & execute until the next one.
    ⛑️ Get support or your ass kicked — whatever you need most right now
    💌 (optional) Personalized session summary email
    📈 (optional) Monthly trend analysis email of your Builder journey
    💬 (optional) Get support or message other Builders in Slack
  TEXT

  def up
    add_column :programs, :format_points, :text, null: false, default: FORMAT_POINTS
    execute <<~SQL.squish
      UPDATE programs
      SET name = 'Continuous r-AI-ls.Builders Edition'
      WHERE name = 'Continuous'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE programs
      SET name = 'Continuous'
      WHERE name = 'Continuous r-AI-ls.Builders Edition'
    SQL
    remove_column :programs, :format_points
  end
end
