# Set here and not in application.rb: Rails applies config.action_controller
# when ActionController::Base loads, so this takes effect only as long as
# nothing loads that class before the initializers run.
Rails.application.config.action_controller.allowed_redirect_hosts = %w(set-in-initializer.example)
