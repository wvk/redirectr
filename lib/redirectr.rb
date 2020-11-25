require 'redirectr/engine'
require 'securerandom'

def ReferrerToken(url, token=nil)
  case url
  when Redirectr::ReferrerToken
    url
  when nil
    nil
  else
    Redirectr::ReferrerToken.new(url, token).tap do |rt|
      #puts "Token for #{url}: #{rt.token}"
      rt.save
    end
  end
end

$referrer_lookup ||= {}

module Redirectr
  REFERRER_PARAM_NAME = :referrer

  class UrlNotInWhitelist < ArgumentError
  end

  class InvalidReferrerToken < ArgumentError
  end

  def self.config
    Rails.configuration.x.redirectr
  end

  class ReferrerToken
    extend ActiveModel::Naming

    # this is a stora implementation for activerecord-
    class ActiveRecordStorage < ActiveRecord::Base
      validates_presence_of :url, :token

      self.table_name = :redirectr_referrer_tokens

      class << self
        def store(record)
          self.find_or_create_by url: record.url, token: record.token
          record.url
        end

        def fetch(token)
          url = self.find_by(token: token)&.url
          ReferrerToken(url) if url
        end

        def token_for_url(url)
          self.find_by(url: url)&.token
        end
      end
    end

    class GlobalVarStorage
      extend ActiveModel::Naming

      def persisted?
        false
      end

      class << self
        def store(record)
          $referrer_lookup[record.token] = record.url
        end

        def fetch(token)
          ReferrerToken($referrer_lookup[token])
        end

        def token_for_url(url)
          $referrer_lookup.key(url)
        end
      end
    end

    attr_reader :url, :token

    def initialize(url, token=nil)
      @url   = url
      @token = token

      if Redirectr.config.use_referrer_token
        if Redirectr.config.storage_implementation.nil?
          raise "Missing storage implementation for referrer tokens! please define config.x.redirectr.storage_implementation"
        end

        if Redirectr.config.reuse_tokens
          @token ||= Redirectr.config.storage_implementation.token_for_url(url)
        end
        @token ||= SecureRandom.hex(16)
      elsif Redirectr.config.encrypt_referrer
        @token ||= self.class.cryptr.encrypt_and_sign url
      else
        @token ||= url
      end
    end

    def to_param
      @token
    end

    def to_model
      self
    end

    def to_s
      @url
    end

    def persisted?
      true
    end

    def save
      if Redirectr.config.use_referrer_token
        Redirectr.config.storage_implementation.store self
      end
    end

    def self.from_param(param)
      if Redirectr.config.encrypt_referrer
        ReferrerToken.new self.class.cryptr.decrypt_and_verify param
      elsif Redirectr.config.use_referrer_token
        self.lookup(param)
      else
        ReferrerToken.new param
      end
    end

    def self.lookup(token)
      Redirectr.config.storage_implementation.fetch token
    end

    private

    def self.cryptr
      @cryptr ||= ActiveSupport::MessageEncryptor.new(Rails.application.secrets.secret_key_base)
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
        Redirectr.remove_constant :REFERRER_PARAM_NAME
        Redirectr.const_set :REFERRER_PARAM_NAME, new_name.to_sym
      end
    end

    def redirectr_referrer_token_url(rt)
      rt.to_s
    end

    def redirectr_referrer_token_path(rt)
      rt.to_s
    end

    # Return the name of the parameter used to pass the referrer path.
    # Use this instead of the real param name in creating your own links
    # to allow easily changing the name later
    # Example:
    #
    #  <%= link_to my_messages_url :filter_by => 'date', referrer_param => current_url %>
    #
    def referrer_param
      Redirectr::REFERRER_PARAM_NAME
    end

    # Return the complete URL of the current request.
    # Note that this does include ALL query parameters and the host name,
    # thus allowing you to navigate back and forth between different hosts. If you
    # want the pre-0.1.0 behaviour back, just overwrite this method
    # in your controller so it returns "request.env['PATH_INFO']".
    # Example:
    #
    #  <%= link_to my_messages_url referrer_param => current_url %>
    #
    def current_url
      if request.respond_to? :url # for rack >= 2.0.0
        ReferrerToken(request.url)
      elsif request.respond_to? :original_url # for rails >= 4.0.0
        ReferrerToken(request.original_url)
      else
        ReferrerToken(request.env['REQUEST_URI'])
      end
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
        case default
        when nil
          ReferrerToken(self.default_url)
        when String
          ReferrerToken(default)
        else
          ReferrerToken(url_for(default))
        end
      end
    end

    # to be overwritten by your controllers
    def default_url
      root_url
    end

    # reads referrer_param from HTTP params and validates it against the whitelist
    def referrer_url
      return nil if params[referrer_param].blank?

      referrer_token = ReferrerToken.from_param params[referrer_param]
      raise Redirectr::InvalidReferrerToken, "no URL matches given token value #{params[referrer_param]}" if referrer_token.blank?

      parsed_url = URI.parse referrer_token.to_s
      if parsed_url.absolute? and redirect_whitelist.find {|url| parsed_url.host == url.host and parsed_url.port == url.port }
        referrer_token
      elsif parsed_url.relative?
        referrer_token
      else
        raise Redirectr::UrlNotInWhitelist, "#{parsed_url.inspect} - #{redirect_whitelist.inspect}"
      end
    end

    def redirect_whitelist
      [URI.parse(self.current_url.to_s)] +
          Array(Redirectr.config.whitelist).map {|url| URI.parse url.to_s }
    end
  end

end # module Redirectr

ActionController::Base.send :include, Redirectr::ControllerMethods

