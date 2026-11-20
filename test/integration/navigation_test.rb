require 'test_helper'

class NavigationTest < ActionDispatch::IntegrationTest
  DEFAULT_URL = 'http://www.example.com/?this_is_default_url=1'

  test 'basic stuff' do
    # Test referrer param
    get '/redirect?referrer=http://www.example.com/?foo=bar'
    follow_redirect!
    assert_equal 'http://www.example.com/?foo=bar', request.url

    # Test `ApplicationController#default_url` method
    get '/redirect'
    follow_redirect!
    assert_equal DEFAULT_URL, request.url

    # Test `default` parameter for `back_or_default`
    get '/redirect?other_default=http://www.example.com/?other_default=1'
    follow_redirect!
    assert_equal 'http://www.example.com/?other_default=1', request.url
  end

  test 'Rails checks foreign hosts in redirect_to' do
    assert_raises(ActionController::Redirecting::OpenRedirectError) do
      get '/redirect?referrer=http://www.notvalid.com/?foo=bar'
    end
  end

  test 'discard_referrer_on_invalid_origin applies Rails rule in back_or_default' do
    with_redirectr_config(discard_referrer_on_invalid_origin: true) do
      ['http://www.notvalid.com/?foo=bar', 'http:/www.notvalid.com/?foo=bar'].each do |referrer|
        get '/redirect', params: { referrer: referrer }
        assert_redirected_to DEFAULT_URL, "for referrer #{referrer.inspect}"
      end
    end
  end

  test 'pass-along helpers keep foreign hosts' do
    assert_equal 'http://www.notvalid.com/x', hidden_referrer_value('http://www.notvalid.com/x')
  end

  test 'link targets follow Rails rule' do
    assert_equal DEFAULT_URL, link_to_back_href('http://www.notvalid.com/x')
    assert_equal 'http://www.example.com/x', link_to_back_href('http://www.example.com/x')
    assert_equal 'https://www.example.com:8443/x', link_to_back_href('https://www.example.com:8443/x')
    assert_equal '/x', link_to_back_href('/x')
  end

  test 'with http(s) entries, the request origin compares scheme, host and port' do
    with_redirectr_config(whitelist: %w(https://other.example), discard_referrer_on_invalid_origin: true) do
      assert_equal 'http://WWW.example.com/x', hidden_referrer_value('http://WWW.example.com/x')
      assert_nil hidden_referrer_value('https://www.example.com:80/x')
      assert_nil hidden_referrer_value('http://www.example.com:8080/x')
    end
  end

  test 'local paths are accepted' do
    %w(/ /?foo=bar /foo/bar#baz).each do |referrer|
      get '/redirect', params: { referrer: referrer }
      assert_redirected_to "http://www.example.com#{referrer}"
    end
  end

  test 'other schemes, protocol-relative and relative URLs are rejected' do
    with_redirectr_config(discard_referrer_on_invalid_origin: true) do
      [
        'javascript://www.example.com/%0Aalert(1)',
        'javascript://www.example.com:80/%0Aalert(1)',
        'javascript:alert(1)',
        'data://www.example.com/text/html,foo',
        '//www.notvalid.com/?foo=bar',
        '///www.notvalid.com/?foo=bar',
        '/\\www.notvalid.com/?foo=bar',
        'www.notvalid.com/?foo=bar',
        '?page=2',
        '#top',
      ].each do |referrer|
        get '/redirect', params: { referrer: referrer }
        assert_redirected_to DEFAULT_URL, "for referrer #{referrer.inspect}"

        assert_nil hidden_referrer_value(referrer), "for referrer #{referrer.inspect}"
      end
    end
  end

  test 'rejected referrers are logged' do
    log = capture_controller_log do
      with_redirectr_config(discard_referrer_on_invalid_origin: true) do
        get '/redirect', params: { referrer: '//evil.example/' }
      end
    end
    assert_includes log, '[redirectr] rejected referrer "//evil.example/"'
  end

  test 'http(s) whitelist entries restrict hosts' do
    with_redirectr_config(whitelist: %w(https://other.example), discard_referrer_on_invalid_origin: true) do
      assert_equal 'https://other.example/x', hidden_referrer_value('https://other.example/x')
      assert_equal 'http://www.example.com/x', hidden_referrer_value('http://www.example.com/x')
      assert_nil hidden_referrer_value('http://other.example/x')
      assert_nil hidden_referrer_value('https://other.example:8443/x')
      assert_nil hidden_referrer_value('https://evil.example/x')

      assert_equal 'https://other.example/x', link_to_back_href('https://other.example/x')
    end
  end

  test 'whitelisted hosts outside allowed_redirect_hosts trigger one warning' do
    Redirectr.warned_hosts.clear
    log = capture_controller_log do
      with_redirectr_config(whitelist: %w(https://other.example)) do
        2.times { hidden_referrer_value('https://other.example/x') }
      end
    end
    assert_equal 1, log.scan('whitelisted host other.example').size
  ensure
    Redirectr.warned_hosts.clear
  end

  test 'whitelisted hosts in allowed_redirect_hosts' do
    previous = ActionController::Base.allowed_redirect_hosts
    ActionController::Base.allowed_redirect_hosts = %w(other.example)

    log = capture_controller_log do
      with_redirectr_config(whitelist: %w(https://other.example)) do
        get '/redirect', params: { referrer: 'https://other.example/x' }
        assert_redirected_to 'https://other.example/x'
      end
    end
    refute_includes log, 'whitelisted host'
  ensure
    ActionController::Base.allowed_redirect_hosts = previous
  end

  test 'whitelisted schemes' do
    with_redirectr_config(whitelist: %w(com.example.app:/oauth2redirect mailto:someone@example.com), discard_referrer_on_invalid_origin: true) do
      %w(com.example.app:/oauth2redirect?code=1 com.example.app:/oauth2redirect/done mailto:someone@example.com).each do |referrer|
        assert_equal referrer, hidden_referrer_value(referrer)
      end

      %w(com.example.app:/oauth2redirect-evil com.example.app:/other other.app:/oauth2redirect mailto:someone@example.com.au tel:123).each do |referrer|
        assert_nil hidden_referrer_value(referrer), "for referrer #{referrer.inspect}"
      end

      assert_equal 'com.example.app:/oauth2redirect?code=1', link_to_back_href('com.example.app:/oauth2redirect?code=1')
    end
  end

  test 'whitelisted dangerous schemes with signing' do
    with_redirectr_config(whitelist: %w(javascript:void(0)), referrer_format: :signed) do
      signed = Redirectr::ReferrerToken.new('javascript:void(0)').to_param
      assert_equal signed, hidden_referrer_value(signed)
    end
  end

  test 'signed referrers' do
    with_redirectr_config(referrer_format: :signed, discard_referrer_on_invalid_origin: true) do
      url = 'http://www.example.com/foo--bar?x=1'
      signed = Redirectr::ReferrerToken.new(url).to_param
      assert_equal "#{url}--", signed[0..-65]

      get '/redirect', params: { referrer: signed }
      assert_redirected_to url

      [url, signed.sub('x=1', 'x=2'), "#{signed}0"].each do |referrer|
        get '/redirect', params: { referrer: referrer }
        assert_redirected_to DEFAULT_URL, "for referrer #{referrer.inspect}"
      end
    end
  end

  test 'nested signed referrers' do
    with_redirectr_config(referrer_format: :signed, discard_referrer_on_invalid_origin: true) do
      inner_url = 'http://www.example.com/?filter=done'
      inner = Redirectr::ReferrerToken.new(inner_url).to_param
      outer_url = "http://www.example.com/redirect?#{{ referrer: inner }.to_query}"

      get '/redirect', params: { referrer: Redirectr::ReferrerToken.new(outer_url).to_param }
      assert_redirected_to outer_url
      follow_redirect!
      assert_redirected_to inner_url

      tampered_url = "http://www.example.com/redirect?#{{ referrer: inner.sub('done', 'gone') }.to_query}"
      get '/redirect', params: { referrer: Redirectr::ReferrerToken.new(tampered_url).to_param }
      follow_redirect!
      assert_redirected_to DEFAULT_URL
    end
  end

  test 'encrypted referrers' do
    with_redirectr_config(referrer_format: :encrypted, discard_referrer_on_invalid_origin: true) do
      url = 'http://www.example.com/secret?x=1'
      encrypted = Redirectr::ReferrerToken.new(url).to_param
      refute_includes encrypted, 'secret'

      get '/redirect', params: { referrer: encrypted }
      assert_redirected_to url

      [url, encrypted.reverse].each do |referrer|
        get '/redirect', params: { referrer: referrer }
        assert_redirected_to DEFAULT_URL, "for referrer #{referrer.inspect}"
      end
    end
  end

  test 'rotated secrets' do
    old_secret = 'a' * 64
    new_secret = 'b' * 64
    signed = with_redirectr_config(referrer_format: :signed, secret: old_secret) do
      Redirectr::ReferrerToken.new('/rotated').to_param
    end

    with_redirectr_config(referrer_format: :signed, secret: new_secret, discard_referrer_on_invalid_origin: true) do
      get '/redirect', params: { referrer: signed }
      assert_redirected_to DEFAULT_URL
    end

    with_redirectr_config(referrer_format: :signed, secret: new_secret, previous_secrets: [old_secret]) do
      get '/redirect', params: { referrer: signed }
      assert_redirected_to 'http://www.example.com/rotated'
    end
  end

  test 'registered referrer formats' do
    reversed = Module.new do
      def self.encode(url)
        url.to_s.reverse
      end

      def self.decode(param)
        param.reverse
      end
    end
    Redirectr::ReferrerFormat.register(:reversed, signed: false) { reversed }

    with_redirectr_config(referrer_format: :reversed) do
      assert_equal 'oof/', Redirectr::ReferrerToken.new('/foo').to_param

      get '/redirect', params: { referrer: 'oof/' }
      assert_redirected_to 'http://www.example.com/foo'
    end
  ensure
    Redirectr::ReferrerFormat.formats.delete(:reversed)
  end

  test 'current_url' do
    get '/current_url'
    assert_equal 'http://www.example.com/current_url', response.body

    get '/current_url?anchor=foo'
    assert_equal 'http://www.example.com/current_url?anchor=foo#foo', response.body

    get '/current_url?b=2&a=1'
    assert_equal 'http://www.example.com/current_url?b=2&a=1', response.body
  end

  test 'current_url overrides path and query params' do
    get '/items/7?scenario=page&page=1&host=evil.example'
    assert_equal 'http://www.example.com/items/7?host=evil.example&page=2&scenario=page#foo', response.body

    get '/items/7?scenario=id'
    assert_equal 'http://www.example.com/items/8?scenario=id', response.body

    get '/items/7?scenario=reserved'
    assert_equal 'http://www.example.com/items/7?anchor=x&scenario=reserved#foo', response.body

    get '/items/7?scenario=drop&page=1&x=y'
    assert_equal 'http://www.example.com/items/7?scenario=drop&x=y', response.body
  end

  test 'back_or_default with current_url overrides' do
    get '/page_two?x=1'
    assert_redirected_to 'http://www.example.com/page_two?page=2&x=1#foo'
  end

  test 'hidden_referrer_input_tag' do
    get '/hidden_referrer_input_tag'
    assert_equal '<input type="hidden" name="referrer" id="referrer" />', response.body

    assert_equal 'http://www.example.com/?foo=bar', hidden_referrer_value('http://www.example.com/?foo=bar')
  end

  test 'referrer_param_name' do
    with_redirectr_config(referrer_param_name: 'r') do
      get '/redirect?r=/foo'
      assert_redirected_to 'http://www.example.com/foo'

      get '/redirect?referrer=/foo'
      assert_redirected_to DEFAULT_URL

      get '/hidden_referrer_input_tag', params: { r: '/foo' }
      assert_match %r{ name="r" id="r" value="/foo"}, response.body
    end
  end

  private

  def hidden_referrer_value(referrer)
    get '/hidden_referrer_input_tag', params: { referrer: referrer }
    value = response.body[/ value="([^"]*)"/, 1]
    value && CGI.unescapeHTML(value)
  end

  def link_to_back_href(referrer)
    get '/link_to_back', params: { referrer: referrer }
    CGI.unescapeHTML(response.body[/ href="([^"]*)"/, 1])
  end

  def capture_controller_log
    io = StringIO.new
    logger = ActionController::Base.logger
    ActionController::Base.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    ActionController::Base.logger = logger
  end
end
