class AddSlackDesiredStateToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :slack_desired_state, :string, null: false, default: "absent"
    execute <<~SQL.squish
      UPDATE users
      SET slack_desired_state = 'present'
      WHERE enrollment_status = 'active'
    SQL
  end

  def down
    remove_column :users, :slack_desired_state
  end
end
