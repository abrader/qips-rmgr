class AddMinMaxToFarm < ActiveRecord::Migration
  def self.up
    add_column :farms, :min, :integer, :default => 0
    add_column :farms, :max, :integer, :default => 1
  end

  def self.down
    remove_column :farms, :min
    remove_column :farms, :max
  end
end
