require 'active_model'

module Redirectr
  class ReferrerToken

    extend ActiveModel::Naming

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
      else
        @token ||= ReferrerFormat.current.encode(url)
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

    # Raises Redirectr::InvalidReferrerToken for values with a missing or
    # wrong signature.
    def self.from_param(param)
      if Redirectr.config.use_referrer_token
        self.lookup(param)
      else
        new ReferrerFormat.current.decode(param), param
      end
    end

    def self.lookup(token)
      Redirectr.config.storage_implementation.fetch token
    end

  end
end