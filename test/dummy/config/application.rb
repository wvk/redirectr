require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)
require "redirectr"

module Dummy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults ENV.fetch("RAILS_VERSION", "7.1").to_f

    # The engine's migrations, so loading the schema marks them as run.
    config.paths["db/migrate"] << File.expand_path("../../../db/migrate", __dir__)

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end

