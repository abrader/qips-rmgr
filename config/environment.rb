# Load the rails application
require File.expand_path('../application', __FILE__)

# Initialize the rails application
QipsRmgr::Application.initialize!

#RMGR config file that contains sensitive config information pertaining to AWS and Chef
require File.join(File.dirname(__FILE__), 'rmgr-config')
