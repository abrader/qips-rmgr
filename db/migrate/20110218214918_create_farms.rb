class CreateFarms < ActiveRecord::Migration
  def self.up
    create_table :farms do |t|
      t.string :name
      t.string :description
      t.string :ami_id
      t.string :role

      t.timestamps
    end
  end

  def self.down
    drop_table :farms
  end
end
