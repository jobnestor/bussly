class CreateOperators < ActiveRecord::Migration[8.0]
  def change
    create_table :operators do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :depot, null: false
      t.integer :radius, null: false, default: 150
      t.decimal :pos_factor, precision: 3, scale: 2, null: false, default: 0.5
      t.boolean :ev, null: false, default: false
      t.boolean :instant, null: false, default: false
      t.decimal :rating, precision: 2, scale: 1
      t.integer :reviews_count, null: false, default: 0
      t.integer :model_year
      t.json :amenities, null: false, default: []
      t.json :langs, null: false, default: []
      t.json :fleet, null: false, default: {}
      t.json :blocked_dates, null: false, default: []
      t.integer :sur_weekend, null: false, default: 10
      t.integer :sur_peak, null: false, default: 12
      t.integer :sur_night, null: false, default: 15
      t.string :org_number
      t.string :licence_number
      t.string :email
      t.timestamps
    end
    add_index :operators, :slug, unique: true
    add_index :operators, :org_number, unique: true
    add_reference :users, :operator, foreign_key: true
    add_column :users, :admin, :boolean, null: false, default: false
  end
end
