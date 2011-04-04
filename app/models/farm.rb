class Farm < ActiveRecord::Base
  
  validates_presence_of :name, :description, :ami_id, :role
  validates_length_of :ami_id, :minimum => 12, :maximum => 12, :message => "AMI_ID has an exact length of 12 characters"
  
  require 'chef/search/query'
    
  def self.min_max_check()
    #Cycle through farms, take note of min max, then check state of each farm to insure compliance.
    Farm.find(:all).each do |fm|
      num_running_instances = fm.running_instances.count
      if (num_running_instances < fm.min)
        fm.start_instances(fm.min - num_running_instances)
      elsif (num_running_instances > fm.max)
        (num_running_instances - fm.max).times do
         Node.shutdown_instance(fm.idle.shift)
        end
      end
    end
  end
  
  def idle()
    # Returns instance ids of instances that are in an idle state from this farm.
    instance_ids = Array.new
    query_array = query_chef("node", "qips_status","idle")
    query_array.each do |instance|
      if instance["qips_farm"] == self.name
        instance_ids << instance.ec2.instance_id
      end    
    end
    instance_ids
  end
    
  def running_instances()
    # Returns instance ids associated with instances running from this farm.
    instance_ids = Array.new
    query_array = query_chef("node", "qips_farm", self.name)
    query_array.each do |instance|
      instance_ids << instance.ec2.instance_id
    end
    instance_ids
  end
  
  def query_chef(model_type, attribute, search)
    # Returns instance ids associated with instances running from this farm.
    instance_ids = Array.new
    q = Chef::Search::Query.new
    query = "#{attribute}:\"#{search}\""
    
    begin
      q.search(model_type, query)[0].each do |instance|
        instance_ids << instance
      end
    rescue Net::HTTPServerException => e
      Rails.logger.error("Farm.query_chef(#{self.name}): Chef API search failed")
      exit 1
    end
    instance_ids
  end
    
  
  def start_instances(num_instances)
    if num_instances > 0
      begin
        num_instances.times do
          n = Node.new
          n.start_by_spot_request(self.name, self.ami_id, self.ami_type)
        end
      rescue => e
        puts e.backtrace
        Rails.logger.error("Farm.start_instances: Unable to start #{num_instances} in #{self.name}")
      end
    end
  end
end
