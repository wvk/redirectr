require 'securerandom'
require 'uri'

require 'redirectr/engine'
require 'redirectr/whitelist_entry'
require 'redirectr/referrer_format'
require 'redirectr/referrer_token'

def ReferrerToken(url, token=nil)
  case url
  when Redirectr::ReferrerToken
    url
  when nil
    nil
  else
    Redirectr::ReferrerToken.new(url, token).tap do |rt|
      rt.save
    end
  end
end

$referrer_lookup ||= {}

module Redirectr
  REFERRER_PARAM_NAME = :referrer

  # Schemes accepted without a whitelist entry.
  SAFE_SCHEMES = %w(http https).freeze

  # Schemes that run code in the page; a whitelist entry for one of them
  # requires signed, encrypted or token referrers.
  DANGEROUS_SCHEMES = %w(javascript data vbscript).freeze

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

  def self.deprecator
    @deprecator ||= ActiveSupport::Deprecation.new('2.0', 'Redirectr')
  end

  def self.whitelist
    Array(config.whitelist).map { |entry| WhitelistEntry.new(entry) }
  end

  # Checks settings that only work together, at boot.
  def self.validate_config!
    modes = %i(sign_referrer encrypt_referrer use_referrer_token).select { |mode| config[mode] }
    if modes.size > 1
      raise ConfigurationError, "config.x.redirectr: enable only one of #{modes.join(', ')}"
    end

    dangerous = whitelist.select(&:dangerous?)
    if dangerous.any? and modes.empty?
      raise ConfigurationError, "config.x.redirectr.whitelist allows #{dangerous.join(', ')}, " \
                                'which requires sign_referrer, encrypt_referrer or use_referrer_token'
    end

    if config.use_referrer_token
      deprecator.warn 'Token mode (config.x.redirectr.use_referrer_token) moves to a separate gem with Redirectr 2.0.'
    end
  end

  module ControllerMethods
    extend ActiveSupport::Concern

    included do
      helper_method :current_url,
                    :referrer_or_current_url,
                    :back_or_default,
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
      if anchor.is_a?(ActiveRecord::Base)
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

    # Used in back links, referrer based redirection after actions etc.
    # Accepts a default redirect path in case no param[referrer_param]
    # is set, default being root_url.
    # To set an own default path (per controller), you can overwrite
    # the default_url method (see below).
    # Example:
    #
    #   class MyController
    #     def create
    #       @my = My.create(...)
    #       redirect_to back_or_default(my_url)
    #     end
    #   end
    #
    # The above example will redirect to the referrer_url if it is defined, otherwise
    # it will redirect to the my_url
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
    # The above example will redirect to the referrer_url if it is defined, otherwise
    # it will redirect to the root_url of the application.
    def back_or_default(default = nil)
      if self.referrer_url.present?
        self.referrer_url
      else
        url = default || self.default_url

        case url
        when nil
          raise Redirectr::InvalidUrl, 'No URL given'
        when Redirectr::ReferrerToken
          url
        when String
          ReferrerToken(url)
        else
          ReferrerToken(url_for(url))
        end
      end
    end

    # to be overwritten by your controllers
    def default_url
      root_url
    end

    # Reads referrer_param from HTTP params and checks its scheme, host and
    # signature.
    def referrer_url
      return @referrer_url if defined?(@referrer_url)

      @referrer_url = read_referrer_param
    end

    private

    def request_url_with_fragment(anchor)
      return request.original_url if anchor.nil?

      URI.parse(request.original_url).tap { |url| url.fragment = anchor }.to_s
    end

    def read_referrer_param
      param = params[referrer_param]
      return nil if param.blank?

      referrer_token = begin
                         ReferrerToken.from_param(param)
                       rescue Redirectr::InvalidReferrerToken
                         nil
                       end

      if referrer_token.blank?
        reject_referrer param, Redirectr::InvalidReferrerToken, "no valid referrer in #{param.inspect}"
      elsif allowed_url?(referrer_token)
        referrer_token
      else
        reject_referrer param, Redirectr::UrlNotInWhitelist, "#{referrer_token.to_s.inspect} is not allowed as referrer"
      end
    end

    def reject_referrer(param, error_class, message)
      logger&.info "[redirectr] rejected referrer #{param.inspect}"
      raise error_class, message unless Redirectr.config.discard_referrer_on_invalid_origin
    end

    # Referrers end up in redirects and link targets. They are paths with
    # exactly one leading slash (browsers resolve "//other.host/..." to
    # other.host), http(s) URLs on the request's or a whitelisted host and
    # port, or URLs matching a whitelist entry of another scheme.
    def allowed_url?(url)
      url = url.to_s
      uri = URI.parse(url)
      if uri.scheme.nil?
        url.start_with?('/') and not url.start_with?('//')
      elsif Redirectr::SAFE_SCHEMES.include?(uri.scheme.downcase)
        same_origin?(uri) or Redirectr.whitelist.any? { |entry| entry.http? and entry.match?(uri, strict_scheme: false) }
      else
        Redirectr.whitelist.any? { |entry| entry.match?(uri) }
      end
    rescue URI::InvalidURIError
      false
    end

    def same_origin?(uri)
      uri.host.present? and uri.host.casecmp?(request.host) and uri.port == request.port
    end
  end

end # module Redirectr

ActionController::Base.send :include, Redirectr::ControllerMethods
