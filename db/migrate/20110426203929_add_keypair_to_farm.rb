class AddKeypairToFarm < ActiveRecord::Migration
  def self.up
    add_column :farms, :keypair, :string
  end

  def self.down
    remove_column :farms, :keypair
  end
end
