class FarmController < ApplicationController
  respond_to :html, :xml, :json
  
  def index
    @farms = Farm.all

    respond_with(@farms)
  end
  
  def create
    @farm = Farm.new(params[:farm])
    if @farm.save
      redirect_to @farm, :notice => "Successfully created a farm."
    else
      render :action => 'new'
    end
  end

  def show
    @farm = Farm.find(params[:farm])
    
    respond_with(@farm)
  end

  def edit
  end

  def destroy
  end

end
