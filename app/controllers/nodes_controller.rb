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
      if params[:instance_id] then
        @instance_id = params[:instance_id]
        Node.shutdown_instance(@instance_id)
        redirect_to nodes_url, :notice => "#{@instance_id} was shutdown successfully."
      end
    rescue => e
      puts e.backtrace
      @_message = {:error => "Could not delete chef client and shutdown instance associated with #{:instance_id}"}
      {}
    end
  end
  
  def reconcile
    begin
    rescue
    end
  end
end
