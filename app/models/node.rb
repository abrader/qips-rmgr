class Node < ActiveRecord::Base
  
  @@connection = Fog::Compute.new(
    :provider => 'AWS',
    :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
    :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]#,
    #:region => Chef::Config[:knife][:region]
  )
  
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
  
end
