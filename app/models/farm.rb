class Farm < ActiveRecord::Base
  
  validates_presence_of :name, :description, :ami_id, :role
  validates_length_of :ami_id, :minimum => 12, :maximum => 12, :message => "AMI_ID has an exact length of 12 characters"
  
  require 'chef/search/query'
  
  
  @@ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])
  
  def self.set_ec2_west
    @@ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key], :region => 'us-west-1')
  end
  
  def self.set_ec2_east
    @@ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key], :region => 'us-east-1')
  end
  
  def self.switch_ec2_region
    if Node.get_ec2_region == "east"
      Node.set_ec2_west
    else
      Node.set_ec2_east
    end
  end
  
  def self.get_ec2_region
    if @@ec2.params[:server] == "us-west-1.ec2.amazonaws.com"
      return "west"
    else
      return "east"
    end
  end
    
  def self.min_max_check()
    #Cycle through farms, take note of min max, then check state of each farm to insure compliance.
    Farm.find(:all).each do |fm|
      num_running_instances = fm.running_instances.length
      if (num_running_instances < fm.min)
        fm.start_instances(fm.min - num_running_instances)
      elsif (num_running_instances > fm.max)
        (num_running_instances - fm.max).times do
          if fm.idle.count > 0
            Node.shutdown_instance(fm.idle.shift)
          end
        end
      end
    end
  end
  
  def idle()
    # Returns instance ids of instances that are in an idle state associated with this farm.
    instance_ids = Array.new
    query_array = Node.query_chef("node", "qips_status","idle")
    query_array.each do |instance|
      if instance["qips_farm"] == self.name
        instance_ids << instance.ec2.instance_id
      end
    end
    instance_ids
  end
  
  def busy()
    # Returns instance ids of instances that are in a busy state associated with this farm.
    instance_ids = Array.new
    query_array = Node.query_chef("node", "qips_status","busy")
    query_array.each do |instance|
      if instance["qips_farm"] == self.name
        instance_ids << instance.ec2.instance_id
      end
    end
    instance_ids
  end
    
  def running_instances()
    # Returns instance ids associated with instances running from this farm.
    Node.query_chef("node", "qips_farm", self.name)
  end
  
  def self.reconcile_nodes()
    #First we call Farm.min_max_check to shutdown nodes that aren't warranted by it's farm.
    Farm.min_max_check
    #Second we check if CPU is being used after 52 minutes since the instance was launched is up. If so, shutdown instance.
    begin
      Farm.find(:all).each do |farm|
        farm.idle.each do |instance_id|
          if Node.query_chef("node", "name", instance_id)[0].domain =~ /west/
            Farm.set_ec2_west
          else
            Farm.set_ec2_east
          end
          puts @@ec2
          instance = @@ec2.describe_instances(instance_id)[0]
          uptime_sec = (Time.now.to_i - DateTime.parse(instance[:aws_launch_time]).to_i)
          if (uptime_sec % 3600) >= Chef::Config[:max_idle_seconds].to_i # Set in config/rmgr-config.rb
            if Node.load(instance[:aws_instance_id]).qips_status == "idle"
              Rails.logger.info("[#{Time.now}] Farm.reconcile_nodes: Shutting down #{instance[:aws_instance_id]} due to inactivity.")
              Node.shutdown_instance(instance[:aws_instance_id])
            else
              Rails.logger.info("Farm.reconcile_nodes: #{instance[:aws_instance_id]} will not be shutdown due to qips-status = busy")
            end
          else
            Rails.logger.info("Farm.reconcile_nodes: #{instance[:aws_instance_id]} will not be shutdown due to incompatible interval")
          end
        end
        #return true
      end
    rescue
      Rails.logger.error("[#{Time.now}] Farm.reconcile_nodes: Unable to perform reconcile duties.")
      #return false
    end
  end
    
  # FIXME Currently not working for EC2 West coast instances
  def start_instances(num_instances)
    if num_instances.to_i > 0
      begin
        num_instances.to_i.times do
          Node.async_start_by_spot_request(self.name, self.avail_zone, self.keypair, self.ami_id, self.ami_type)
        end
      rescue => e
        puts e.backtrace
        Rails.logger.error("Farm.start_instances: Unable to start #{num_instances} in #{self.name}")
      end
    end
  end
  
end