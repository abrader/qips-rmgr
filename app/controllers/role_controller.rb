class RoleController < ApplicationController
  respond_to :html, :xml, :json
  
  def index
   @role_list =  begin
                  Chef::Role.list()
                 rescue => e
                   Chef::Log.error("#{e}\n#{e.backtrace.join("\n")}")
                   @_message = {:error => "Could not list roles"}
                   {}
                 end
   respond_with(@role_list)
  end

  def show
    @role = begin
              Chef::Role.load(params[:id])
            rescue => e
              Chef::Log.error("#{e}\n#{e.backtrace.join("\n")}")
              @_message = {:error => "Could not load role #{params[:id]}"}
              Chef::Role.new
            end
    render
  end
  
  def create
    begin
      @role = Chef::Role.new
      @role.name(params[:name])
      @role.env_run_lists(params[:env_run_lists])
      @role.description(params[:description]) if params[:description] != ''
      @role.default_attributes(Chef::JSON.from_json(params[:default_attributes])) if params[:default_attributes] != ''
      @role.override_attributes(Chef::JSON.from_json(params[:override_attributes])) if params[:override_attributes] != ''
      @role.create
      redirect(url(:roles), :message => { :notice => "Created Role #{@role.name}" })
    rescue => e
      Chef::Log.error("#{e}\n#{e.backtrace.join("\n")}")
      @available_recipes = list_available_recipes
      @available_roles = Chef::Role.list.keys.sort
      @role = Chef::Role.new
      @role.default_attributes(Chef::JSON.from_json(params[:default_attributes])) if params[:default_attributes] != ''
      @role.override_attributes(Chef::JSON.from_json(params[:override_attributes])) if params[:override_attributes] != ''
      @run_list = Chef::RunList.new.reset!(Array(params[:for_role]))
      @_message = { :error => "Could not create role" }
      render :new
    end  
  end

  def edit
  end

  def destroy
  end

end
