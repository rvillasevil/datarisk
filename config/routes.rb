Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: 'registrations' }
  devise_for :owners, class_name: 'User', controllers: { registrations: 'owners/registrations' }  
  resources :users, only: [] do
    resources :clients, only: %i[index new create destroy]
  end
  get 'clients/dashboard', to: 'clients#dashboard', as: :client_dashboard
  resources :clients, only: :show 
  resources :risk_assistants, only: %i[index show new create destroy report] do
    resources :messages,   only: :create
    resources :documents,  only: :index
    resources :summaries,  only: :index
    member do
      get :report
      get   :tabla_datos
      patch :update_message
      post :create_message
      get :summary
      delete 'files/:file_id', to: 'risk_assistants#destroy_file', as: :file
    end
  end

  resources :policy_analyses, only: [:index, :new, :create, :show, :destroy] do
    post :create_analysis, on: :member
    post :ask, on: :member   # << añadimos esta línea
  end

  resources :data_collections, only: %i[index show new]

  resource :guest_upgrade, only: :create, controller: 'users/guest_upgrades'  

  get 'owners/dashboard', to: 'owners#dashboard', as: :owner_dashboard 

  get 'client_invitations/accept', to: 'invitations#accept', as: :accept_client_invitation

  get  'risk_assistants/:id/report', to: "risk_assistants#report", as: 'risk_assistant_report'
  get  'risk_assistants/:id/resume', to: "risk_assistants#resume", as: 'risk_assistant_resume'

  root 'static_pages#home'
end