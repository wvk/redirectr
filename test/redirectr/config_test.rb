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

  test 'signed referrer formats require config.hosts outside development and test' do
    %i(signed encrypted).each do |format|
      with_redirectr_config(referrer_format: format) do
        assert_nothing_raised { Redirectr.validate_config! }

        with_rails_env('production') do
          error = assert_raises(Redirectr::ConfigurationError, "for #{format}") { Redirectr.validate_config! }
          assert_includes error.message, 'requires config.hosts'

          with_hosts(%w(www.example.com)) do
            assert_nothing_raised { Redirectr.validate_config! }
          end
        end
      end
    end

    with_rails_env('production') do
      assert_nothing_raised { Redirectr.validate_config! }
    end
  end

  test 'action_controller settings from initializers apply' do
    assert_equal %w(set-in-initializer.example), ActionController::Base.allowed_redirect_hosts
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

  private

  def with_rails_env(env)
    previous = Rails.env
    Rails.env = env
    yield
  ensure
    Rails.env = previous
  end

  def with_hosts(hosts)
    previous = Rails.application.config.hosts
    Rails.application.config.hosts = hosts
    yield
  ensure
    Rails.application.config.hosts = previous
  end
end
