require 'test_helper'

class Redirectr::ConfigTest < ActiveSupport::TestCase
  test 'one referrer format at a time' do
    with_redirectr_config(sign_referrer: true, encrypt_referrer: true) do
      assert_raises(Redirectr::ConfigurationError) { Redirectr.validate_config! }
    end
  end

  test 'dangerous schemes require signing' do
    with_redirectr_config(whitelist: %w(javascript:)) do
      assert_raises(Redirectr::ConfigurationError) { Redirectr.validate_config! }
    end

    with_redirectr_config(whitelist: %w(javascript:), sign_referrer: true) do
      assert_nothing_raised { Redirectr.validate_config! }
    end
  end

  test 'invalid whitelist entries' do
    with_redirectr_config(whitelist: %w(my.host.com/path)) do
      assert_raises(Redirectr::ConfigurationError) { Redirectr.validate_config! }
    end
  end

  test 'token mode is deprecated' do
    with_redirectr_config(use_referrer_token: true) do
      assert_deprecated(/separate gem/, Redirectr.deprecator) { Redirectr.validate_config! }
    end
  end
end
