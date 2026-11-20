Rails.application.routes.draw do
  root "quotes#index"

  resources :bookings, only: %i[new create], path: "bestilling"
  get "bli-partner", to: "partners#new", as: :partner
  post "bli-partner", to: "partners#create"

  resource :session, path: "logg-inn", only: %i[new create destroy]
  resources :passwords, param: :token, path: "glemt-passord", only: %i[new create edit update]

  namespace :portal, path: "operator" do
    root "requests#index"
    resources :requests, only: [], param: :ref do
      member do
        patch :accept
        patch :decline
        patch :claim
      end
    end
    resource :rate_card, path: "priser", only: %i[show update] do
      post :preview
    end
    post "bytt", to: "switches#create", as: :switch
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
