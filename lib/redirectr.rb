require 'concurrent/set'
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

  # Schemes accepted without a whitelist entry.
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

  # Hosts redirectr has warned about, see ControllerMethods#warn_about_rails_rejection.
  def self.warned_hosts
    @warned_hosts ||= Concurrent::Set.new
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

    unless open_redirect_protection?
      Rails.logger&.warn '[redirectr] Rails\' open-redirect protection is off, so referrers can redirect ' \
                         'to any host; set config.action_controller.action_on_open_redirect = :raise'
    end
  end

  def self.open_redirect_protection?
    ActionController::Base.raise_on_open_redirects or ActionController::Base.action_on_open_redirect == :raise
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
    # Rails' open-redirect protection checks the result in redirect_to.
    # With discard_referrer_on_invalid_origin, back_or_default applies
    # Rails' rule itself and returns the default for referrers Rails rejects.
    def back_or_default(default = nil)
      referrer = referrer_url
      if referrer.present? and not (Redirectr.config.discard_referrer_on_invalid_origin and rails_rejects?(referrer))
        referrer
      else
        fallback_url(default)
      end
    end

    # to be overwritten by your controllers
    def default_url
      root_url
    end

    # Reads referrer_param from HTTP params and checks its scheme, signature
    # and, when the whitelist names http(s) hosts, its host.
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
      if referrer.present? and not rails_rejects?(referrer)
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

      referrer_token = begin
                         ReferrerToken.from_param(param)
                       rescue Redirectr::InvalidReferrerToken
                         nil
                       end
      @referrer_kind = referrer_token && referrer_kind(referrer_token.to_s)

      if referrer_token.nil?
        reject_referrer param, Redirectr::InvalidReferrerToken, "no valid referrer in #{param.inspect}"
      elsif @referrer_kind.nil?
        reject_referrer param, Redirectr::UrlNotInWhitelist, "#{referrer_token.to_s.inspect} is not allowed as referrer"
      else
        warn_about_rails_rejection(referrer_token) if @referrer_kind == :whitelisted
        referrer_token
      end
    end

    def reject_referrer(param, error_class, message)
      logger&.info "[redirectr] rejected referrer #{param.inspect}"
      raise error_class, message unless Redirectr.config.discard_referrer_on_invalid_origin
    end

    # How a referrer is allowed: :local (a path or the request's origin),
    # :whitelisted, :rails (Rails' open-redirect protection decides about
    # its host), or nil. Paths have exactly one leading slash: browsers
    # resolve "//other.host/..." to other.host.
    def referrer_kind(url)
      uri = URI.parse(url)
      if uri.scheme.nil?
        :local if url.start_with?('/') and not url.start_with?('//')
      elsif Redirectr::SAFE_SCHEMES.include?(uri.scheme.downcase)
        http_entries = Redirectr.whitelist.select(&:http?)
        if http_entries.empty?
          :rails
        elsif same_origin?(uri)
          :local
        elsif http_entries.any? { |entry| entry.match?(uri) }
          :whitelisted
        end
      elsif Redirectr.whitelist.any? { |entry| entry.match?(uri) }
        :whitelisted
      end
    rescue URI::InvalidURIError
      nil
    end

    def same_origin?(uri)
      uri.scheme.casecmp?(request.scheme) and
        uri.host.present? and uri.host.casecmp?(request.host) and
        uri.port == request.port
    end

    def rails_rejects?(referrer)
      return false unless @referrer_kind == :rails
      return false if url_from(referrer.to_s)

      logger&.info "[redirectr] rejected referrer #{referrer.to_s.inspect}"
      true
    end

    # Whitelisted http(s) hosts outside allowed_redirect_hosts pass redirectr
    # but fail in redirect_to without allow_other_host: true.
    def warn_about_rails_rejection(referrer)
      uri = URI.parse(referrer.to_s)
      return unless Redirectr::SAFE_SCHEMES.include?(uri.scheme.to_s.downcase)
      return if url_from(referrer.to_s)

      if Redirectr.warned_hosts.add?(uri.host)
        logger&.warn "[redirectr] whitelisted host #{uri.host} is missing from config.action_controller.allowed_redirect_hosts, " \
                     'so redirect_to rejects it without allow_other_host: true'
      end
    end
  end

end # module Redirectr

# Included on load: loading ActionController::Base here would make Rails
# apply config.action_controller before the app's initializers have run.
ActiveSupport.on_load(:action_controller_base) { include Redirectr::ControllerMethods }
