class Farm < ActiveRecord::Base
  
  validates_presence_of :name, :description, :ami_id, :role
  validates_length_of :ami_id, :minimum => 12, :maximum => 12, :message => "AMI_ID has an exact length of 12 characters"
  
  require 'chef/search/query'
  require 'lib/connect'
    
  def self.min_max_check()
    #Cycle through farms, take note of min max, then check state of each farm to insure compliance.
    Farm.find(:all).each do |fm|
      num_running_instances = fm.running_instances.length
      if (num_running_instances < fm.min)
        fm.start_instances(fm.min - num_running_instances)
      elsif (num_running_instances > fm.max)
        (num_running_instances - fm.max).times do
          if fm.idle.count > 0
            Node.shutdown_instance(fm.idle.shift, fm.name)
          end
        end
      end
    end
  end
  
  def self.chef_ec2_reconcile
    begin
      all_instance_ids = Farm.ec2_instance_ids
      Farm.find(:all).each do |fm|
        fm.running_instances.each do |inst|
          if ! all_instance_ids.include?(inst["instance_id"]) && fm.name != "Chef Server"
            Node.delete_chef_client(inst["instance_id"])
            Node.delete_chef_node(inst["instance_id"])
          end
        end
      end
      return true
    rescue
      Rails.logger.error("Farm.chef_ec2_reconcile: Unable to perform ec2/chef reconciliation.")
      return false
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
  
  def self.ec2_instance_ids
    # Returns an array of running EC2 instance ids
    conn = Connect.new
    instance_id_array = Array.new
    conn.fog.servers.each do |inst|
      instance_id_array << inst.id
    end
    conn.switch_region
    conn.fog.servers.each do |inst|
      instance_id_array << inst.id
    end
    instance_id_array
  end
    
  def running_instances()
    # Returns running instance information based on Farm, this was the only way to get proper created_at time
    node_array = Array.new
    Node.query_chef("node", "qips_farm", self.name).each do |nd|
      if nd.nil? || nd.empty?
        return nil
      end
      n = Hash.new
      n["chef_url"] = nd.chef_url
      n["reservation_id"] = nd.ec2.reservation_id
      n["instance_id"] = nd.ec2.instance_id
      n["public_hostname"] = nd.ec2.public_hostname
      n["name"] = nd.name
      n["ami_id"] = nd.ec2.ami_id
      n["security_groups"] = nd.ec2.security_groups
      n["created_at"] = nd.qips_launch_time.to_time
      node_array << n
    end
    node_array
  end
  
  def self.fetch_all()
    begin
      nodes = Node.list
      
      payload = Hash.new
      
      Farm.all.each do |fm|
        current_farm = Array.new
        nodes.each do |node_name, sys_url|
          nd = Node.load(node_name)
          if fm.name == nd.qips_farm
            current_farm << nd
          end
        end
        payload[fm.name] = current_farm
      end
      
      return payload
    rescue
      Rails.logger.error("Farm.fetch_all: Unable to fetch information on all farms and their respective instances")
      return nil
    end
  end
  
  def self.reconcile_nodes()
    # First we call Farm.min_max_check to shutdown nodes that aren't warranted by it's farm.
    Farm.min_max_check
    # Second, we check to see if nodes/clients exist in Chef but not EC2
    Farm.chef_ec2_reconcile
    # Thirdly, we check if CPU is being used after 52 minutes since the instance was launched is up. If so, shutdown instance.
    begin
      
      conn = Connect.new
      
      Farm.find(:all).each do |farm|
        farm.idle.each do |instance_id|
          conn.set_region(farm.avail_zone)
          instance = conn.fog.servers.get(instance_id)
          uptime_sec = (Time.now.to_i - instance.created_at.to_i)
          if (uptime_sec % 3600) >= Chef::Config[:max_idle_seconds].to_i # Set in config/rmgr-config.rb
            if Node.load(instance.id).qips_status == "idle"
              Rails.logger.info("[#{Time.now}] Farm.reconcile_nodes: Shutting down #{instance.id} due to inactivity.")
              Node.shutdown_instance(instance_id, farm.name)
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
      return true
    rescue
      Rails.logger.error("[#{Time.now}] Farm.reconcile_nodes: Unable to perform reconcile duties.")
      return false
    end
  end
    
  def start_instances(num_instances)
    if num_instances.to_i > 0
      begin
        num_instances.to_i.times do
          Node.async_start_by_spot_request(self.name, self.avail_zone, self.keypair, self.ami_id, self.ami_type, self.spot_price)
        end
      rescue => e
        puts e.backtrace
        Rails.logger.error("Farm.start_instances: Unable to start #{num_instances} in #{self.name}")
      end
    end
  end
  
end