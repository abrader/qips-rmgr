class NodeController < ApplicationController
  respond_to :html, :xml, :json
  
  include ActionView::Helpers::DateHelper
  
  def index
    begin
      @servers = Node.get_servers
      @nodes = Node.get_nodes
    rescue => e
      Chef::Log.error("#{e}\n#{e.backtrace.join("\n")}")
      @_message = {:error => "Could not list nodes"}
      {}
    end
    respond_with(@nodes, @servers)
  end
end
