module Redirectr
  # View helpers. Controllers including Redirectr::ControllerMethods register
  # them, so views need no extra setup.
  #
  # back_or_default and link_to_back produce link targets: they return the
  # referrer when Rails' open-redirect rule or the whitelist allows it, and
  # the default otherwise. referrer_or_current_url and
  # hidden_referrer_input_tag pass the referrer on unchanged; the service
  # that finally redirects judges it in its back_or_default.
  module ApplicationHelper
    # The referrer as link target, or the default. See
    # Redirectr::ControllerMethods#back_or_default for the default.
    def back_or_default(default = nil)
      controller.send(:link_target_or_default, default)
    end

    # Create a link back to the path specified in the referrer-param.
    # title can be either a text string or anything else like an image.
    def link_to_back(title, options = {})
      link_to title, back_or_default.to_s, options.merge(rel: 'back')
    end

    # Create a hidden input field containing the referrer.
    # Handy for use in forms that are called with a referrer param which
    # has to be passed on and respected by the form processing action.
    def hidden_referrer_input_tag(options = {})
      hidden_field_tag referrer_param, referrer_url.to_param, options
    end
  end
end
