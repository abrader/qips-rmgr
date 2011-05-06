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
  
  def bind_instance_region(instance_id)
    begin
      self.right_ec2.describe_instances(instance_id)
      return self.region
    rescue RightAws::AwsError
      self.switch_region
      self.right_ec2.describe_instances(instance_id)
      return self.region
    end
  end
  
  def bind_spot_instance_region(spot_instance_request_id)
    begin
      self.right_ec2.describe_spot_instance_requests(spot_instance_request_id)
      return self.region
    rescue RightAws::AwsError
      self.switch_region
      self.right_ec2.describe_spot_instance_requests(spot_instance_request_id)
      return self.region
    end
  end
  
  def bind_image_region(ami_id)
    begin
      self.right_ec2.describe_images(ami_id)
      return self.region
    rescue RightAws::AwsError
      self.switch_region
      self.right_ec2.describe_images(ami_id)
      return self.region
    end
  end    
  
  def switch_region
    if self.region == "east"
      self.set_west
    elsif self.region == "west"
      self.set_east
    else
      Rails.logger.error("Connect.switch_region: Connect object doesn't have region set.")
    end
  end
  
  def set_west
    begin
      @fog = Fog::Compute.new(
        :provider => 'AWS',
        :region => 'us-west-1',
        :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
        :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]
      )
    
      @right_ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key], :region => 'us-west-1')

      @right_acw = RightAws::AcwInterface.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key], :region => 'us-west-1')

      @region = "west"
      return true
    rescue
      return false
    end
  end
  
  def set_east
    begin
      @fog = Fog::Compute.new(
        :provider => 'AWS',
        :region => 'us-east-1',
        :aws_access_key_id => Chef::Config[:knife][:aws_access_key_id],
        :aws_secret_access_key => Chef::Config[:knife][:aws_secret_access_key]
      )
    
      @right_ec2 = RightAws::Ec2.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key], :region => 'us-east-1')

      @right_acw = RightAws::AcwInterface.new(Chef::Config[:knife][:aws_access_key_id], Chef::Config[:knife][:aws_secret_access_key], :region => 'us-east-1')
      
      @region = "east"
      return true
    rescue
      return false
    end  
  end
end