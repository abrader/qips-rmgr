class RolesController < ApplicationController
  respond_to :html, :xml, :json
  
  def index
    begin
      @roles = Role.get_roles
    rescue => e
      Chef::Log.error("#{e}\n#{e.backtrace.join("\n")}")
      @_message = {:error => "Could not list roles"}
      {}
    end
    respond_with(@roles)
  end
end