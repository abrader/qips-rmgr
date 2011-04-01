class Farm < ActiveRecord::Base
  
  validates_presence_of :name, :description, :ami_id, :role
  validates_length_of :ami_id, :minimum => 12, :maximum => 12, :message => "AMI_ID has an exact length of 12 characters"
  
  def start_instances(num_instances)
    begin
      num_instances.each do
        n = Node.new
        n.start_by_spot_request(self.name, self.ami_id, self.ami_type)
      end
    rescue => e
      puts e.backtrace
      Rails.logger.error("Farm.start_instances: Unable to start #{:num_instances} in #{self.name}")
    end
  end
end
