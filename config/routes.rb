Rails.application.routes.draw do
  root "quotes#index"

  resources :bookings, only: %i[new create], path: "bestilling"
  # Customer trip page (secret link), passenger tracking link and "my trips" lookup
  resources :trips, only: :show, path: "reise", param: :token do
    member do
      get :position, path: "posisjon"
      patch :cancel, path: "avbestill"
      patch :pay_balance, path: "betal-resten"
      post :review, path: "omtale"
    end
  end
  get "spor/:share_token", to: "tracks#show", as: :track
  get "spor/:share_token/posisjon", to: "tracks#position", as: :track_position
  get "mine-turer", to: "lookups#new", as: :lookup
  post "mine-turer", to: "lookups#create"

  resources :operator_profiles, only: :show, path: "operatorer", param: :slug
  get "bedrift", to: "business#new", as: :business
  post "bedrift", to: "business#create"

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
        patch :assign
        patch :complete
      end
    end
    resource :rate_card, path: "priser", only: %i[show update] do
      post :preview
    end
    post "bytt", to: "switches#create", as: :switch
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
