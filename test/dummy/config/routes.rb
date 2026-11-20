Rails.application.routes.draw do
  root to: 'simple#index'
  get '/redirect' => 'simple#do_redirect', as: :do_redirect
  get '/current_url' => 'simple#current_url_value'
  get '/hidden_referrer_input_tag' => 'simple#hidden_referrer_input_tag'
  get '/items/:id' => 'simple#current_url_overrides'
  get '/page_two' => 'simple#redirect_to_page_two'

  mount Redirectr::Engine => "/redirectr"
end
