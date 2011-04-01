class ApplicationController < ActionController::Base
  protect_from_forgery
  
  before_filter :authenticate
  #USERS = { "lifo" => "world" }
  def authenticate
    authenticate_or_request_with_http_digest("Application") do |name|
      QIPS_USER[name]
    end
  end
  
end
