class AddMissingQboFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :qbo_realm_id, :string
    add_column :users, :qbo_access_token, :text
    add_column :users, :qbo_refresh_token, :text
    add_column :users, :qbo_token_expires_at, :datetime
    add_column :users, :qbo_connected_at, :datetime

    add_index :users, :qbo_realm_id
    add_index :users, :qbo_connected_at
  end
end
