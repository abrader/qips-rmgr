class Farm < ActiveRecord::Base
  
  validates_presence_of :name, :description, :ami_id, :role
  validates_length_of :ami_id, :minimum => 12, :maximum => 12, :message => "AMI_ID has an exact length of 12 characters"
  
  require 'chef/search/query'
  require 'connect'
    
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
    # Returns running instance information based on Farm, this was the only way to get proper created_at time
    node_array = Array.new
    Node.query_chef("node", "qips_farm", self.name).each do |nd|
      if nd.nil?
        return nil
      end
      conn = Connect.new
      n = Hash.new
      n["chef_url"] = nd.chef_url
      n["reservation_id"] = nd.ec2.reservation_id
      conn.set_region(Node.find_by_instance_id(nd.ec2.instance_id).region)
      fog_info = conn.fog.servers.get(nd.ec2.instance_id)
      n["public_hostname"] = fog_info.dns_name
      n["instance_id"] = fog_info.id
      n["name"] = fog_info.id
      n["ami_id"] = fog_info.image_id
      n["security_groups"] = fog_info.groups
      n["created_at"] = fog_info.created_at
      node_array << n
    end
    node_array
  end
  
  def self.reconcile_nodes()
    #First we call Farm.min_max_check to shutdown nodes that aren't warranted by it's farm.
    Farm.min_max_check
    #Second we check if CPU is being used after 52 minutes since the instance was launched is up. If so, shutdown instance.
    begin
      
      conn = Connect.new
      
      Farm.find(:all).each do |farm|
        farm.idle.each do |instance_id|
          conn.set_region(Node.find_by_instance_id(instance_id).region)
          instance = conn.fog.servers.get(instance_id)
          uptime_sec = (Time.now.to_i - instance.created_at.to_i)
          if (uptime_sec % 3600) >= Chef::Config[:max_idle_seconds].to_i # Set in config/rmgr-config.rb
            if Node.load(instance.id).qips_status == "idle"
              Rails.logger.info("[#{Time.now}] Farm.reconcile_nodes: Shutting down #{instance.id} due to inactivity.")
              Node.shutdown_instance(instance_id)
              return true
            else
              Rails.logger.info("[#{Time.now}] Farm.reconcile_nodes: #{instance.id} will not be shutdown due to qips-status = busy")
              return true
            end
          else
            Rails.logger.info("[#{Time.now}] Farm.reconcile_nodes: #{instance.id} will not be shutdown due to incompatible interval")
            return true
          end
        end
      end
    rescue
      Rails.logger.error("[#{Time.now}] Farm.reconcile_nodes: Unable to perform reconcile duties.")
      return false
    end
  end
    
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