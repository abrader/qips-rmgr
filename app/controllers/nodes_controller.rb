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
  
  def reconcile
    begin
    rescue
    end
  end
end
