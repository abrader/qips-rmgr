class NodesController < ApplicationController
  respond_to :html, :xml, :json
  
  include ActionView::Helpers::DateHelper
  
  def index
    begin
      @farms = Farm.all
      @ec2_instances = Node.get_ec2
    rescue => e
      Rails.logger.error("NodesController.index: Unable to display list of nodes.")
    end
    respond_with(@farms, @ec2_instances)
  end
  
  def idle_status
    begin
      Node.set_qips_status(params[:id], "idle")
      respond_to do |format|
        format.html { redirect_to nodes_url}
        format.xml  { head :ok }
        format.json  { head :ok }
      end
    rescue
      Rails.logger.error("NodesController.idle_status: Unable to set #{params[:id]} to idle status.")
    end
  end
  
  def busy_status
    begin
      Node.set_qips_status(params[:id], "busy")
      respond_to do |format|
        format.html { redirect_to nodes_url}
        format.xml  { head :ok }
        format.json  { head :ok }
      end
    rescue
      Rails.logger.error("NodesController.busy_status: Unable to set #{params[:id]} to busy status.")
    end
  end
  
  def destroy
    begin
      if params[:id] then
        @instance_id = params[:id]
        Node.shutdown_instance(@instance_id)
        redirect_to nodes_path, :notice => "#{@instance_id} was shutdown successfully."
      end
    rescue => e
      puts e.backtrace
      Rails.logger.error("NodesController.destroy: Could not delete chef client and shutdown instance associated with #{params[:id]}")
      redirect_to nodes_path
    end
  end
end
