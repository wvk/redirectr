require 'test_helper'

class Redirectr::ConfigTest < ActiveSupport::TestCase
  test 'settings of Redirectr 1.x raise' do
    %i(sign_referrer encrypt_referrer use_referrer_token reuse_tokens storage_implementation).each do |setting|
      with_redirectr_config(setting => true) do
        assert_raises(Redirectr::ConfigurationError, "for #{setting}") { Redirectr.validate_config! }
      end
    end
  end

  test 'unknown referrer formats raise' do
    with_redirectr_config(referrer_format: :rot13) do
      assert_raises(Redirectr::ConfigurationError) { Redirectr.validate_config! }
    end
  end

  test 'dangerous schemes require a signed referrer format' do
    with_redirectr_config(whitelist: %w(javascript:void(0))) do
      assert_raises(Redirectr::ConfigurationError) { Redirectr.validate_config! }
    end

    %i(signed encrypted).each do |format|
      with_redirectr_config(whitelist: %w(javascript:void(0)), referrer_format: format) do
        assert_nothing_raised { Redirectr.validate_config! }
      end
    end
  end

  test 'invalid whitelist entries' do
    %w(my.host.com/path mailto: https:).each do |entry|
      with_redirectr_config(whitelist: [entry]) do
        assert_raises(Redirectr::ConfigurationError, "for #{entry.inspect}") { Redirectr.validate_config! }
      end
    end
  end

  test 'warning when Rails open-redirect protection is off' do
    io = StringIO.new
    logger = Rails.logger
    action = ActionController::Base.action_on_open_redirect
    raise_on = ActionController::Base.raise_on_open_redirects

    Rails.logger = ActiveSupport::Logger.new(io)
    ActionController::Base.action_on_open_redirect = :log
    ActionController::Base.raise_on_open_redirects = false
    Redirectr.validate_config!
    assert_includes io.string, 'open-redirect protection is off'
  ensure
    Rails.logger = logger
    ActionController::Base.action_on_open_redirect = action
    ActionController::Base.raise_on_open_redirects = raise_on
  end
end
