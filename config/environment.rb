# Load the rails application
require File.expand_path('../application', __FILE__)

#RMGR config file that contains sensitive config information pertaining to AWS and Chef
require File.join(File.dirname(__FILE__), 'rmgr-config')

# Initialize the rails application - MUST BE LAST ITEM TO LOAD IN THIS FILE
QipsRmgr::Application.initialize!