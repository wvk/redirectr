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

  test 'hidden_referrer_input_tag' do
    get '/hidden_referrer_input_tag'
    assert_equal '<input type="hidden" name="referrer" id="referrer" autocomplete="off" />', response.body

    get '/hidden_referrer_input_tag?referrer=http://www.example.com/?foo=bar'
    assert_equal '<input type="hidden" name="referrer" id="referrer" value="http://www.example.com/?foo=bar" autocomplete="off" />', response.body
  end
end
