class AddOpenIdConnectFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :qbo_id_token, :text
    add_column :users, :qbo_user_sub, :string
    add_column :users, :qbo_user_email, :string
    add_column :users, :qbo_user_email_verified, :boolean
    add_column :users, :qbo_user_given_name, :string
    add_column :users, :qbo_user_family_name, :string
  end
end
