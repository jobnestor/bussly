class CreateShuttleRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :shuttle_requests do |t|
      t.string :company, null: false
      t.string :contact_name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :segment          # commute, event, airport, school, other
      t.string :route, null: false
      t.integer :riders
      t.string :weekdays
      t.date :start_date
      t.text :notes
      t.string :status, default: "new", null: false
      t.timestamps
    end
  end
end
