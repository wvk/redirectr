module Redirectr
  class Engine < ::Rails::Engine
    #isolate_namespace Redirectr

    initializer 'redirectr.deprecator' do |app|
      app.deprecators[:redirectr] = Redirectr.deprecator
    end

    config.after_initialize do
      Redirectr.validate_config!
    end
  end
end
