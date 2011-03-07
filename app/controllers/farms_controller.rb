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
    
    respond_with(@farm)
  end

  def destroy
    begin
      @farm = Farm.find(params[:id])
      #@farm.destroy
      redirect_to farms_path, :notice => "Farm #{@farm.name} deleted successfully."
    rescue => e
      puts e.backtrace
      @farms = Farm.all
      @_message = {:error => "Could not delete farm #{params[:id]}"}
      render :index
    end
  end

end
