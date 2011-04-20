class RolesController < ApplicationController
  respond_to :html, :xml, :json
  
  def index
    begin
      @roles = Role.get_roles
    rescue => e
      Rails.logger.error("RolesController: Unable to get list of roles from Chef server [#{Chef::Config[:chef_server_url]}]")
    end
    respond_with(@roles)
  end
end