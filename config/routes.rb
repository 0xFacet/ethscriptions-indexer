Rails.application.routes.draw do
  def draw_routes
    resources :ethscriptions, only: [:index, :show] do
    end
    
    resources :blocks, only: [:index, :show] do
    end
  end

  draw_routes

  # Support legacy indexer namespace
  namespace :api do
    draw_routes
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
