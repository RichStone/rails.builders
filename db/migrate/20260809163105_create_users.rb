class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.datetime :verified_at
      t.boolean :og, null: false, default: false
      t.boolean :administrator, null: false, default: false
      t.boolean :facilitator, null: false, default: false
      t.boolean :public_profile, null: false, default: false
      t.string :name
      t.text :testimonial
      t.string :enrollment_status, null: false, default: "unverified"
      t.datetime :waitlist_joined_at
      t.integer :waitlist_rank
      t.datetime :offer_expires_at
      t.datetime :newsletter_requested_at
      t.datetime :newsletter_confirmed_at
      t.string :clickfunnels_contact_id
      t.string :clickfunnels_sync_status, null: false, default: "not_requested"
      t.string :slack_status, null: false, default: "manual_pending"

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :enrollment_status
    add_index :users, [ :waitlist_rank, :waitlist_joined_at ]
  end
end
