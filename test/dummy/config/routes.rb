Rails.application.routes.draw do
  root to: 'simple#index'
  get '/redirect' => 'simple#do_redirect', as: :do_redirect
  get '/current_url' => 'simple#current_url_value'

  mount Redirectr::Engine => "/redirectr"
end
