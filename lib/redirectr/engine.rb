module Redirectr
  class Engine < ::Rails::Engine
    #isolate_namespace Redirectr

    config.after_initialize do
      Redirectr.validate_config!
    end
  end
end
