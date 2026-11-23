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

  test 'foreign hosts raise at the redirect' do
    each_redirect_to_foreign_host do |path, referrer, message|
      assert_raises(Redirectr::UrlNotInWhitelist, message) { get path, params: { referrer: referrer } }
    end
  end

  test 'discard_referrer_on_invalid_origin redirects to the default for foreign hosts' do
    with_redirectr_config(discard_referrer_on_invalid_origin: true) do
      each_redirect_to_foreign_host do |path, referrer, message|
        get path, params: { referrer: referrer }
        assert_redirected_to DEFAULT_URL, message
      end
    end
  end

  test 'foreign hosts are rejected while Rails logs open redirects' do
    with_open_redirects_logged do
      each_redirect_to_foreign_host do |path, referrer, message|
        assert_raises(Redirectr::UrlNotInWhitelist, message) { get path, params: { referrer: referrer } }
      end
    end
  end

  test 'hosts in allowed_redirect_hosts are redirected to' do
    get '/redirect', params: { referrer: 'https://set-in-initializer.example/x' }
    assert_redirected_to 'https://set-in-initializer.example/x'
  end

  test 'allow_other_host applies to defaults chosen by the application' do
    get '/redirect_to_other_host', params: { other_default: 'https://elsewhere.example/' }
    assert_redirected_to 'https://elsewhere.example/'
  end

  test 'pass-along helpers keep the referrer as it is' do
    ['http://www.notvalid.com/x', 'javascript:alert(1)', 'tel:123', '//www.notvalid.com/', '?page=2'].each do |referrer|
      assert_equal referrer, hidden_referrer_value(referrer)

      get '/with_referrer', params: { referrer: referrer }
      assert_equal "/redirect?#{{ referrer: referrer }.to_query}", hrefs.first
    end
  end

  test 'link targets follow Rails rule' do
    assert_equal DEFAULT_URL, link_to_back_href('http://www.notvalid.com/x')
    assert_equal 'http://www.example.com/x', link_to_back_href('http://www.example.com/x')
    assert_equal 'https://www.example.com:8443/x', link_to_back_href('https://www.example.com:8443/x')
    assert_equal 'https://set-in-initializer.example/x', link_to_back_href('https://set-in-initializer.example/x')
    assert_equal '/x', link_to_back_href('/x')
  end

  test 'local paths are accepted' do
    %w(/ /?foo=bar /foo/bar#baz).each do |referrer|
      get '/redirect', params: { referrer: referrer }
      assert_redirected_to "http://www.example.com#{referrer}"
    end
  end

  test 'other schemes, protocol-relative and relative URLs are no targets' do
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
      message = "for referrer #{referrer.inspect}"

      %w(/redirect /redirect_to_other_host).each do |path|
        assert_raises(Redirectr::UrlNotInWhitelist, message) { get path, params: { referrer: referrer } }

        with_redirectr_config(discard_referrer_on_invalid_origin: true) do
          get path, params: { referrer: referrer }
          assert_redirected_to DEFAULT_URL, message
        end
      end

      assert_equal DEFAULT_URL, link_to_back_href(referrer), message
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

  test 'whitelisted schemes' do
    with_redirectr_config(whitelist: %w(com.example.app:/oauth2redirect mailto:someone@example.com), discard_referrer_on_invalid_origin: true) do
      %w(com.example.app:/oauth2redirect?code=1 com.example.app:/oauth2redirect/done mailto:someone@example.com).each do |referrer|
        get '/redirect_to_other_host', params: { referrer: referrer }
        assert_redirected_to referrer

        assert_equal referrer, link_to_back_href(referrer)
      end

      %w(com.example.app:/oauth2redirect-evil com.example.app:/other other.app:/oauth2redirect mailto:someone@example.com.au tel:123).each do |referrer|
        get '/redirect_to_other_host', params: { referrer: referrer }
        assert_redirected_to DEFAULT_URL, "for referrer #{referrer.inspect}"

        assert_equal DEFAULT_URL, link_to_back_href(referrer), "for referrer #{referrer.inspect}"
      end
    end
  end

  test 'whitelisted dangerous schemes with signing' do
    with_redirectr_config(whitelist: %w(javascript:void(0)), referrer_format: :signed) do
      signed = Redirectr::ReferrerToken.new('javascript:void(0)').to_param
      assert_equal signed, hidden_referrer_value(signed)
      assert_equal 'javascript:void(0)', link_to_back_href(signed)
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

  test 'invalid signed referrers raise when read' do
    with_redirectr_config(referrer_format: :signed) do
      assert_raises(Redirectr::InvalidReferrerToken) { hidden_referrer_value('http://www.example.com/unsigned') }
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

  test 'current_url takes a record as anchor without Active Record' do
    refute defined?(ActiveRecord), 'the dummy app loads Active Record'

    get '/items/7?scenario=record'
    assert_equal 'http://www.example.com/items/7?scenario=record#item_7', response.body
  end

  test 'back_or_default with current_url overrides' do
    get '/page_two?x=1'
    assert_redirected_to 'http://www.example.com/page_two?page=2&x=1#foo'
  end

  test 'with_referrer' do
    get '/with_referrer'
    assert_equal [
      "/redirect?#{{ referrer: 'http://www.example.com/with_referrer' }.to_query}",
      "/redirect?#{{ referrer: '/checkout' }.to_query}",
      "/redirect?#{{ other: 'params', referrer: '/checkout' }.to_query}",
      "/redirect?#{{ referrer: 'http://www.example.com/with_referrer?page=2' }.to_query}",
      "/redirect?#{{ referrer: 'http://www.example.com/' }.to_query}",
      "/redirect?#{{ referrer: 'http://www.example.com/my/account' }.to_query}",
    ], hrefs

    get '/with_referrer', params: { referrer: '/start' }
    assert_equal "/redirect?#{{ referrer: '/start' }.to_query}", hrefs.first
  end

  test 'with_referrer encodes the URL' do
    with_redirectr_config(referrer_format: :signed) do
      get '/with_referrer'
      get hrefs[1]
      assert_redirected_to 'http://www.example.com/checkout'
    end
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

  # Yields the actions that redirect to the referrer, each with referrers
  # naming a host Rails would not redirect to.
  def each_redirect_to_foreign_host
    %w(/redirect /redirect_to_other_host).each do |path|
      ['http://www.notvalid.com/?foo=bar', 'http:/www.notvalid.com/?foo=bar'].each do |referrer|
        yield path, referrer, "for #{path} with referrer #{referrer.inspect}"
      end
    end
  end

  def with_open_redirects_logged
    previous = ActionController::Base.action_on_open_redirect
    ActionController::Base.action_on_open_redirect = :log
    yield
  ensure
    ActionController::Base.action_on_open_redirect = previous
  end

  def hidden_referrer_value(referrer)
    get '/hidden_referrer_input_tag', params: { referrer: referrer }
    value = response.body[/ value="([^"]*)"/, 1]
    value && CGI.unescapeHTML(value)
  end

  def hrefs
    response.body.scan(/ href="([^"]*)"/).flatten.map { |href| CGI.unescapeHTML(href) }
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
