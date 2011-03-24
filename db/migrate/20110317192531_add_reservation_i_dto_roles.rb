class AddReservationIDtoRoles < ActiveRecord::Migration
  def self.up
    add_column :roles, :reservation_id, :string
  end

  def self.down
    remove_column :roles, :reservation_id
  end
end
