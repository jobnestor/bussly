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

ActiveRecord::Schema[8.1].define(version: 2026_11_20_170000) do
  create_table "bookings", force: :cascade do |t|
    t.string "ref", null: false
    t.integer "operator_id"
    t.string "trip_type", null: false
    t.string "from_place", null: false
    t.string "to_place", null: false
    t.date "date", null: false
    t.string "time"
    t.date "return_date"
    t.integer "wait_hours"
    t.integer "pax", null: false
    t.boolean "electric", default: false, null: false
    t.boolean "luggage", default: false, null: false
    t.integer "hours"
    t.string "guide"
    t.boolean "cruise", default: false, null: false
    t.string "ship"
    t.string "aboard"
    t.integer "vehicle_count", null: false
    t.string "vehicle_class", null: false
    t.decimal "subtotal", precision: 12, scale: 2, null: false
    t.decimal "customer_subtotal", precision: 12, scale: 2, null: false
    t.decimal "guide_subtotal", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "vat", precision: 12, scale: 2, null: false
    t.decimal "total", precision: 12, scale: 2, null: false
    t.decimal "deposit", precision: 12, scale: 2, null: false
    t.string "status", default: "new", null: false
    t.boolean "guaranteed", default: false, null: false
    t.string "contact_name"
    t.string "phone"
    t.string "email"
    t.string "organisation"
    t.string "payment_method"
    t.json "breakdown", default: {}, null: false
    t.string "locale", default: "nb", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "token"
    t.string "share_token"
    t.string "driver_name"
    t.string "driver_phone"
    t.string "vehicle_plate"
    t.datetime "deposit_paid_at"
    t.datetime "balance_paid_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.decimal "refund", precision: 12, scale: 2
    t.string "stops", default: "", null: false
    t.index ["operator_id"], name: "index_bookings_on_operator_id"
    t.index ["ref"], name: "index_bookings_on_ref", unique: true
    t.index ["share_token"], name: "index_bookings_on_share_token", unique: true
    t.index ["status"], name: "index_bookings_on_status"
    t.index ["token"], name: "index_bookings_on_token", unique: true
  end

  create_table "operators", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "depot", null: false
    t.integer "radius", default: 150, null: false
    t.decimal "pos_factor", precision: 3, scale: 2, default: "0.5", null: false
    t.boolean "ev", default: false, null: false
    t.boolean "instant", default: false, null: false
    t.decimal "rating", precision: 2, scale: 1
    t.integer "reviews_count", default: 0, null: false
    t.integer "model_year"
    t.json "amenities", default: [], null: false
    t.json "langs", default: [], null: false
    t.json "fleet", default: {}, null: false
    t.json "blocked_dates", default: [], null: false
    t.integer "sur_weekend", default: 10, null: false
    t.integer "sur_peak", default: 12, null: false
    t.integer "sur_night", default: 15, null: false
    t.string "org_number"
    t.string "licence_number"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "on_time_pct"
    t.integer "trips_count", default: 0, null: false
    t.integer "founded_year"
    t.text "about"
    t.index ["org_number"], name: "index_operators_on_org_number", unique: true
    t.index ["slug"], name: "index_operators_on_slug", unique: true
  end

  create_table "reviews", force: :cascade do |t|
    t.integer "operator_id", null: false
    t.integer "booking_id"
    t.integer "rating", null: false
    t.boolean "on_time", default: true, null: false
    t.string "author", null: false
    t.string "trip_label"
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_reviews_on_booking_id", unique: true
    t.index ["operator_id"], name: "index_reviews_on_operator_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shuttle_requests", force: :cascade do |t|
    t.string "company", null: false
    t.string "contact_name", null: false
    t.string "email", null: false
    t.string "phone"
    t.string "segment"
    t.string "route", null: false
    t.integer "riders"
    t.string "weekdays"
    t.date "start_date"
    t.text "notes"
    t.string "status", default: "new", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "operator_id"
    t.boolean "admin", default: false, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["operator_id"], name: "index_users_on_operator_id"
  end

  add_foreign_key "bookings", "operators"
  add_foreign_key "reviews", "bookings"
  add_foreign_key "reviews", "operators"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "operators"
end
