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

ActiveRecord::Schema[8.1].define(version: 2026_08_22_124000) do
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

  create_table "builder_session_attendances", force: :cascade do |t|
    t.datetime "arrived_at"
    t.integer "builder_session_id", null: false
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "role", null: false
    t.integer "speaker_allotted_seconds"
    t.datetime "speaker_ended_at"
    t.integer "speaker_paused_seconds", default: 0, null: false
    t.integer "speaker_position"
    t.datetime "speaker_started_at"
    t.string "speaker_state"
    t.string "status", default: "absent", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["builder_session_id", "speaker_position"], name: "index_session_attendances_on_speaker_position", unique: true, where: "speaker_position IS NOT NULL"
    t.index ["builder_session_id", "user_id"], name: "index_session_attendances_on_session_and_user", unique: true, where: "user_id IS NOT NULL"
    t.index ["builder_session_id"], name: "index_builder_session_attendances_on_builder_session_id"
    t.index ["builder_session_id"], name: "index_session_attendances_on_current_speaker", unique: true, where: "speaker_state = 'speaking'"
    t.index ["user_id"], name: "index_builder_session_attendances_on_user_id"
  end

  create_table "builder_session_pauses", force: :cascade do |t|
    t.integer "builder_session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["builder_session_id"], name: "index_builder_session_pauses_on_builder_session_id"
    t.index ["builder_session_id"], name: "index_builder_session_pauses_on_open_pause", unique: true, where: "ended_at IS NULL"
  end

  create_table "builder_session_transcripts", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.integer "builder_session_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "google_conference_record_name"
    t.text "google_transcript_names"
    t.datetime "imported_at"
    t.datetime "last_attempted_at"
    t.string "last_error_code"
    t.datetime "next_attempt_at"
    t.string "source"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["builder_session_id"], name: "index_builder_session_transcripts_on_builder_session_id", unique: true
    t.index ["state", "next_attempt_at"], name: "index_builder_session_transcripts_on_state_and_next_attempt_at"
  end

  create_table "builder_sessions", force: :cascade do |t|
    t.integer "assigned_facilitator_id"
    t.datetime "builder_updates_started_at"
    t.datetime "closing_started_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ended_at"
    t.string "facilitator_name_snapshot"
    t.string "finish_reason"
    t.string "google_event_id", null: false
    t.datetime "hangout_started_at"
    t.string "location"
    t.string "meet_url"
    t.integer "program_id", null: false
    t.datetime "scheduled_ends_at", null: false
    t.datetime "scheduled_starts_at", null: false
    t.datetime "started_at"
    t.string "state", default: "ready", null: false
    t.string "time_zone", null: false
    t.integer "timer_duration_seconds"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_facilitator_id"], name: "index_builder_sessions_on_assigned_facilitator_id"
    t.index ["program_id", "google_event_id"], name: "index_builder_sessions_on_program_id_and_google_event_id", unique: true
    t.index ["program_id", "state", "scheduled_starts_at"], name: "idx_on_program_id_state_scheduled_starts_at_ab613453a0"
    t.index ["program_id"], name: "index_builder_sessions_on_one_active_program", unique: true, where: "state IN ('connection', 'builder_updates', 'closing', 'hangout')"
    t.index ["program_id"], name: "index_builder_sessions_on_program_id"
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

  create_table "program_calendar_connections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "facilitator_id", null: false
    t.string "google_account_email", null: false
    t.string "google_calendar_id", null: false
    t.string "google_calendar_name", null: false
    t.string "google_calendar_time_zone"
    t.string "google_data_owner"
    t.string "last_error_code"
    t.datetime "last_synced_at"
    t.text "oauth_token_json", null: false
    t.integer "program_id", null: false
    t.string "status", default: "connected", null: false
    t.datetime "updated_at", null: false
    t.index ["facilitator_id"], name: "index_program_calendar_connections_on_facilitator_id"
    t.index ["program_id"], name: "index_program_calendar_connections_on_program_id", unique: true
  end

  create_table "programs", force: :cascade do |t|
    t.integer "capacity", default: 9, null: false
    t.datetime "created_at", null: false
    t.date "ends_on", null: false
    t.integer "main_facilitator_id"
    t.string "name", null: false
    t.boolean "og_priority", default: true, null: false
    t.boolean "promotions_paused", default: false, null: false
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
    t.index ["main_facilitator_id"], name: "index_programs_on_main_facilitator_id"
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
    t.boolean "public_profile_approved", default: false, null: false
    t.integer "sign_in_token_version", default: 0, null: false
    t.string "slack_desired_state", default: "absent", null: false
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
  add_foreign_key "builder_session_attendances", "builder_sessions"
  add_foreign_key "builder_session_attendances", "users"
  add_foreign_key "builder_session_pauses", "builder_sessions"
  add_foreign_key "builder_session_transcripts", "builder_sessions"
  add_foreign_key "builder_sessions", "programs"
  add_foreign_key "builder_sessions", "users", column: "assigned_facilitator_id"
  add_foreign_key "products", "users"
  add_foreign_key "program_calendar_connections", "programs"
  add_foreign_key "program_calendar_connections", "users", column: "facilitator_id"
  add_foreign_key "programs", "users", column: "main_facilitator_id"
end
