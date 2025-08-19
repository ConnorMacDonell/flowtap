class CreateAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, null: true, foreign_key: true # Allow system events without user
      t.string :action, null: false
      t.jsonb :metadata, default: {}
      t.string :ip_address

      t.timestamps
    end
    
    # Add indexes for performance
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
    add_index :audit_logs, [:user_id, :created_at]
    add_index :audit_logs, :ip_address
  end
end
