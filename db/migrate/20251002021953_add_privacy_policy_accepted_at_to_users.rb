class AddPrivacyPolicyAcceptedAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :privacy_policy_accepted_at, :datetime
  end
end
