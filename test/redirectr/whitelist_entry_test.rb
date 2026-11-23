require 'test_helper'

class Redirectr::WhitelistEntryTest < ActiveSupport::TestCase
  test 'paths compare segment by segment' do
    assert match?('com.example.app:/oauth2redirect', 'com.example.app:/oauth2redirect?code=1')
    assert match?('com.example.app:/oauth2redirect', 'com.example.app:/oauth2redirect/done')
    refute match?('com.example.app:/oauth2redirect', 'com.example.app:/oauth2redirect-evil')
    refute match?('com.example.app:/oauth2redirect', 'com.example.app:/other')
    refute match?('com.example.app:/oauth2redirect', 'com.example.app:oauth2redirect')
  end

  test 'empty path segments and trailing slashes are ignored' do
    assert match?('com.example.app://callback/app/', 'com.example.app://callback//app')
    assert match?('com.example.app://callback/app', 'com.example.app://callback/app/')
  end

  test 'hosts compare with port' do
    assert match?('com.example.app://callback', 'com.example.app://callback/x')
    assert match?('com.example.app://Callback', 'com.example.app://callback/x')
    refute match?('com.example.app://callback', 'com.example.app://callback:8443/x')
    refute match?('com.example.app://callback', 'com.example.app://other/x')
    refute match?('com.example.app://callback', 'com.example.app://callback.evil/x')
  end

  test 'opaque entries compare the part before the query exactly' do
    assert match?('mailto:support@example.com', 'mailto:support@example.com')
    assert match?('mailto:support@example.com', 'mailto:support@example.com?subject=Hi')
    refute match?('mailto:support@example.com', 'mailto:support@example.com.au')
    refute match?('mailto:support@example.com', 'mailto:support@example.com,evil@example.com')
    refute match?('mailto:support@example.com', 'mailto:?to=support@example.com')
    refute match?('mailto:support@example.com', 'mailto:sales@example.com')
    assert match?('tel:+4930123456', 'tel:+4930123456')
    refute match?('tel:+49', 'tel:+4930123456')
  end

  test 'dangerous schemes' do
    assert Redirectr::WhitelistEntry.new('javascript:void(0)').dangerous?
    refute Redirectr::WhitelistEntry.new('com.example.app:/oauth2redirect').dangerous?
  end

  test 'entries need a scheme' do
    assert_raises(Redirectr::ConfigurationError) { Redirectr::WhitelistEntry.new('my.host.com/path') }
  end

  test 'entries need more than a scheme' do
    %w(mailto: com.example.app: javascript: mailto:?subject=Hi).each do |entry|
      assert_raises(Redirectr::ConfigurationError, "for #{entry.inspect}") { Redirectr::WhitelistEntry.new(entry) }
    end
  end

  test 'http and https entries point to allowed_redirect_hosts' do
    %w(https://my.host.com http://localhost:3000 https:/path https:).each do |entry|
      error = assert_raises(Redirectr::ConfigurationError, "for #{entry.inspect}") { Redirectr::WhitelistEntry.new(entry) }
      assert_includes error.message, 'config.action_controller.allowed_redirect_hosts'
    end
  end

  private

  def match?(entry, url)
    Redirectr::WhitelistEntry.new(entry).match?(URI.parse(url))
  end
end
