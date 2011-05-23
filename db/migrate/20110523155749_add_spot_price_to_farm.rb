class AddSpotPriceToFarm < ActiveRecord::Migration
  def self.up
    add_column :farms, :spot_price, :float
  end

  def self.down
    remove_column :farms, :spot_price
  end
end
