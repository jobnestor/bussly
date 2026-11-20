class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :operator, null: false, foreign_key: true
      t.references :booking, foreign_key: true, index: { unique: true }
      t.integer :rating, null: false
      t.boolean :on_time, default: true, null: false
      t.string :author, null: false
      t.string :trip_label
      t.text :comment
      t.timestamps
    end
  end
end
