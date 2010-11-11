module Redirectr
  REFERRER_PARAM_NAME = :referrer

  module ControllerMethods
    def self.included(base)
      base.send :include, InstanceMethods
      base.send :extend, ClassMethods

      base.send :helper_method,
        :current_path,
        :current_or_last_redirect_url,
        :back_or_default,
        :referrer_path,
        :referrer_param
    end

    module ClassMethods
      def use_referrer_param_name(new_name)
        const_set Redirectr::REFERRER_PARAM_NAME, new_name.to_sym
      end
    end

    module InstanceMethods

      def referrer_param
        Redirectr::REFERRER_PARAM_NAME
      end

      def current_path
        # maybe we want to use request.env['REQUEST_URI'] in the future...?
        request.env['PATH_INFO']
      end

      def current_or_last_redirect_url
        if referrer_path.blank?
          current_path
        else
          referrer_path
        end
      end

      # used in back links, referrer based redirection after actions etc.
      # can and should be overwritten in namespace specific controllers
      # to set a sensible default if no referrer is given.
      def back_or_default(default = nil)
        unless referrer_path.blank?
          referrer_path
        else
          root_path
        end
      end

      def referrer_path
        params[Redirectr::REFERRER_PARAM_NAME]
      end
    end
  end

  module Helpers
    def link_to_back(title, options = {})
      link_to title, back_or_default, options
    end

    def hidden_referrer_input_tag
      hidden_field :referrer, current_or_last_redirect_url
    end

  end # module Helpers
end # module Redirectr
