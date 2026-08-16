Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
  get "sign-in", to: "sessions#new"
  post "sign-in", to: "sessions#create"
  get "check-email", to: "sessions#check_email"
  get "verify", to: "sessions#verification", as: :verify_email
  post "verify", to: "sessions#verify"
  delete "sign-out", to: "sessions#destroy"

  resource :dashboard, only: :show, controller: :dashboard
  resource :profile, only: %i[edit update destroy]
  resources :products, only: %i[create update destroy] do
    patch :focus, on: :member
  end
  post "offer/accept", to: "enrollments#accept", as: :accept_offer
  post "offer/decline", to: "enrollments#decline", as: :decline_offer
  post "seat/withdraw", to: "enrollments#withdraw", as: :withdraw_seat
  post "waitlist/join", to: "enrollments#join", as: :join_waitlist
  get "newsletter/confirm", to: "newsletter_subscriptions#show", as: :confirm_newsletter
  post "newsletter/confirm", to: "newsletter_subscriptions#create"
  get "privacy", to: "home#privacy"

  namespace :admin do
    root "dashboard#index"
    resources :users, only: %i[edit update destroy] do
      post :retry_newsletter, on: :member
      resources :products, only: %i[create update destroy]
    end
    resources :programs, only: :update do
      post :promote, on: :member
      post :expire_offers, on: :member
    end
  end

  namespace :facilitator do
    resources :profile_reviews, only: %i[index update]
  end
end
