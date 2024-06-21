require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)
require "redirectr"

module Dummy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults ENV.fetch("RAILS_VERSION", "7.0").to_f

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end

