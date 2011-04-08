class Node
  attr_accessor :instance_id, :sir_state, :aws_state, :hostname, :spot_instance_request_id
  
  require 'chef/knife/bootstrap'
  require 'chef/knife/ssh'
  require 'chef/search/query'
  require 'resque'
  
  DEFAULT_32_INSTANCE_TYPE = "m1.small"
  DEFAULT_64_INSTANCE_TYPE = "m1.large"
  
  @@connection = Fog::Compute.new(
    :provider => 'AWS',
    :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
    :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]
  )
  
  @@ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])
  
  @@acw = RightAws::AcwInterface.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])
  
  @queue = :aws_spot_instance_requests
  
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
  
  def self.cpu_util(instance_id)
    util_over_time = 10 # min
    stats = @@acw.get_metric_statistics(:start_time => (Time.now.utc - (util_over_time * 60)), :period => 60, :namespace => "AWS/EC2", :dimentions => {:InstanceId => instance_id}, :measure_name=>"CPUUtilization")
    avg = 0.0
    stats[:datapoints].each do |stat|
      avg = avg + stat[:average]
    end
    avg = avg / util_over_time
    avg
  end
  
  def self.get_ec2
    @ec2_info = Array.new

    @@connection.servers.all.each do |instance|
      if self.instance_match(instance.id.to_s) == false
        ec2_instance = Hash.new
        ec2_instance["private_dns"] = instance.private_dns_name
        ec2_instance["public_dns"] = instance.dns_name
        ec2_instance["instance_id"] = instance.id.to_s
        ec2_instance["ami_id"] = instance.image_id
        ec2_instance["uptime_seconds"] = (Time.now.to_i - instance.created_at.to_i)
        ec2_instance["state"] = instance.state
        @ec2_info << ec2_instance
      end
    end
    @ec2_info
  end
   
  #Check to see if an instance_id already exists in local record
  def self.instance_match(instance_id)
    Node.list().each do |node_name, sys_url|
      if instance_id == Node.load(node_name).ec2.instance_id
        return true
      end
    end
    false
  end  
  
  def start_by_spot_request(farm_name, image_id, ami_type, spot_price)
    # This is the AWS reduced cost spot request
    require 'net/ssh/multi'
    
    instance = nil
    
    if ami_type == nil
      arch = Node.get_arch(image_id)
      if arch == "i386"
        ami_type = DEFAULT_32_INSTANCE_TYPE
      else
        ami_type = DEFAULT_64_INSTANCE_TYPE
      end
    end
    
    sir = @@ec2.request_spot_instances(
            :image_id => image_id,
            :spot_price => spot_price,
            :key_name => Chef::Config[:knife][:aws_ssh_key_id],
            :instance_count => 1,
            :monitoring_enabled => true,
            :launch_group => 'QIPS_dev',
            :groups => Chef::Config[:knife][:security_groups],
            :instance_type => ami_type
    )
    
    @spot_instance_request_id = sir[0][:spot_instance_request_id]
    
    # Must hang in a loop until Amazon issues us a instance id
    while @instance_id == nil
      sleep(5)
      status = Node.describe_spot_instance_request(@spot_instance_request_id) 
      @instance_id = status[:instance_id]
      @sir_state = status[:state]
      break if (@sir_state == nil || @sir_state == "cancelled" || @sir_state == "failed")
    end
    
    # Get the status of our instance now that we have an instance ID
    self.get_instance_status
    
    # Once we're done with the spot instance request we can cancel it
    @@ec2.cancel_spot_instance_requests(@spot_instance_request_id)
    
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
    instance_bootstrap(farm_name).run
    
    # Set farm attribute so we can retrieve from OHAI later.
    set_farm_attrib(farm_name)
  end
  
  # Resque method called by Farm to instantiate a spot instance request via queue
  def self.async_start_by_spot_request(farm_name, image_id=Chef::Config[:knife][:image], ami_type=nil, spot_price=Chef::Config[:knife][:spot_price])
    Resque.enqueue(Node, farm_name, image_id, ami_type, spot_price)
  end
  
  # Resque required method for calling start_by_spot_request via queue
  def self.perform(farm_name, image_id, ami_type, spot_price)
    n = Node.new
    n.start_by_spot_request(farm_name, image_id, ami_type, spot_price)
  end
  
  def set_farm_attrib(farm_name)
    begin
      Node.set_farm_name(@instance_id, farm_name)
      Node.set_qips_status(@instance_id, "idle")
    rescue
      Rails.logger.error("Node.set_farm_attrib: Unable to set attribute for #{farm_name} farm to #{@instance_id}")
    end
  end
  
  def self.set_farm_name(instance_id, farm_name)
    begin
      node = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("nodes/#{instance_id}")
      node.attribute["qips_farm"] = farm_name
      node.save
    rescue
      Rails.logger.error("Node.set_farm_name: Unable to set #{instance_id} to farm #{farm_name}.")
    end
  end
  
  # Sets QIPS status, extra step due to non-compliance of instance_id == node name
  def self.set_qips_status(instance_id, status)
    begin
      node_name = Node.query_chef("node", "instance_id", instance_id)[0].name
      node = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("nodes/#{node_name}")
      node.attribute["qips_status"] = status
      node.save
    rescue
      Rails.logger.error("Node.set_qips_status: Unable to set QIPS #{status} status for #{instance_id}.")
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
  def self.delete_chef_node(client_name)
    begin
      Chef::REST.new(Chef::Config[:chef_server_url]).delete_rest("nodes/#{client_name}")
    rescue Net::HTTPServerException
      false
    end
  end
  
  # Removes client from chef based on client name, in this case instance id from AWS
  def self.delete_chef_client(client_name)
    begin
      Chef::REST.new(Chef::Config[:chef_server_url]).delete_rest("clients/#{client_name}")
    rescue Net::HTTPServerException
      false
    end
  end
  
  # Removes node and client from Chef as well as uses Right AWS method for shutdown of instance
  def self.shutdown_instance(instance_id)
    begin
      self.delete_chef_node(instance_id)
      self.delete_chef_client(instance_id)
      @@ec2.terminate_instances(instance_id)
    rescue => e
      Rails.logger.error("Node.shutdown_instance: Unable to shutdown #{instance_id} properly.")
    end
  end
  
  # Wrapper for Right AWS describe_spot_instance_requests method
  def self.describe_spot_instance_request(spot_request_id)
    @@ec2.describe_spot_instance_requests(spot_request_id)[0]
  end
  
  # Sets @aws_state, @hostname
  def get_instance_status()
    if @instance_id == nil
      return false
    else
      instance = @@ec2.describe_instances(@instance_id)[0]
      @aws_state = instance[:aws_state]
      @hostname = instance[:dns_name]
    end    
  end
  
  # Returns i386 or x86_64, require Amazon Image ID
  def self.get_arch(ami_id)
    @@ec2.describe_images(ami_id)[0][:aws_architecture]
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
      @role_name = Farm.find_by_name(farm_name).role
      bootstrap.config[:run_list] = "role[#{@role_name}]"
      bootstrap.config[:ssh_user] = Chef::Config[:knife][:ssh_user]
      # The SSH identity file used for authentication
      bootstrap.config[:identity_file] = Chef::Config[:knife][:ssh_client_key]
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
    end
  end
  
end
