# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
require "rails/test_help"

# Filter out Minitest backtrace while allowing backtrace from other libraries
# to be shown.
Minitest.backtrace_filter = Minitest::BacktraceFilter.new

class ActiveSupport::TestCase
  # Sets config.x.redirectr values for the duration of the block.
  def with_redirectr_config(settings)
    previous = settings.keys.index_with { |key| Redirectr.config[key] }
    settings.each { |key, value| Redirectr.config[key] = value }
    yield
  ensure
    previous&.each { |key, value| Redirectr.config[key] = value }
  end
end
