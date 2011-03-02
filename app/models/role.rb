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
   
   def self.get_roles
     @roles = Array.new
     Role.list().each do |name,role_url|
       current_role = Role.load(name)
       current_role.default_attributes["chef_url"] = role_url.gsub(/4000/, '4040')
       current_role.save
       @roles << current_role
     end
     @roles
   end
  
end
