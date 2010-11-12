module Redirectr
  REFERRER_PARAM_NAME = :referrer

  module ControllerMethods
    def self.included(base)
      base.send :include, InstanceMethods
      base.send :extend, ClassMethods

      base.send :helper_method,
        :current_path,
        :referrer_or_current_path,
        :back_or_default,
        :referrer_path,
        :referrer_param,
        :link_to_back,
        :hidden_referrer_input_tag
    end

    module ClassMethods
      # Used to set a different param name where the referrer path should be stored.
      # Default is :referrer, a sensible alternative would be :r or so.
      # Example:
      #
      #   class MyController
      #     use_referrer_param_name :r
      #     # ...
      #   end
      #
      def use_referrer_param_name(new_name)
        const_set Redirectr::REFERRER_PARAM_NAME, new_name.to_sym
      end
    end

    module InstanceMethods

      # Return the name of the parameter used to pass the referrer path.
      # Use this instead of the real param name in creating your own links
      # to allow easily changing the name later
      # Example:
      #
      #  <%= link_to my_messages_path :filter_by => 'date', referrer_param => current_path %>
      #
      def referrer_param
        Redirectr::REFERRER_PARAM_NAME
      end

      # Return the path of the current request.
      # note that this path does NOT include any query parameters nor the hostname,
      # thus allowing you to navigate within the application only. This may be changed
      # in the future. If you need a different behaviour now, just overwrite this method
      # in your controller.
      # Example:
      #
      #  <%= link_to my_messages_path referrer_param => current_path %>
      #
      def current_path
        # maybe we want to use request.env['REQUEST_URI'] in the future...?
        request.env['PATH_INFO']
      end

      # Return the referrer or the current path, it the former is not set.
      # Useful in cases where there might be a redirect path that has to be
      # taken note of but in case it is not present, the current path will be
      # redirected back to.
      # Example:
      #
      #  <%= link_to my_messages_path referrer_param => referrer_or_current_path %>
      #
      def referrer_or_current_path
        referrer_path.blank? ? current_path : referrer_path
      end

      # Used in back links, referrer based redirection after actions etc.
      # Accepts a default redirect path in case no param[referrer_param]
      # is set, default being root_path.
      # Can and should be overwritten in namespace specific controllers
      # to set a sensible default if no referrer is given.
      # Example:
      #
      #   class MyController
      #     def create
      #       @my = My.create(...)
      #       redirect_to back_or_default(my_path)
      #     end
      #   end
      #
      # The above example will redirect to the referrer_path if it is defined, otherwise
      # it will redirect to the my_path
      #
      # Example:
      #
      #   class MyController
      #     def create
      #       @my = My.create(...)
      #       redirect_to back_or_default
      #     end
      #   end
      #
      # The above example will redirect to the referrer_path if it is defined, otherwise
      # it will redirect to the root_path of the application.
      def back_or_default(default = nil)
        unless referrer_path.blank?
          referrer_path
        else
          root_path
        end
      end

      # Convenience method for params[referrer_param]
      def referrer_path
        params[referrer_param]
      end
    end

    # Create a link back to the path specified in the referrer-param.
    # title can be either a text string or anything else like an image.
    # Remember to call #html_safe on the title argument if it contains
    # HTML and you are using Rails 3.
    def link_to_back(title, options = {})
      link_to title, back_or_default, options
    end

    # Create a hidden input field containing the referrer or current path.
    # Handy for use in forms that are called with a referrer param which
    # has to be passed on and respected by the form processing action.
    def hidden_referrer_input_tag
      hidden_field :referrer, referrer_or_current_path
    end

  end # module Helpers
end # module Redirectr

ActionController::Base.send :include, Redirectr::ControllerMethods
