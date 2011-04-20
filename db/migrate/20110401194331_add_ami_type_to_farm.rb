class AddAmiTypeToFarm < ActiveRecord::Migration
  def self.up
    add_column :farms, :ami_type, :string
  end

  def self.down
    remove_column :farms, :ami_type
  end
end
