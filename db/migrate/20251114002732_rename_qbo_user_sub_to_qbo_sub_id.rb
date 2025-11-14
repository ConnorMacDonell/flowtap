class RenameQboUserSubToQboSubId < ActiveRecord::Migration[7.1]
  def change
    rename_column :users, :qbo_user_sub, :qbo_sub_id
  end
end
