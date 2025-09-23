class AddFreelancerOauthFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :freelancer_user_id, :string
    add_column :users, :freelancer_access_token, :text
    add_column :users, :freelancer_refresh_token, :text
    add_column :users, :freelancer_token_expires_at, :datetime
    add_column :users, :freelancer_scopes, :text
    add_column :users, :freelancer_connected_at, :datetime

    add_index :users, :freelancer_user_id, unique: true
    add_index :users, :freelancer_connected_at
  end
end
