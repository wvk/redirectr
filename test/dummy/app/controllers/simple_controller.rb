class SimpleController < ApplicationController

  def index
    render plain: 'Hello World!'
  end

  def do_redirect
    redirect_to back_or_default(params[:other_default].presence)
  end

  protected

  def default_url
    root_url(this_is_default_url: 1)
  end

end