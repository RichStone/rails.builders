Rails.application.routes.draw do
  constraints(host: "www.rails.builders") do
    match "(*path)", to: redirect(status: 308) { |_params, request| "https://rails.builders#{request.fullpath}" }, via: :all
  end

  get "up" => "rails/health#show", as: :rails_health_check
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  root "home#index"
  get "sign-in", to: "sessions#new"
  post "sign-in", to: "sessions#create"
  get "check-email", to: "sessions#check_email"
  get "verify", to: "sessions#verification", as: :verify_email
  post "verify", to: "sessions#verify"
  delete "sign-out", to: "sessions#destroy"

  resource :dashboard, only: :show, controller: :dashboard
  resources :builder_sessions, path: "sessions", only: %i[index show] do
    post :sync_calendar, on: :collection
    resource :transcript, only: %i[create destroy], controller: "builder_session_transcripts"
    member do
      get :join
      post :start
      post :pause
      post :resume
      post :advance
      post :next_speaker
      post :finish
      patch :attendance
      patch :speaker_order
      patch :end_time
      patch :heartbeat
    end
  end
  resource :profile, only: %i[edit update destroy]
  resources :products, only: %i[create update destroy] do
    patch :focus, on: :member
  end
  post "offer/accept", to: "enrollments#accept", as: :accept_offer
  post "offer/decline", to: "enrollments#decline", as: :decline_offer
  patch "membership", to: "enrollments#membership", as: :membership
  post "seat/withdraw", to: "enrollments#withdraw", as: :withdraw_seat
  patch "waitlist", to: "enrollments#waitlist", as: :waitlist
  post "waitlist/join", to: "enrollments#join", as: :join_waitlist
  get "newsletter/confirm", to: "newsletter_subscriptions#show", as: :confirm_newsletter
  post "newsletter/confirm", to: "newsletter_subscriptions#create"
  get "privacy", to: "home#privacy"
  get "terms", to: "home#terms"

  namespace :admin do
    root "dashboard#index"
    resource :calendar_connection, only: %i[show create update destroy] do
      get :callback
      post :sync
    end
    resources :users, only: %i[edit update destroy] do
      post :retry_newsletter, on: :member
      post :remove, on: :member
      post :reinstate, on: :member
      post :grant_administrator, on: :member
      post :revoke_administrator, on: :member
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
