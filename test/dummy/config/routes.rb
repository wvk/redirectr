Rails.application.routes.draw do
  mount Redirectr::Engine => "/redirectr"
end
