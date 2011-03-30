class Farm < ActiveRecord::Base
  
  validates_presence_of :name, :description, :ami_id, :role
  validates_length_of :ami_id, :minimum => 12, :maximum => 12, :message => "AMI_ID has an exact length of 12 characters"
  
  def start_instances(num_instances)
    begin
      num_instances.each do
        n = Node.new()
        n.start_by_spot_request(self.name, self.ami_id)
      end
    rescue
      Rails.logger.error("Unable to start #{num_instances} instances from #{self.name}.")
    end
  end
  
end
