require 'test_helper'

class RoleTest < Test::Unit::TestCase

  def test_role_load
    chef_role = Role.load(Role.list().first[0])
    assert_instance_of(Chef::Role, chef_role)
  end
  
  def test_role_list
    Role.list().each do |role_name, sys_url|
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
  
  def test_get_roles
    role_array = Role.get_roles.each do |role|
      assert_instance_of(Chef::Role, role)
    end
    assert_instance_of(Array, role_array)
  end

end
