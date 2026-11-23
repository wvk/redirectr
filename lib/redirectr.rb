require 'uri'

require 'redirectr/engine'
require 'redirectr/whitelist_entry'
require 'redirectr/referrer_format'
require 'redirectr/referrer_token'
require 'redirectr/application_helper'

def ReferrerToken(url, token=nil)
  case url
  when Redirectr::ReferrerToken
    url
  when nil
    nil
  else
    Redirectr::ReferrerToken.new(url, token)
  end
end

module Redirectr
  REFERRER_PARAM_NAME = :referrer

  # Schemes Rails decides about, see ControllerMethods#back_or_default.
  # They take no whitelist entry.
  SAFE_SCHEMES = %w(http https).freeze

  # Schemes that run code in the page; a whitelist entry for one of them
  # requires a signed referrer format.
  DANGEROUS_SCHEMES = %w(javascript data vbscript).freeze

  # Settings of Redirectr 1.x and their replacements.
  REPLACED_SETTINGS = {
    sign_referrer:          'referrer_format = :signed',
    encrypt_referrer:       'referrer_format = :encrypted',
    use_referrer_token:     'the token gem',
    reuse_tokens:           'the token gem',
    storage_implementation: 'the token gem',
  }.freeze

  class UrlNotInWhitelist < ArgumentError
  end

  class InvalidReferrerToken < ArgumentError
  end

  class InvalidUrl < ArgumentError
  end

  class ConfigurationError < StandardError
  end

  def self.config
    Rails.configuration.x.redirectr
  end

  def self.whitelist
    Array(config.whitelist).map { |entry| WhitelistEntry.new(entry) }
  end

  # Checks the settings at boot.
  def self.validate_config!
    REPLACED_SETTINGS.each do |setting, replacement|
      if config[setting]
        raise ConfigurationError, "config.x.redirectr.#{setting} is replaced by #{replacement}"
      end
    end

    format = ReferrerFormat.fetch(config.referrer_format)
    dangerous = whitelist.select(&:dangerous?)
    if dangerous.any? and not format.signed?
      raise ConfigurationError, "config.x.redirectr.whitelist allows #{dangerous.join(', ')}, " \
                                'which requires a signed referrer_format such as :signed or :encrypted'
    end

    # current_url takes its host from the request, so Rails has to reject
    # requests for foreign hosts before a referrer is signed for them.
    if format.signed? and Rails.application.config.hosts.blank? and not Rails.env.local?
      raise ConfigurationError, "config.x.redirectr.referrer_format #{config.referrer_format.inspect} requires config.hosts, " \
                                'since signed referrers are issued for the host of the request'
    end
  end

  module ControllerMethods
    extend ActiveSupport::Concern

    included do
      helper Redirectr::ApplicationHelper
      helper_method :current_url,
                    :referrer_or_current_url,
                    :with_referrer,
                    :referrer_url,
                    :referrer_param,
                    :redirectr_referrer_token_url,
                    :redirectr_referrer_token_path
    end

    def redirectr_referrer_token_url(rt)
      rt.to_s
    end

    def redirectr_referrer_token_path(rt)
      rt.to_s
    end

    # Return the name of the parameter used to pass the referrer path:
    # config.x.redirectr.referrer_param_name, :referrer by default.
    # Use this instead of the real param name in creating your own links
    # to allow easily changing the name later
    # Example:
    #
    #  <%= link_to my_messages_url :filter_by => 'date', referrer_param => current_url %>
    #
    def referrer_param
      (Redirectr.config.referrer_param_name.presence || Redirectr::REFERRER_PARAM_NAME).to_sym
    end

    # Return the complete URL of the current request, including all query
    # params, as a Redirectr::ReferrerToken.
    #
    # Keyword arguments override path and query params the way +url_for+
    # does: a key naming a path segment fills it, other keys become query
    # params, +params:+ sets query params with reserved names such as
    # +anchor+, and +nil+ drops a param. +anchor:+ sets the fragment; a
    # record becomes its dom_id.
    #
    #  <%= link_to 'Edit', edit_task_path(task, referrer_param => current_url(page: 2, anchor: task)) %>
    #
    def current_url(anchor: nil, params: nil, **overrides)
      if anchor.respond_to?(:to_key)
        anchor = ActionView::RecordIdentifier.dom_id(anchor)
      end

      url = if params.nil? and overrides.empty?
              request_url_with_fragment(anchor)
            else
              query = request.query_parameters.except(*overrides.keys)
              query = query.merge(params) if params
              url_for(overrides.merge(params: query, anchor: anchor))
            end
      ReferrerToken(url)
    end

    # Return the referrer or the current path, it the former is not set.
    # Useful in cases where there might be a redirect path that has to be
    # taken note of but in case it is not present, the current path will be
    # redirected back to.
    # Example:
    #
    #  <%= link_to my_messages_url referrer_param => referrer_or_current_url %>
    #
    def referrer_or_current_url
      referrer_url.blank? ? current_url : referrer_url
    end

    # URL params carrying a referrer: the given URL, or else the referrer
    # or the current URL. Takes what back_or_default takes as default.
    # Example:
    #
    #  <%= link_to 'Sign in', new_session_path(with_referrer) %>
    #  <%= link_to 'Sign in', new_session_path(with_referrer(checkout_url)) %>
    #  <%= link_to 'Sign in', new_session_path(with_referrer(checkout_url).merge(other: 'params')) %>
    #
    def with_referrer(url = nil)
      { referrer_param => url.nil? ? referrer_or_current_url : referrer_token_for(url) }
    end

    # The referrer, or a default when no referrer is given. Accepts a
    # default URL, otherwise default_url applies.
    #
    #   class MyController
    #     def create
    #       @my = My.create(...)
    #       redirect_to back_or_default(my_url)
    #     end
    #   end
    #
    # The referrer becomes a redirect target here, so this is where it is
    # judged. Rails decides about paths and http(s) URLs: url_from accepts
    # the request's host and the hosts in
    # config.action_controller.allowed_redirect_hosts. The whitelist decides
    # about all other schemes. A referrer that fails raises
    # Redirectr::UrlNotInWhitelist; with discard_referrer_on_invalid_origin,
    # back_or_default returns the default for it.
    def back_or_default(default = nil)
      referrer = referrer_url
      if referrer.present? and redirect_allowed?(referrer)
        referrer
      else
        fallback_url(default)
      end
    end

    # to be overwritten by your controllers
    def default_url
      root_url
    end

    # The referrer from referrer_param, decoded and, with a signed referrer
    # format, verified. Where it points is not judged here, so it can be
    # passed on as it is; back_or_default judges it at the redirect.
    def referrer_url
      return @referrer_url if defined?(@referrer_url)

      @referrer_url = read_referrer_param
    end

    private

    def request_url_with_fragment(anchor)
      return request.original_url if anchor.nil?

      URI.parse(request.original_url).tap { |url| url.fragment = anchor }.to_s
    end

    def link_target_or_default(default)
      referrer = referrer_url
      if referrer.present? and target_allowed?(referrer)
        referrer
      else
        fallback_url(default)
      end
    end

    def fallback_url(default)
      url = default || default_url
      raise Redirectr::InvalidUrl, 'No URL given' if url.nil?

      referrer_token_for(url)
    end

    def referrer_token_for(url)
      case url
      when Redirectr::ReferrerToken
        url
      when String
        ReferrerToken(url)
      else
        ReferrerToken(url_for(url))
      end
    end

    def read_referrer_param
      param = params[referrer_param]
      return nil if param.blank?

      ReferrerToken.from_param(param)
    rescue Redirectr::InvalidReferrerToken
      logger&.info "[redirectr] rejected referrer #{param.inspect}"
      raise Redirectr::InvalidReferrerToken, "no valid referrer in #{param.inspect}" unless discard_referrer?
    end

    def discard_referrer?
      Redirectr.config.discard_referrer_on_invalid_origin
    end

    # Whether back_or_default may hand out the referrer as redirect target.
    # Raises for a referrer that fails, unless
    # discard_referrer_on_invalid_origin is set.
    def redirect_allowed?(referrer)
      return true if target_allowed?(referrer)
      return false if discard_referrer?

      raise Redirectr::UrlNotInWhitelist, "#{referrer.to_s.inspect} is not allowed as redirect target"
    end

    # Whether a referrer may be redirected or linked to.
    def target_allowed?(referrer)
      url = referrer.to_s
      return true if rails_or_whitelist_allows?(url)

      logger&.info "[redirectr] rejected referrer #{url.inspect}"
      false
    end

    # Rails decides about paths and http(s) URLs through url_from, which
    # looks at the host only. All other schemes therefore go by the
    # whitelist.
    def rails_or_whitelist_allows?(url)
      uri = URI.parse(url)
      if uri.scheme.nil? or Redirectr::SAFE_SCHEMES.include?(uri.scheme.downcase)
        url_from(url).present?
      else
        Redirectr.whitelist.any? { |entry| entry.match?(uri) }
      end
    rescue URI::InvalidURIError
      false
    end
  end

end # module Redirectr

# Included on load: loading ActionController::Base here would make Rails
# apply config.action_controller before the app's initializers have run.
ActiveSupport.on_load(:action_controller_base) { include Redirectr::ControllerMethods }
