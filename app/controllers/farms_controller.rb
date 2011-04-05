class FarmsController < ApplicationController
  respond_to :html, :xml, :json
  
  INSTANCE_TYPES_32 = ['m1.small', 'c1.medium']
  INSTANCE_TYPES_64 = ['m1.large','m1.xlarge', 'c1.xlarge', 'm2.xlarge', 'm2.2xlarge', 'm2.4xlarge']
  
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
    @instance_types
    @farm = Farm.find(params[:id])
    @roles = Role.get_roles
    
    arch = Node.get_arch(@farm.ami_id)
    
    if arch == "i386"
      @instance_types = INSTANCE_TYPES_32
    else
      @instance_types = INSTANCE_TYPES_64
    end
    
    respond_with(@farm, @roles, @instance_types)
  end
  
  def update
    begin
      @farm = Farm.find(params[:id])
    
      if @farm.update_attributes(params[:farm])
        redirect_to farms_path, :notice => "Farm #{@farm.name} was updated successfully."
      else
        render :action => "edit"
      end
    rescue
      Rails.logger.error("FarmsController.update: Unable to update #{params[:id]}")
    end
  end
  
  def start
    begin
      @farm = Farm.find_by_name(params[:name])
      @farm.start_instances(params[:num_instances].to_i)
      redirect_to farms_path, :notice => "Started #{params[:num_instances]} in #{params[:name]} successfully."
    rescue
      Rails.logger.error("FarmsController.start: Unable to start #{params[:num_instances]} instances in #{params[:name]}")
      render :index
    end
  end

  def destroy
    begin
      @farm = Farm.find(params[:id])
      #@farm.destroy
      redirect_to farms_path, :notice => "Farm #{@farm.name} was deleted successfully."
    rescue
      Rails.logger.error("FarmsController.destroy: Unable to delete farm #{params[:id]}")
      render :index
    end
  end
  
  def reconcile
    begin
      @resp = Farm.reconcile_nodes()
      respond_to do |format|
        format.xml  { head :ok }
        format.json { head :ok }
      end
    rescue
      Rails.logger.error("FarmsController.reconcile: Unable to reconcile nodes")
      render :index
    end
  end
  
end
