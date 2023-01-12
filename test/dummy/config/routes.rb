Rails.application.routes.draw do
  root to: 'simple#index'
  get '/redirect' => 'simple#do_redirect', as: :do_redirect

  mount Redirectr::Engine => "/redirectr"
end
