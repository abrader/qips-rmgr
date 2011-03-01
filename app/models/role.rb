class Role < ActiveRecord::Base
  
  def chef_server_rest
     Chef::REST.new(Chef::Config[:chef_server_url])
   end

   def self.chef_server_rest
     Chef::REST.new(Chef::Config[:chef_server_url])
   end
   
   def self.load(name)
     chef_server_rest.get_rest("roles/#{name}")
   end

   # Get the list of all roles from the API.
   def self.list(inflate=false)
     if inflate
       response = Hash.new
       Chef::Search::Query.new.search(:role) do |n|
         response[n.name] = n unless n.nil?
       end
       response
     else
       chef_server_rest.get_rest("roles")
     end
   end
  
end
