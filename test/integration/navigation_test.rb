require 'test_helper'

class NavigationTest < ActionDispatch::IntegrationTest
  test 'basic stuff' do
    # Test referrer param
    get '/redirect?referrer=http://www.example.com/?foo=bar'
    follow_redirect!
    assert_equal 'http://www.example.com/?foo=bar', request.url

    # Test `ApplicationController#default_url` method
    get '/redirect'
    follow_redirect!
    assert_equal 'http://www.example.com/?this_is_default_url=1', request.url

    # Test `default` parameter for `back_or_default`
    get '/redirect?other_default=http://www.example.com/?other_default=1'
    follow_redirect!
    assert_equal 'http://www.example.com/?other_default=1', request.url
  end

  test 'origin checks' do

    begin
      get '/redirect?referrer=http://www.notvalid.com/?foo=bar'
      assert response.status == 500
    rescue Redirectr::UrlNotInWhitelist # Rails 7.1 throws an exception, Rails 7.2+ returns 500...
      assert true
    end

    Redirectr.config.discard_referrer_on_invalid_origin = true
    get '/redirect?referrer=http://www.notvalid.com/?foo=bar'
    follow_redirect!
    assert_equal 'http://www.example.com/?this_is_default_url=1', request.url
  ensure
    Redirectr.config.discard_referrer_on_invalid_origin = nil
  end
end
