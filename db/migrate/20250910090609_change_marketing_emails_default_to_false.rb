class ChangeMarketingEmailsDefaultToFalse < ActiveRecord::Migration[7.1]
  def change
    change_column_default :users, :marketing_emails, from: true, to: false
  end
end
