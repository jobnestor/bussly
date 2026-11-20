class AddTrustStatsToOperators < ActiveRecord::Migration[8.1]
  def change
    change_table :operators, bulk: true do |t|
      t.integer :on_time_pct          # share of trips where the bus was at pickup on time
      t.integer :trips_count, default: 0, null: false
      t.integer :founded_year
      t.text :about
    end
  end
end
