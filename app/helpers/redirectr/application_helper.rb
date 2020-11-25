module Redirectr
  module ApplicationHelper
    # Create a link back to the path specified in the referrer-param.
    # title can be either a text string or anything else like an image.
    # Remember to call #html_safe on the title argument if it contains
    # HTML and you are using Rails >=3.
    def link_to_back(title, options = {})
      link_to title, back_or_default.to_s, options.merge(rel: 'back')
    end

    # Create a hidden input field containing the referrer or current path.
    # Handy for use in forms that are called with a referrer param which
    # has to be passed on and respected by the form processing action.
    def hidden_referrer_input_tag(options = {})
      hidden_field_tag :referrer, referrer_or_current_url.to_param, options
    end

  end
end
