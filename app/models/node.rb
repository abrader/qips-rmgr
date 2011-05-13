class Node
  attr_accessor :instance_id, :aws_state, :hostname, :spot_instance_request_id, :region, :launch_time
  
  require 'chef/knife/bootstrap'
  require 'chef/knife/ssh'
  require 'chef/search/query'
  require 'resque'
  require 'lib/connect'
  
  DEFAULT_32_INSTANCE_TYPE = "m1.small"
  DEFAULT_64_INSTANCE_TYPE = "m1.large"
  
  @queue = :aws_spot_instance_requests
  
  def self.find_by_instance_id(instance_id)
    new_node = allocate
    new_node.initialize_from_instance_id(instance_id)
    new_node
  end
  
  # Has to use RightAWS for now since Fog doesn't support Spot Instance Requests
  def initialize_from_instance_id(instance_id)
    conn = Connect.new 
    
    begin
      instance = conn.right_ec2.describe_instances(instance_id)[0]
      @region = conn.region
      @instance_id = instance[:aws_instance_id]
      @aws_state = instance[:aws_state]
      @hostname = instance[:dns_name]
      @spot_instance_request_id  = instance[:spot_instance_request_id]
      @launch_time = instance[:aws_launch_time].to_time
      return self
    rescue RightAws::AwsError
      conn.switch_region
      instance = conn.right_ec2.describe_instances(instance_id)[0]
      @region = conn.region
      @instance_id = instance[:aws_instance_id]
      @aws_state = instance[:aws_state]
      @hostname = instance[:dns_name]
      @spot_instance_request_id  = instance[:spot_instance_request_id]
      @launch_time = instance[:aws_launch_time].to_time
      return self
    end
  end
     
  def chef_server_rest
    Chef::REST.new(Chef::Config[:chef_server_url])
  end

  def self.chef_server_rest
    Chef::REST.new(Chef::Config[:chef_server_url])
  end
  
  def self.load(name)
    chef_server_rest.get_rest("nodes/#{name}")
  end
  
  # Get the list of all systems registered with Chef.
  def self.list(inflate=false)
    if inflate
      response = Hash.new
      Chef::Search::Query.new.search(:node) do |n|
        response[n.name] = n unless n.nil?
      end
      response
    else
      chef_server_rest.get_rest("nodes")
    end
  end
  
  def self.cpu_util(instance_id, farm_name)
    conn = Connect.new
    conn.set_region(Farm.find_by_name(farm_name).avail_zone) # This is will set the EC2 region appriopriately for the ACW command
    util_over_time = 10 # min
    stats = conn.right_acw.get_metric_statistics(:start_time => (Time.now.utc - (util_over_time * 60)), :period => 60, :namespace => "AWS/EC2", :dimentions => {:InstanceId => instance_id}, :measure_name=>"CPUUtilization")
    avg = 0.0
    stats[:datapoints].each do |stat|
      avg = avg + stat[:average]
    end
    avg = avg / util_over_time
    avg
  end
  
  def self.get_ec2
    # Need to get EC2 info for both coasts
    @ec2_info_all = Array.new
    @ec2_info_all += Node.describe_ec2_instances("west")
    @ec2_info_all += Node.describe_ec2_instances("east")
  end
  
  def self.describe_ec2_instances(region)
    @ec2_info = Array.new
    
    conn = Connect.new
    conn.set_region(region)

    conn.fog.servers.each do |instance|
      if self.instance_match(instance.id) == false
        ec2_instance = Hash.new
        ec2_instance["private_dns"] = instance.private_dns_name
        ec2_instance["public_dns"] = instance.dns_name
        ec2_instance["instance_id"] = instance.id
        ec2_instance["ami_id"] = instance.image_id
        ec2_instance["uptime"] = instance.created_at
        ec2_instance["state"] = instance.state
        @ec2_info << ec2_instance
      end
    end
    @ec2_info
  end    
   
  #Check to see if an instance_id already exists in local record
  def self.instance_match(instance_id)
    Node.list().each do |node_name, sys_url|
      chef_node = Node.load(node_name)
      begin
        if instance_id == chef_node.ec2.instance_id && ! chef_node.qips_status.nil? && ! chef_node.qips_farm.nil?
          return true
        end
      rescue ArgumentError
        return false
      end
    end
    return false
  end
  
  def start_by_spot_request(farm_name, avail_zone, keypair, image_id, ami_type, spot_price)
    # This is the AWS reduced cost spot request
    require 'net/ssh/multi'
    
    instance = nil
    
    conn = Connect.new
    conn.set_region(Farm.find_by_name(farm_name).avail_zone)
    
    if ami_type == nil
      arch = Node.get_arch(image_id)
      if arch == "i386"
        ami_type = DEFAULT_32_INSTANCE_TYPE
      else
        ami_type = DEFAULT_64_INSTANCE_TYPE
      end
    end
    
    launch_group = ("QIPS_" + Rails.env).to_s
    
    sir = conn.right_ec2.request_spot_instances(
            :image_id => image_id,
            :spot_price => spot_price,
            :key_name => keypair,
            :instance_count => 1,
            :monitoring_enabled => true,
            :launch_group => launch_group,
            :groups => Chef::Config[:knife][:security_groups],
            :instance_type => ami_type,
            :availability_zone => avail_zone
    )
    
    @spot_instance_request_id = sir[0][:spot_instance_request_id]
    
    # Must hang in a loop until Amazon issues us a instance id
    while @instance_id == nil
      sleep(5)
      status = Node.describe_spot_instance_request(@spot_instance_request_id)
      @instance_id = status[:instance_id]
      sir_state = status[:state]
      break if (sir_state == nil || sir_state == "cancelled" || sir_state == "failed")
    end
    
    # Get the status of our instance now that we have an instance ID
    self.get_instance_status
    
    # Once we're done with the spot instance request we can cancel it
    conn.right_ec2.cancel_spot_instance_requests(@spot_instance_request_id)
    
    # Must wait for aws_state to go from Pending to Active in order to get pertinent host information i.e., hostname
    while @aws_state =~ /pending/
      sleep(5)
      self.get_instance_status
    end
    
    # Get the latest info on our instance now that hostname should be populated
    self.get_instance_status
    
    # wait for it to be ready to do stuff
    Node.wait_for_ssh(@hostname)

    # Must wait for system to come up for SSH to be responsive enough in order to avoid failure
    sleep(45)

    # Time to get that instance boostrapped with Chef-client
    tries = 0
    
    begin
      tries +=1
      self.instance_bootstrap(farm_name).run
    rescue
      Rails.logger.warn("Node.start_by_spot_request: First attempt to bootstrap instance #{@instance_id} failed. Retrying...")
      tries +=1
      retry if tries <= 2
      Rails.logger.error("Node.start_by_spot_request: Unable to bootstrap instance #{@instance_id}.")
      Node.shutdown_instance(@instance_id, farm_name)
      fm = Farm.find_by_name(farm_name)
      fm.start_instances(1)
    end
      
      
    
    # Set attributes so we can retrieve from OHAI later.
    sleep(15)
    Node.set_farm_name(@instance_id, farm_name)
    Node.set_qips_status(@instance_id, "idle")
    self.set_launch_time
    Node.set_chef_url()
  end
  
  # Resque method called by Farm to instantiate a spot instance request via queue
  def self.async_start_by_spot_request(farm_name, avail_zone, keypair, image_id=Chef::Config[:knife][:image], ami_type=nil, spot_price=Chef::Config[:knife][:spot_price])
    Resque.enqueue(Node, farm_name, avail_zone, keypair, image_id, ami_type, spot_price)
  end
  
  # Resque required method for calling start_by_spot_request via queue
  def self.perform(farm_name, avail_zone, keypair, image_id, ami_type, spot_price)
    n = Node.new
    n.start_by_spot_request(farm_name, avail_zone, keypair, image_id, ami_type, spot_price)
  end
  
  def self.set_chef_url()
    begin
      Node.list().each do |name,node_url|
        current_node = Node.load(name)
        current_node.attribute["chef_url"] = node_url.gsub(/4000/, '4040')
        current_node.save
      end
    rescue => e
      puts e.backtrace
      Rails.logger.error("Node.set_farm_name: Unable to set chef_url on chef aware nodes")
    end
  end
  
  def self.set_farm_name(instance_id, farm_name)
    begin
      node_name = Node.id_to_name(instance_id)
      if node_name.nil?
        Rails.logger.error("Node.set_farm_name: #{instance_id} does not exist")
        exit
      end
      node = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("nodes/#{node_name}")
      if node.nil?
        Rails.logger.error("Node.set_farm_name: get_rest failed for #{node_name}.")
      end
      node.attribute["qips_farm"] = farm_name
      node.save
    rescue => e
      Rails.logger.error("Node.set_farm_name: Unable to set #{instance_id} to farm #{farm_name}. --- #{e.backtrace}")
    end
  end
  
  def self.get_farm_name(instance_id)
    begin
      Node.query_chef("node", "name", instance_id)[0].qips_farm
    rescue
      Rails.logger.error("Node.get_qips_status: Unable to retrieve QIPS Status from Chef server for #{instance_id}.")
    end
  end
  
  def set_launch_time
    begin
      if @instance_id.nil? || @launch_time.nil?
        Rails.logger("Node.set_launch_time: Unable to set launch time due to instance_id or launch_time == nil.")
        return false
      end
      node_name = Node.id_to_name(instance_id)
      if node_name.nil?
        Rails.logger.error("Node.set_launch_time: #{instance_id} does not exist")
        exit
      end
      node = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("nodes/#{node_name}")
      if node.nil?
        Rails.logger.error("Node.set_launch_time: get_rest failed for #{node_name}.")
      end
      node.attribute["qips_launch_time"] = @launch_time
      node.save
      return true
    rescue => e
      Rails.logger.error("Node.set_launch_time: Unable to set #{instance_id} to farm #{farm_name}.")
      return false
    end
  end
  
  # Sets QIPS status, extra step due to non-compliance of instance_id == node name
  def self.set_qips_status(instance_id, status)
    begin
      node_name = Node.id_to_name(instance_id)
      if node_name.nil?
        Rails.logger.error("Node.set_qips_status: #{instance_id} does not exist")
        exit
      end
      node = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("nodes/#{node_name}")
      node.attribute["qips_status"] = status
      node.save
    rescue
      Rails.logger.error("Node.set_qips_status: Unable to set #{status} status for #{instance_id}.")
    end
  end
  
  def self.get_qips_status(instance_id)
    begin
      Node.query_chef("node", "name", instance_id)[0].qips_status
    rescue
      Rails.logger.error("Node.get_qips_status: Unable to retrieve QIPS Status from Chef server for #{instance_id}.")
    end
  end
  
  def self.id_to_name(instance_id)
    begin
      q = Chef::Search::Query.new
      query = "instance_id:#{instance_id}"

      q.search("node", query)[0].each do |instance|
        return instance.name
      end
      return nil
    rescue => e
      Rails.logger.error("Node.id_to_name: Unable to search chef server for #{instance_id}")
    end
  end
  
  def self.query_chef(model_type, attribute, search)
    # Returns instance ids associated with instances running from this farm.
    instance_ids = Array.new
    q = Chef::Search::Query.new
    query = "#{attribute}:\"#{search}\""
    
    begin
      q.search(model_type, query)[0].each do |instance|
        instance_ids << instance
      end
    rescue Net::HTTPServerException => e
      Rails.logger.error("Node.query_chef(#{attribute}:#{search}): Chef API search failed")
      exit 1
    end
    instance_ids
  end

  # Removes node from chef based on node name, in this case instance id from AWS
  def self.delete_chef_node(node_name)
    begin
      Chef::REST.new(Chef::Config[:chef_server_url]).delete_rest("nodes/#{node_name}")
    rescue Net::HTTPServerException
      Rails.logger.error("Node.delete_chef_node: Unable to delete chef node #{instance_id}")
      false
    end
  end
  
  # Removes client from chef based on client name, in this case instance id from AWS
  def self.delete_chef_client(client_name)
    begin
      Chef::REST.new(Chef::Config[:chef_server_url]).delete_rest("clients/#{client_name}")
    rescue Net::HTTPServerException
      Rails.logger.error("Node.delete_chef_client: Unable to delete chef client #{instance_id}")
      false
    end
  end
  
  # Removes node and client from Chef as well as uses Right AWS method for shutdown of instance
  def self.shutdown_instance(instance_id, farm_name)
    chef_aware = Object.new
    conn = Connect.new
    
    conn.set_region(Farm.find_by_name(farm_name).avail_zone)
    
    begin
      if Node.load(instance_id)
        chef_aware = true
      else
        chef_aware = false
      end
    rescue Net::HTTPServerException
      chef_aware = false
    end
        
    begin
      if chef_aware
        instance = conn.fog.servers.get(instance_id).destroy
        node_client_name = Node.id_to_name(instance_id)
        self.delete_chef_node(node_client_name)
        self.delete_chef_client(node_client_name)
      else
        instance = conn.fog.servers.get(instance_id).destroy
      end
    rescue
      Rails.logger.error("Node.shutdown_instance: Unable to shutdown #{instance_id} properly.")
    end
  end
  
  # Wrapper for Right AWS describe_spot_instance_requests method, Fog not capable currently.
  def self.describe_spot_instance_request(spot_instance_request_id)
    begin
      conn = Connect.new
      conn.set_region(self.region)
      conn.right_ec2.describe_spot_instance_requests(spot_instance_request_id)[0]
    rescue => e
      puts e.backtrace
      Rails.logger.error("Node.describe_spot_instance_request: Unable to get details on spot instance request id #{spot_instance_request_id}.")
      return nil
    end
  end
  
  def self.get_avail_zones()
    conn = Connect.new
    avail_zones = Array.new
    azs = Array.new
    
    azs += conn.right_ec2.describe_availability_zones
    conn.switch_region
    azs += conn.right_ec2.describe_availability_zones
    
    azs.each do |az|
      if az[:zone_state] == "available"
        avail_zones << az[:zone_name]
      end
    end
    avail_zones
  end
  
  # Sets @aws_state, @hostname
  def get_instance_status()
    if @instance_id == nil
      return false
    else
      conn = Connect.new
          
      begin
        instance = conn.right_ec2.describe_instances(@instance_id)[0]
        @region = conn.region
        @aws_state = instance[:aws_state]
        @hostname = instance[:dns_name]
        @launch_time = instance[:aws_launch_time].to_time
        return true
      rescue RightAws::AwsError
        conn.switch_region
        instance = conn.right_ec2.describe_instances(@instance_id)[0]
        @region = conn.region
        @aws_state = instance[:aws_state]
        @hostname = instance[:dns_name]
        @launch_time = instance[:aws_launch_time].to_time
        return true
      end
    end
  end
  
  # Returns i386 or x86_64, require Amazon Image ID
  def self.get_arch(ami_id)
    begin
      conn = Connect.new
      conn.set_region(self.region)
      conn.right_ec2.describe_images(ami_id)[0][:aws_architecture]
    rescue
      Rails.logger.error("Node.get_arch: Unable to retrieve architecture for #{ami_id}. Most likely invalid AMI ID.")
      return "i386"
    end
  end
  
  def self.wait_for_ssh(host)
    available = false
    while available == false
      begin
        timeout(5) do
          s = TCPSocket.new(host, "ssh")
          s.close
        end
      rescue Errno::ECONNREFUSED
        #available = false
        sleep(5)
        Rails.logger.debug("Not available: REFUSED connection to host: #{host}")
        retry if available == false
      rescue Timeout::Error, StandardError
        #available = false
        sleep(5)
        Rails.logger.debug("Not available: ERROR connection to host: #{host}")
        retry if available == false
      end
      available = true
    end
    return true
  end
  
  def instance_bootstrap(farm_name)
    begin
      bootstrap = Chef::Knife::Bootstrap.new
      bootstrap.name_args = @hostname
      # Comma separated list of roles/recipes to apply, getting role via Farm
      frm = Farm.find_by_name(farm_name)
      bootstrap.config[:run_list] = "role[#{frm.role}]"
      bootstrap.config[:ssh_user] = Chef::Config[:knife][:ssh_user]
      # The SSH identity file used for authentication
      bootstrap.config[:identity_file] = Chef::Config[:knife][:ssh_client_key_dir] + frm.keypair + ".pem"
      # The Chef node name for your new node
      bootstrap.config[:chef_node_name] = @instance_id
      # This is if you want pre-release Chef client gems to be installed
      #bootstrap.config[:prerelease] = config[:prerelease]
      # Bootstrap a distro using a template
      #bootstrap.config[:distro] = config[:distro]
      bootstrap.config[:use_sudo] = true
      # Full path to location of template to use
      #bootstrap.config[:template_file] = config[:template_file]
      # Not sure environment is even used since I couldn't find it referenced in › chef› lib› chef› knife› bootstrap.rb
      #bootstrap.config[:environment] = config[:environment]
      bootstrap
    rescue
      Rails.logger.error("Node.instance_bootstrap: Unable to boostrap instance #{@instance_id}")
      return nil
    end
  end
  
end
