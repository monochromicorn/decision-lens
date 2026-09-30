Rails.application.routes.draw do
  # Health check for the hosting platform; the only unauthenticated route besides login.
  get "up" => "rails/health#show", as: :rails_health_check

  get    "login",   to: "sessions#new"
  post   "login",   to: "sessions#create"
  delete "logout",  to: "sessions#destroy"

  post "analyze", to: "decisions#create", as: :analyze
  root "decisions#new"
end
