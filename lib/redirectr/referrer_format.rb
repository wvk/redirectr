require 'json'
require 'openssl'

module Redirectr
  # Turns referrer URLs into param values and back.
  module ReferrerFormat
    SIGNING_SALT    = 'redirectr signed referrer'.freeze
    ENCRYPTION_SALT = 'redirectr encrypted referrer'.freeze
    CIPHER          = 'aes-256-gcm'.freeze

    Definition = Struct.new(:signed, :factory) do
      def signed?
        signed
      end
    end

    def self.formats
      @formats ||= {}
    end

    # Registers a referrer format for config.x.redirectr.referrer_format.
    # The block builds an object responding to encode(url) and
    # decode(param); decode raises Redirectr::InvalidReferrerToken for
    # values it rejects. signed: true marks formats that accept only values
    # the app issued.
    def self.register(name, signed:, &factory)
      formats[name.to_sym] = Definition.new(signed, factory)
    end

    def self.fetch(name)
      name = (name || :plain).to_sym
      formats.fetch(name) do
        raise ConfigurationError, "unknown config.x.redirectr.referrer_format #{name.inspect}"
      end
    end

    def self.current
      fetch(Redirectr.config.referrer_format).factory.call
    end

    # Keys derived from the current secret, followed by those derived from
    # config.x.redirectr.previous_secrets.
    def self.keys(salt, length)
      secrets.map { |secret| key_generator(secret).generate_key(salt, length) }
    end

    # The current secret is config.x.redirectr.secret, the credential
    # redirectr.secret or secret_key_base, in that order.
    def self.secrets
      current = Redirectr.config.secret.presence ||
                Rails.application.credentials.dig(:redirectr, :secret).presence ||
                Rails.application.secret_key_base
      [current, *Array(Redirectr.config.previous_secrets)]
    end

    def self.key_generator(secret)
      @key_generators ||= {}
      @key_generators[secret] ||= ActiveSupport::CachingKeyGenerator.new(
        ActiveSupport::KeyGenerator.new(secret, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA256)
      )
    end

    module Plain
      def self.encode(url)
        url
      end

      def self.decode(param)
        param
      end
    end

    # The plain URL followed by "--" and a hex HMAC-SHA256 of the URL.
    class Signed
      SEPARATOR = '--'.freeze

      def initialize(keys)
        @keys = keys
      end

      def encode(url)
        url = url.to_s
        "#{url}#{SEPARATOR}#{digest(@keys.first, url)}"
      end

      def decode(param)
        url, separator, signature = param.to_s.rpartition(SEPARATOR)
        if separator.empty? or not signature.match?(/\A\h{64}\z/)
          raise InvalidReferrerToken, 'unsigned referrer'
        end

        unless @keys.any? { |key| ActiveSupport::SecurityUtils.secure_compare(digest(key, url), signature) }
          raise InvalidReferrerToken, 'invalid referrer signature'
        end

        url
      end

      private

      def digest(key, url)
        OpenSSL::HMAC.hexdigest('SHA256', key, url)
      end
    end

    class Encrypted
      def initialize(keys)
        @encryptor = ActiveSupport::MessageEncryptor.new(keys.first, **options)
        keys.drop(1).each { |key| @encryptor.rotate(key, **options) }
      end

      def encode(url)
        @encryptor.encrypt_and_sign(url.to_s)
      end

      def decode(param)
        @encryptor.decrypt_and_verify(param.to_s) or raise InvalidReferrerToken, 'invalid encrypted referrer'
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        raise InvalidReferrerToken, 'invalid encrypted referrer'
      end

      private

      def options
        { cipher: CIPHER, serializer: JSON, url_safe: true }
      end
    end

    register(:plain, signed: false) { Plain }
    register(:signed, signed: true) { Signed.new(keys(SIGNING_SALT, 64)) }
    register(:encrypted, signed: true) do
      Encrypted.new(keys(ENCRYPTION_SALT, ActiveSupport::MessageEncryptor.key_len(CIPHER)))
    end
  end
end
