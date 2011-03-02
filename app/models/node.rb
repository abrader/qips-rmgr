class Node < ActiveRecord::Base
  
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
  
  # Return an array of system information pertaining to nodes only
  def self.get_nodes
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
