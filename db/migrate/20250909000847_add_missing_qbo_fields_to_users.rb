class AddMissingQboFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    rename_column :users, :qbo_company_id, :qbo_realm_id
  end
end
