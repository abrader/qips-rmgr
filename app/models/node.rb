class Node
  attr_accessor :instance_id, :sir_state, :aws_state, :hostname, :spot_instance_request_id
  
  require 'chef/knife/bootstrap'
  require 'chef/knife/ssh'
  
  @@connection = Fog::Compute.new(
    :provider => 'AWS',
    :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
    :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]
  )
  
  @@ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])
  
  @@acw = RightAws::AcwInterface.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])
  
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
    stats = @@acw.get_metric_statistics(:start_time => (Time.now.utc - 6*60), :period => 60, :namespace => "AWS/EC2", :dimentions => {:InstanceId => instance_id}, :measure_name=>"CPUUtilization")
    avg = 0.0
    stats[:datapoints].each do |stat|
      avg + stat[:average]
    end
    avg = avg / 5
    avg
  end
  
  def self.get_ec2
     # TODO remove instances that appear in get_servers and get_compute methods 
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
     self.get_servers().each do |node|
       if instance_id == node.ec2.instance_id then
         return true
       end
     end
     self.get_compute().each do |node|
       if instance_id == node.ec2.instance_id then
         return true
       end
     end
     false
   end  
  
  # Return an array of system information pertaining to servers only
  def self.get_servers
    @servers = Array.new
    self.list().each do |name, sys_url|
      currrent_sys = self.load(name)
      if currrent_sys.ec2.security_groups[0] =~ /www/
        currrent_sys.chef_url = sys_url.gsub(/4000/, '4040')
        currrent_sys.save
        @servers << currrent_sys
      end
    end
    @servers
  end
  
  # Return an array of system information pertaining to compute nodes only
  def self.get_compute
    @nodes = Array.new
    self.list().each do |name, sys_url|
      currrent_sys = self.load(name)
      if currrent_sys.ec2.security_groups[0] =~ /compute/
        currrent_sys.chef_url = sys_url.gsub(/4000/, '4040')
        currrent_sys.save
        @nodes << currrent_sys
      end
    end
    @nodes
  end
  
  def start_by_spot_request(farm_name, image_id=Chef::Config[:knife][:image], spot_price=Chef::Config[:knife][:spot_price])
    # This is the AWS reduced cost spot request
    require 'net/ssh/multi'
    
    instance = nil
    
    sir = @@ec2.request_spot_instances(
            :image_id => image_id,
            :spot_price => spot_price,
            :key_name => Chef::Config[:knife][:aws_ssh_key_id],
            :instance_count => 1,
            :monitoring_enabled => true,
            :launch_group => 'QIPS_dev',
            :groups => Chef::Config[:knife][:security_groups],
            :instance_type => Chef::Config[:knife][:flavor]
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

    # Must wait a min or so for system to come up for SSH to be responsive enough in order to avoid failure
    sleep(60)

    # Time to get that instance boostrapped with Chef-client
    instance_bootstrap(farm_name).run
    
    # Now the chef-client is running on our instance, let's get it bound to it's role, this should get recipes flowing.
    #set_run_list(farm_name)
    
    # Set farm attribute so we can retrieve from OHAI later.
    set_farm_attrib(farm_name)
  end
  
  def set_run_list(farm_name)
    begin
      @role_name = Farm.find_by_name(farm_name).role
      chef_role = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("roles/#{@role_name}")
      chef_node = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("nodes/#{@instance_id}")
      chef_node.run_list = chef_role.run_list
      chef_node.save
    rescue
      puts e.backtrace
      Rails.logger.error("Nodes.bind_run_list: Unable to bind #{@role_name} to #{@instance_id}")
    end
  end
  
  def set_farm_attrib(farm_name)
    begin
      node = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("nodes/#{@instance_id}")
      node.attribute["qips_farm"] = farm_name
      node.save
    rescue
      Rails.logger.error("Node.set_farm_attrib: Unable to set attribute for #{farm_name} farm to #{@instance_id}")
    end
  end

  def self.delete_chef_node(client_name)
    begin
      Chef::REST.new(Chef::Config[:chef_server_url]).delete_rest("nodes/#{client_name}")
    rescue Net::HTTPServerException
      false
    end
  end
  
  def self.delete_chef_client(client_name)
    begin
      Chef::REST.new(Chef::Config[:chef_server_url]).delete_rest("clients/#{client_name}")
    rescue Net::HTTPServerException
      false
    end
  end
  
  def self.shutdown_instance(instance_id)
    self.delete_chef_node(instance_id)
    self.delete_chef_client(instance_id)
    @@ec2.terminate_instances(instance_id)
  end
  
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
        puts ("Not available: REFUSED connection to host: #{host}")
        retry if available == false
      rescue Timeout::Error, StandardError
        #available = false
        sleep(5)
        puts ("Not available: ERROR connection to host: #{host}")
        retry if available == false
      end
      available = true
    end
    return true
  end
  
  def instance_bootstrap(farm_name)
    begin
      # FIXME run_list thinks role is a recipe and determines it can't find it.
      @role_name = Farm.find_by_name(farm_name).role
      chef_role = Chef::REST.new(Chef::Config[:chef_server_url]).get_rest("roles/#{@role_name}")
      
      bootstrap = Chef::Knife::Bootstrap.new
      bootstrap.name_args = @hostname
      # TODO @name_args is argv on the command line for Knife, need to replace with proper runlist.
      # Comma separated list of roles/recipes to apply
      bootstrap.config[:run_list] = chef_role
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
  
  def self.reconcile_nodes()
    Node.get_compute.each do |comp|
      instance = @@ec2.describe_instances(comp.ec2.instance_id)[0]
      uptime_sec  = (Time.now.to_i - DateTime.parse(instance[:aws_launch_time]).to_i)
      if (uptime_sec % (60 * 60)) >= 3120 # 3120 = 52 minutes * 60 secs
        if self.cpu_util(comp.ec2.instance_id) < 0.2 then
          Rails.logger.info("Node.reconcile_nodes: Shutting down #{comp.ec2.instance_id} due to inactivity.")
          #Node.shutdown_instance(comp.ec2.instance_id)
        else
          Rails.logger.info("Node.reconcile_nodes: #{comp.ec2.instance_id} will not be shutdown due to activity")
        end
      else
        Rails.logger.info("Node.reconcile_nodes: #{comp.ec2.instance_id} will not be shutdown due to incompatible interval")
      end
    end    
  end
  
end
