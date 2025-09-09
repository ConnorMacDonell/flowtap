Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations',
    passwords: 'users/passwords',
    confirmations: 'users/confirmations'
  }
  
  # Admin authentication with custom path
  devise_for :admin_users, path: 'admin', controllers: {
    sessions: 'admin/sessions',
    passwords: 'admin/passwords'
  }
  
  # Dashboard route (protected)
  get '/dashboard', to: 'dashboard#index'
  
  # Settings routes (protected)
  get '/settings', to: 'settings#index'
  get '/settings/account', to: 'settings#account'
  get '/settings/notifications', to: 'settings#notifications'
  get '/settings/security', to: 'settings#security'
  get '/settings/export', to: 'settings#export_data'
  get '/settings/delete', to: 'settings#delete_account'
  patch '/settings/notifications', to: 'settings#update_notifications'
  
  # Subscription routes (protected)
  resources :subscriptions, only: [:index, :show, :new, :create] do
    member do
      delete :cancel
    end
  end
  
  # Stripe webhook (public)
  post '/stripe/webhooks', to: 'stripe_webhooks#create'
  
  # Auth callback endpoints (public/protected)
  post '/auth/freelancer/authorize', to: 'auth/freelancer#authorize'
  
  # QBO OAuth2 routes (protected)
  namespace :auth do
    namespace :qbo do
      get :connect
      get :callback
      delete :disconnect
      get :status
    end
  end
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Admin routes (protected)
  namespace :admin do
    get '/', to: 'dashboard#index', as: 'root'
    get '/dashboard', to: 'dashboard#index'
    
    resources :users, only: [:index, :show, :edit, :update] do
      member do
        post :impersonate
        patch :suspend
        patch :unsuspend
        patch :verify
      end
      
      collection do
        delete :stop_impersonating
      end
    end
    
    get '/system', to: 'system#index'
    get '/audit_logs', to: 'audit_logs#index'
  end
  
  # Sidekiq web interface (will be protected in admin)
  require 'sidekiq/web'
  if Rails.env.development?
    mount Sidekiq::Web => '/sidekiq'
  else
    # Protect Sidekiq in production - only allow admin users
    Sidekiq::Web.use ActionDispatch::Cookies
    Sidekiq::Web.use ActionDispatch::Session::CookieStore, key: "_interslice_session"
    mount Sidekiq::Web => '/admin/sidekiq'
  end

  # Error pages
  match '/404', to: 'errors#not_found', via: :all
  match '/500', to: 'errors#internal_server_error', via: :all
  match '/422', to: 'errors#unprocessable_entity', via: :all

  # Defines the root path route ("/")
  root "home#index"
end
