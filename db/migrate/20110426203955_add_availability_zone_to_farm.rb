class AddAvailabilityZoneToFarm < ActiveRecord::Migration
  def self.up
    add_column :farms, :avail_zone, :string
  end

  def self.down
    remove_column :farms, :avail_zone
  end
end
