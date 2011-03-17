class Node < ActiveRecord::Base
  
  require 'chef/knife/bootstrap'
  
  @@connection = Fog::Compute.new(
    :provider => 'AWS',
    :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
    :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]
  )
  
  @@ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])
  
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
  
  def self.start 
    #require 'fog'
    #require 'highline'
    require 'net/ssh/multi'
    #require 'readline'

    $stdout.sync = true

    server = @@connection.servers.create(
      :image_id => Chef::Config[:knife][:image],
      :groups => Chef::Config[:knife][:security_groups],
      :flavor_id => Chef::Config[:knife][:flavor],
      :key_name => Chef::Config[:knife][:aws_ssh_key_id],
      :availability_zone => Chef::Config[:availability_zone]
    )

    # wait for it to be ready to do stuff
    server.wait_for { print "."; ready? }

    print(".") until Node.ssh_available?(server.dns_name) { sleep @initial_sleep_delay ||= 10; puts("done") }

    #bootstrap_for_node(server).run
  end
  
  def self.start_with_spot_request
    server = @@ec2.request_spot_instances(
            :image_id => Chef::Config[:knife][:image],
            :spot_price => 0.05,
            :key_name => Chef::Config[:knife][:aws_ssh_key_id],
            :instance_count => 1,
            :groups => Chef::Config[:knife][:security_groups],
            :instance_type => Chef::Config[:knife][:flavor]
    )
    
    spot_instance_request_id = server[0][:spot_instance_request_id]
    instance_id = nil
    
    while instance_id == nil
      sleep(5)
      status = Node.describe_spot_instance_request(spot_instance_request_id) 
      instance_id = status[0][:instance_id]
      state = status[0][:state]
      break if (state == nil || state == "cancelled" || state == "failed")
    end
    
    instance_id
    
    # wait for it to be ready to do stuff
    #server.wait_for { print "."; ready? }

    #print(".") until Node.ssh_available?(server.dns_name) { sleep @initial_sleep_delay ||= 10; puts("done") }

    #bootstrap_for_node(server).run
  end
  
  def self.describe_spot_instance_request(spot_request_id)
    @@ec2.describe_spot_instance_requests(spot_request_id)
  end
  
  def self.ssh_available?(hostname)
    good_connect = false
    while good_connect == false
      sleep(3)
      tcp_socket = TCPSocket.new(hostname, 22)
      good_connect = IO.select([tcp_socket], nil, nil, 5)
      tcp_socket.close
      Chef::Log.debug("#{hostname} not accepting SSH connections quite yet")
    end
    Chef::Log.debug("sshd accepting connections on #{hostname}")
    true
  end
  
  def self.bootstrap_for_node(server)
    bootstrap = Chef::Knife::Bootstrap.new
    bootstrap.name_args = [server.dns_name]
    bootstrap.config[:run_list] = @name_args
    bootstrap.config[:ssh_user] = config[:ssh_user]
    bootstrap.config[:identity_file] = config[:identity_file]
    bootstrap.config[:chef_node_name] = config[:chef_node_name] || server.id
    bootstrap.config[:prerelease] = config[:prerelease]
    bootstrap.config[:distro] = config[:distro]
    bootstrap.config[:use_sudo] = true
    bootstrap.config[:template_file] = config[:template_file]
    bootstrap.config[:environment] = config[:environment]
    bootstrap
  end
  
  def self.reconcile_nodes()
    Node.get_compute.each do |comp|
      if comp.idletime_seconds > Chef::Config[:max_idle_seconds]
        #Shutdown node if this is a good metric
        puts "Time to shutdown #{comp.ec2.instance_id}"
      end
    end    
  end
  
end
