require 'test_helper'

class Redirectr::WhitelistEntryTest < ActiveSupport::TestCase
  test 'scheme-only entries match every URL of that scheme' do
    assert match?('mailto:', 'mailto:someone@example.com')
    refute match?('mailto:', 'tel:123')
  end

  test 'paths compare segment by segment' do
    assert match?('com.example.app:/oauth2redirect', 'com.example.app:/oauth2redirect?code=1')
    assert match?('com.example.app:/oauth2redirect', 'com.example.app:/oauth2redirect/done')
    refute match?('com.example.app:/oauth2redirect', 'com.example.app:/oauth2redirect-evil')
    refute match?('com.example.app:/oauth2redirect', 'com.example.app:/other')
  end

  test 'empty path segments and trailing slashes are ignored' do
    assert match?('https://my.host.com/app/', 'https://my.host.com//app')
    assert match?('https://my.host.com/app', 'https://my.host.com/app/')
  end

  test 'hosts compare with port' do
    assert match?('https://my.host.com', 'https://my.host.com/x')
    assert match?('https://My.Host.com', 'https://my.host.com/x')
    refute match?('https://my.host.com', 'https://my.host.com:8443/x')
    refute match?('https://my.host.com', 'https://other.host.com/x')
  end

  test 'http and https are interchangeable without strict_scheme' do
    assert match?('http://localhost:3000', 'https://localhost:3000/x', strict_scheme: false)
    refute match?('http://localhost:3000', 'https://localhost:3000/x')
  end

  test 'default ports apply when http and https are interchangeable' do
    refute match?('https://my.host.com', 'http://my.host.com/x', strict_scheme: false)
    assert match?('https://my.host.com', 'http://my.host.com:443/x', strict_scheme: false)
  end

  test 'scheme-only http entries match every host' do
    assert match?('https:', 'https://any.host/x')
    assert match?('https:', 'http://any.host/x', strict_scheme: false)
  end

  test 'opaque entries compare as prefix' do
    assert match?('mailto:support@example.com', 'mailto:support@example.com?subject=Hi')
    assert match?('mailto:support@example.com', 'mailto:support@example.com.au')
    assert match?('tel:+49', 'tel:+4930123456')
    refute match?('mailto:support@example.com', 'mailto:sales@example.com')
  end

  test 'dangerous schemes' do
    assert Redirectr::WhitelistEntry.new('javascript:').dangerous?
    refute Redirectr::WhitelistEntry.new('com.example.app:').dangerous?
  end

  test 'entries need a scheme' do
    assert_raises(Redirectr::ConfigurationError) { Redirectr::WhitelistEntry.new('my.host.com/path') }
  end

  private

  def match?(entry, url, **options)
    Redirectr::WhitelistEntry.new(entry).match?(URI.parse(url), **options)
  end
end
