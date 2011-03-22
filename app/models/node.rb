class Node < ActiveRecord::Base
  
  require 'chef/knife/bootstrap'
  require 'chef/knife/ssh'
  
  @@connection = Fog::Compute.new(
    :provider => 'AWS',
    :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
    :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]
  )
  
  @@ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])
  
  def after_initialize()
    @instance_id = nil
    @sir_state = nil
    @aws_state = nil
    @hostname = nil
    @instance_id = nil
    @spot_instance_request_id = nil
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
     match = false
     self.get_servers().each do |node|
       if instance_id == node.ec2.instance_id then
         match = true
       end
     end
     match
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
  
  def self.start_by_request
    # This is the AWS full cost request
    require 'net/ssh/multi'

    $stdout.sync = true

    instance = @@connection.servers.create(
      :image_id => Chef::Config[:knife][:image],
      :groups => Chef::Config[:knife][:security_groups],
      :flavor_id => Chef::Config[:knife][:flavor],
      :key_name => Chef::Config[:knife][:aws_ssh_key_id],
      :availability_zone => Chef::Config[:availability_zone]
    )

    # wait for it to be ready to do stuff
    server.wait_for { print "."; ready? }

    print(".") until Node.ssh_available?(instance.dns_name) { sleep @initial_sleep_delay ||= 10; puts("done") }

    #instance_bootstrap(instance).run
  end
  
  def start_by_spot_request
    # This is the AWS reduced cost spot request
    require 'net/ssh/multi'
    
    instance = nil
    
    sir = @@ec2.request_spot_instances(
            :image_id => Chef::Config[:knife][:image],
            :spot_price => 0.05,
            :key_name => Chef::Config[:knife][:aws_ssh_key_id],
            :instance_count => 1,
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

    # FIXME Something is getting hung up when Chef libs attempt to contact compute node via SSH
    # Time to get that instance boostrapped with Chef-client
    instance_bootstrap(instance).run
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
  
  def instance_bootstrap(instance)
    bootstrap = Chef::Knife::Bootstrap.new
    bootstrap.name_args = @hostname
    # TODO @name_args is argv on the command line for Knife, need to replace with proper runlist.
    # Comma separated list of roles/recipes to apply
    bootstrap.config[:run_list] = @name_args
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
  end
  
  def self.reconcile_nodes()
    Node.get_compute.each do |comp|
      if comp.idletime_seconds > Chef::Config[:max_idle_seconds]
        # TODO Shutdown node if this is a good metric
        puts "Time to shutdown #{comp.ec2.instance_id}"
      end
    end    
  end
  
end
