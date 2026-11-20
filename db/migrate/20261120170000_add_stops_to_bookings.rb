class AddStopsToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :stops, :string, default: "", null: false
  end
end
