task :environment

namespace :rmgr do
  
  desc "Run all tasks necessary for QIPS RMGR to run properly"
  task :all => ['redis','resque']
  
  desc "Start redis-server"
  task :redis => ['redis:start']
  
  desc "Start a resque worker"
  task :resque_worker => ['resque:work']

end