class CreateBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :bookings do |t|
      t.string :ref, null: false
      t.references :operator, null: true, foreign_key: true
      t.string :trip_type, null: false
      t.string :from_place, null: false
      t.string :to_place, null: false
      t.date :date, null: false
      t.string :time
      t.date :return_date
      t.integer :wait_hours
      t.integer :pax, null: false
      t.boolean :electric, null: false, default: false
      t.boolean :luggage, null: false, default: false
      t.integer :hours
      t.string :guide
      t.boolean :cruise, null: false, default: false
      t.string :ship
      t.string :aboard
      t.integer :vehicle_count, null: false
      t.string :vehicle_class, null: false
      t.decimal :subtotal, precision: 12, scale: 2, null: false      # what the operator is paid on (excl. VAT, before commission)
      t.decimal :customer_subtotal, precision: 12, scale: 2, null: false # what the customer pays excl. VAT (incl. guarantee buffer)
      t.decimal :guide_subtotal, precision: 12, scale: 2, null: false, default: 0
      t.decimal :vat, precision: 12, scale: 2, null: false
      t.decimal :total, precision: 12, scale: 2, null: false
      t.decimal :deposit, precision: 12, scale: 2, null: false
      t.string :status, null: false, default: "new"
      t.boolean :guaranteed, null: false, default: false
      t.string :contact_name
      t.string :phone
      t.string :email
      t.string :organisation
      t.string :payment_method
      t.json :breakdown, null: false, default: {}
      t.string :locale, null: false, default: "nb"
      t.timestamps
    end
    add_index :bookings, :ref, unique: true
    add_index :bookings, :status
  end
end
