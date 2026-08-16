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

ActiveRecord::Schema[8.1].define(version: 2026_08_16_150000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "focus", default: false, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "user_id", null: false
    t.index ["focus"], name: "index_products_on_focus"
    t.index ["user_id"], name: "index_products_on_user_id"
  end

  create_table "programs", force: :cascade do |t|
    t.integer "capacity", default: 9, null: false
    t.datetime "created_at", null: false
    t.date "ends_on", null: false
    t.string "name", null: false
    t.boolean "og_priority", default: true, null: false
    t.boolean "promotions_paused", default: false, null: false
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "administrator", default: false, null: false
    t.string "clickfunnels_contact_id"
    t.string "clickfunnels_contact_public_id"
    t.string "clickfunnels_sync_status", default: "not_requested", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "enrollment_status", default: "unverified", null: false
    t.boolean "facilitator", default: false, null: false
    t.string "name"
    t.datetime "newsletter_confirmed_at"
    t.string "newsletter_consent_version"
    t.datetime "newsletter_requested_at"
    t.string "newsletter_requested_ip"
    t.integer "newsletter_token_version", default: 0, null: false
    t.string "newsletter_user_agent"
    t.datetime "offer_expires_at"
    t.boolean "og", default: false, null: false
    t.boolean "public_profile", default: false, null: false
    t.integer "sign_in_token_version", default: 0, null: false
    t.string "slack_status", default: "manual_pending", null: false
    t.text "testimonial"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.datetime "waitlist_joined_at"
    t.integer "waitlist_rank"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["enrollment_status"], name: "index_users_on_enrollment_status"
    t.index ["waitlist_rank", "waitlist_joined_at"], name: "index_users_on_waitlist_rank_and_waitlist_joined_at"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "products", "users"
end
