class SimpleController < ApplicationController

  helper Redirectr::ApplicationHelper

  def index
    render plain: 'Hello World!'
  end

  def do_redirect
    redirect_to back_or_default(params[:other_default].presence)
  end

  def current_url_value
    render plain: self.current_url(anchor: params[:anchor]), layout: false
  end

  def hidden_referrer_input_tag
    render plain: helpers.hidden_referrer_input_tag, layout: false
  end

  protected

  def default_url
    root_url(this_is_default_url: 1)
  end

end