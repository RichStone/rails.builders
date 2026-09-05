class AddPhaseDurationsToBuilderSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :builder_sessions, :pre_core_duration_seconds, :integer, default: 0, null: false
    add_column :builder_sessions, :hangout_duration_seconds, :integer, default: 0, null: false
  end
end
