class NodesController < ApplicationController
  respond_to :html, :xml, :json
  
  include ActionView::Helpers::DateHelper
  
  def index
    begin
      @servers = Node.get_servers
      @compute = Node.get_compute
      @ec2_instances = Node.get_ec2
    rescue => e
      Chef::Log.error("#{e}\n#{e.backtrace.join("\n")}")
      @_message = {:error => "Could not list nodes"}
      {}
    end
    respond_with(@compute, @servers, @ec2_instances)
  end
  
  def destroy
    begin
      if params[:id] then
        @instance_id = params[:id]
        Node.shutdown_instance(@instance_id)
        redirect_to nodes_url, :notice => "#{@instance_id} was shutdown successfully."
      end
    rescue => e
      puts e.backtrace
      Rails.logger.error("Could not delete chef client and shutdown instance associated with #{:instance_id}")
      render :index
    end
  end
  
  def reconcile
    begin
      @resp = Node.reconcile_nodes()
      redirect_to nodes_path, :notice => "Reconciliation was handled successfully."
    rescue
      puts e.backtrace
      Rails.logger.error("NodesController.reconcile: Unable to reconcile nodes")
      render :index
    end
  end
end
