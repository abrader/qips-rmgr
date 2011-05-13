require 'fog'
require 'right_aws'
require 'chef'
#RMGR config file that contains sensitive config information pertaining to AWS and Chef
require File.join(File.dirname(__FILE__), '../config/rmgr-config')

class Connect
  
  attr_accessor :fog, :right_ec2, :right_acw, :region
  
  @fog = nil
  @right_ec2 = nil
  @right_acw = nil
  @region = nil
  
  def initialize
    begin
      @fog = Fog::Compute.new(
        :provider => 'AWS',
        :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
        :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]
      )
    
      @right_ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])

      @right_acw = RightAws::AcwInterface.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key])
      
      @region = "east"
      return true
    rescue
      return false
    end
  end 
  
  def switch_region
    if self.region == "east"
      self.set_region("west")
    elsif self.region == "west"
      self.set_region("east")
    else
      Rails.logger.error("Connect.switch_region: Connect object doesn't have region set.")
    end
  end
  
  # Will accept "east" or "west"
  def set_region(rgn) 
    begin
      location = String.new
      
      if rgn =~ /west/
        location =  "us-west-1"
      else
        location = "us-east-1"
      end
      
      @fog = Fog::Compute.new(
        :provider => 'AWS',
        :region => location,
        :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
        :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]
      )

      @right_ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key], :region => location)

      @right_acw = RightAws::AcwInterface.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key], :region => location)

      @region = rgn
      return true
    rescue
      return false
    end
  end    
end