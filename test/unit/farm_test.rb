require 'test_helper'

class FarmTest < ActiveSupport::TestCase

  def test_farm_idle
    Farm.find(:all).each do |farm|
      instance_ids = farm.idle()
      assert_instance_of(Array, instance_ids)
    end
  end
  
  def test_running_instances
    Farm.find(:all).each do |farm|
      ri = farm.running_instances()
      assert_instance_of(Array, ri)
    end
  end
  
end
