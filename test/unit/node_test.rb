require 'test_helper'

class NodeTest < Test::Unit::TestCase
  
  def test_node_list
    Node.list().each do |node_name, sys_url|
      response = Net::HTTP.get_response(URI.parse(sys_url))
      case response
      when Net::HTTPSuccess
        assert true
      when Net::HTTPUnauthorized
        assert true
      else
        assert false
      end
    end
  end
  
  def test_node_load
    chef_node = Node.load(Node.list().first[0])
    assert_instance_of(Chef::Node, chef_node)
  end
  
  def test_cpu_util
    chef_node = Node.load(Node.list().first[0])
    util = Node.cpu_util(chef_node.ec2.instance_id)
    assert_instance_of(Float, util)
    assert(util > 0.00)
  end
  
  def test_get_ec2
    ec2_result = Node.get_ec2
    assert_instance_of(Array, ec2_result)
    assert(ec2_result[0]["instance_id"] != nil)
  end
  
  def test_instance_match
    fake_instance_id = "i-abcd1234"
    chef_node = Node.load(Node.list().first[0])
    real_instance_id = chef_node.ec2.instance_id
    should_match = Node.instance_match(real_instance_id)
    shouldnt_match = Node.instance_match(fake_instance_id)
    assert(should_match == true)
    assert(shouldnt_match == false)
  end
  
  def test_set_farm_name
    begin
      @chef_node = Node.load(Node.list().first[0])
      @orig_farm_name = @chef_node.attribute["qips_farm"]
      Node.set_farm_name(@chef_node.ec2.instance_id, "Hunky Dory")
      
      #Do it again to test if change took
      @chef_node = Node.load(Node.list().first[0])
      farm_name = @chef_node.attribute["qips_farm"]
      
      #Revert farm name
      Node.set_farm_name(@chef_node.ec2.instance_id, @orig_farm_name)     
      
      assert(farm_name == "Hunky Dory")
    rescue
      # At least revert farm name
      Node.set_farm_name(@chef_node.ec2.instance_id, @orig_farm_name)
    end
  end
      
  def test_set_qips_status
    begin
      @chef_node = Node.load(Node.list().first[0])
      @orig_node_status = @chef_node.attribute["qips_status"]
      Node.set_qips_status(@chef_node.ec2.instance_id, "Hunky Dory")
      
      #Do it again to test if change took
      @chef_node = Node.load(Node.list().first[0])
      node_status = @chef_node.attribute["qips_status"]
      
      #Revert farm name
      Node.set_qips_status(@chef_node.ec2.instance_id, @orig_node_status)    
      
      assert(node_status == "Hunky Dory")
    rescue
      # At least revert farm name
      Node.set_qips_status(@chef_node.ec2.instance_id, @orig_node_status)
    end
  end
  
  def test_query_chef
    chef_node = Node.load(Node.list().first[0])
    result = Node.query_chef("node", "instance_id", chef_node.ec2.instance_id)
    assert_instance_of(Array, result, "Is not an array as expected")
    assert(result[0].name == chef_node.name, "Does not have the node name we expected")
  end
  
  # def test_delete_client
  #  # Create a node just to test our delete_node method
  #  begin
  #    test_client_name = "simonsays"
  #    test_client = Chef::ApiClient.new()
  #    test_client.name(test_client_name)
  #    test_client.save(true, false)
  #    
  #    # Actual Test
  #    Node.delete_chef_node(test_client_name)
  #   
  #    # Assertion
  #    assert(Node.query_chef("client", "name", test_client_name) == nil)
  #  rescue => e
  #    puts e.backtrace
  #  end
  # end
  
  
  def test_delete_node
   # Create a node just to test our delete_node method
   begin
     test_node_name = "simonsays"
     test_node = Chef::Node.new()
     test_node.name(test_node_name)
     test_node.create
     
     # Actual Test
     Node.delete_chef_node(test_node_name)
    
     # Assertion
     assert(Node.query_chef("node", "name", test_node_name).empty?)
   rescue => e
     #puts e.backtrace
   end
  end
  
  def test_get_arch
    assert(Node.get_arch("ami-f0e20899") == "i386")
    assert(Node.get_arch("ami-fae20893") == "x86_64")
  end
      
end
