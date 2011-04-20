QipsRmgr::Application.routes.draw do
  resources :roles
  
  resources :farms do
    collection do
      get 'reconcile'
    end
  end
  
  resources :nodes do
    member do
      get 'shutdown', :action => 'destroy'
    end
    
    member do
      get 'busy', :action => 'busy_status'
    end
    
    member do
      get 'idle', :action => 'idle_status'
    end
  end
  
  match "farms/start/:name/:num_instances" => "farms#start", :as => 'farm_start'
  
  root :to => "farms#index"