class AddNewsletterConsentEvidenceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :newsletter_consent_version, :string
    add_column :users, :newsletter_requested_ip, :string
    add_column :users, :newsletter_user_agent, :string
  end
end
