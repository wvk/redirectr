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
end