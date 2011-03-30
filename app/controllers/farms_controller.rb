class FarmsController < ApplicationController
  respond_to :html, :xml, :json
  
  def index
    @farms = Farm.all

    respond_with(@farms)
  end
  
  def new
    @farm = Farm.new()
    if @farm.save
      redirect_to farms_path, :notice => "Successfully created a farm."
    else
      render :action => 'new'
    end
  end

  def show
  end

  def edit
    @farm = Farm.find(params[:id])
    @roles = Role.get_roles
    
    respond_with(@farm, @roles)
  end
  
  def update
    @farm = Farm.find(params[:id])
    
    if @farm.update_attributes(params[:farm])
      redirect_to farms_path, :notice => "Farm #{@farm.name} was updated successfully."
    else
      render :action => "edit"
    end 
  end
  
  def start
    begin
      @farm = Farm.find_by_name(params[:name])
      @farm.start_instances(params[:num_instances])
      redirect_to farms_path, :notice => "Started #{params[:num_instances]} of #{@farm.name}."
    rescue => e
      puts e.backtrace
      @_message = {:error => "Unable to start #{params[:num_instances]} of #{@farm.name}"}
      render :index
    end
  end

  def destroy
    begin
      @farm = Farm.find(params[:id])
      #@farm.destroy
      redirect_to farms_path, :notice => "Farm #{@farm.name} was deleted successfully."
    rescue => e
      puts e.backtrace
      @farms = Farm.all
      @_message = {:error => "Could not delete farm #{params[:id]}"}
      render :index
    end
  end
end
