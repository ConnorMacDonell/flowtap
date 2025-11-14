# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_11_14_002732) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "admin_users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "encrypted_password", null: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "user_id"
    t.string "action", null: false
    t.jsonb "metadata", default: {}
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["ip_address"], name: "index_audit_logs_on_ip_address"
    t.index ["user_id", "created_at"], name: "index_audit_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "status", default: "free", null: false
    t.string "stripe_subscription_id"
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "first_name"
    t.string "last_name"
    t.string "timezone", default: "UTC"
    t.boolean "marketing_emails", default: false
    t.datetime "deleted_at"
    t.string "stripe_customer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "qbo_realm_id"
    t.text "qbo_access_token"
    t.text "qbo_refresh_token"
    t.datetime "qbo_token_expires_at"
    t.datetime "qbo_connected_at"
    t.string "freelancer_user_id"
    t.text "freelancer_access_token"
    t.text "freelancer_refresh_token"
    t.datetime "freelancer_token_expires_at"
    t.text "freelancer_scopes"
    t.datetime "freelancer_connected_at"
    t.datetime "eula_accepted_at"
    t.datetime "privacy_policy_accepted_at"
    t.text "qbo_id_token"
    t.string "qbo_sub_id"
    t.string "qbo_user_email"
    t.boolean "qbo_user_email_verified"
    t.string "qbo_user_given_name"
    t.string "qbo_user_family_name"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["freelancer_connected_at"], name: "index_users_on_freelancer_connected_at"
    t.index ["freelancer_user_id"], name: "index_users_on_freelancer_user_id", unique: true
    t.index ["qbo_connected_at"], name: "index_users_on_qbo_connected_at"
    t.index ["qbo_realm_id"], name: "index_users_on_qbo_realm_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "audit_logs", "users"
  add_foreign_key "subscriptions", "users"
end
