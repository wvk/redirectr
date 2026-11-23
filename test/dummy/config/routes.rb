Rails.application.routes.draw do
  root to: 'simple#index'
  get '/redirect' => 'simple#do_redirect', as: :do_redirect
  get '/redirect_to_other_host' => 'simple#do_redirect_to_other_host'
  get '/current_url' => 'simple#current_url_value'
  get '/hidden_referrer_input_tag' => 'simple#hidden_referrer_input_tag'
  get '/items/:id' => 'simple#current_url_overrides'
  get '/page_two' => 'simple#redirect_to_page_two'
  get '/link_to_back' => 'simple#link_to_back_tag'
  get '/with_referrer' => 'simple#with_referrer_links'

  namespace :my do
    resource :account, only: :show
  end

  mount Redirectr::Engine => "/redirectr"
end
