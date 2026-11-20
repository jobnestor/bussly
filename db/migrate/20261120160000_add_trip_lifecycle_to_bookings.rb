class AddTripLifecycleToBookings < ActiveRecord::Migration[8.1]
  def change
    change_table :bookings, bulk: true do |t|
      t.string :token            # secret link for the customer (/reise/:token)
      t.string :share_token      # passenger tracking link without prices or contact details (/spor/:share_token)
      t.string :driver_name
      t.string :driver_phone
      t.string :vehicle_plate
      t.datetime :deposit_paid_at
      t.datetime :balance_paid_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.decimal :refund, precision: 12, scale: 2
    end
    add_index :bookings, :token, unique: true
    add_index :bookings, :share_token, unique: true

    # Give existing bookings their links
    reversible do |dir|
      dir.up do
        select_values("SELECT id FROM bookings").each do |id|
          execute "UPDATE bookings SET token = #{quote(SecureRandom.urlsafe_base64(18))}, " \
                  "share_token = #{quote(SecureRandom.urlsafe_base64(12))} WHERE id = #{id.to_i}"
        end
      end
    end
  end
end
