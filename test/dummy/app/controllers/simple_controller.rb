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

  def current_url_overrides
    url = case params[:scenario]
          when 'page'     then current_url(page: 2, anchor: 'foo')
          when 'id'       then current_url(id: 8)
          when 'reserved' then current_url(params: { anchor: 'x' }, anchor: 'foo')
          when 'drop'     then current_url(page: nil)
          when 'record'   then current_url(anchor: Item.new(id: params[:id]))
          end
    render plain: url, layout: false
  end

  def redirect_to_page_two
    redirect_to back_or_default(current_url(page: 2, anchor: 'foo'))
  end

  def hidden_referrer_input_tag
    render plain: helpers.hidden_referrer_input_tag, layout: false
  end

  def with_referrer_links
    render inline: <<~ERB, layout: false
      <%= link_to 'a', do_redirect_path(with_referrer) %>
      <%= link_to 'b', do_redirect_path(with_referrer('/checkout')) %>
      <%= link_to 'c', do_redirect_path(with_referrer('/checkout').merge(other: 'params')) %>
      <%= link_to 'd', do_redirect_path(with_referrer(current_url(page: 2))) %>
      <%= link_to 'e', do_redirect_path(with_referrer(controller: 'simple', action: 'index')) %>
      <%= link_to 'f', do_redirect_path(with_referrer([:my, :account])) %>
    ERB
  end

  def link_to_back_tag
    render inline: "<%= link_to_back 'Back' %>", layout: false
  end

  protected

  def default_url
    root_url(this_is_default_url: 1)
  end

end
