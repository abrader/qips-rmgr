class CreateInstances < ActiveRecord::Migration
  def self.up
    create_table :instances do |t|
      t.string :instance_id
      t.string :ami_id
      t.string :instance_type
      t.string :status
      t.string :security_groups
      t.string :region
      t.string :monitoring

      t.timestamps
    end
  end

  def self.down
    drop_table :instances
  end
end
