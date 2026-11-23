module Redirectr
  # One entry of config.x.redirectr.whitelist: a URL such as
  # "https://my.host.com", "com.example.app:/oauth2redirect" or
  # "mailto:support@example.com". A URL matches when its parts match the
  # entry's: scheme, host and port exactly, the path segment by segment as
  # prefix, and an opaque part such as a mail address exactly. The entry's
  # query and fragment are ignored.
  class WhitelistEntry
    attr_reader :scheme

    def initialize(source)
      @source = source.to_s
      uri = URI.parse(@source)
      raise ConfigurationError, "whitelist entry #{@source.inspect} lacks a scheme" if uri.scheme.nil?

      @scheme = uri.scheme.downcase
      if uri.opaque
        @opaque = opaque_part(uri)
        raise ConfigurationError, "whitelist entry #{@source.inspect} names only a scheme" if @opaque.empty?
      else
        @host     = uri.host.to_s.downcase
        @port     = uri.port
        @segments = segments(uri.path)
        if @host.empty? and @segments.empty?
          raise ConfigurationError, "whitelist entry #{@source.inspect} names only a scheme"
        elsif @host.empty? and http?
          raise ConfigurationError, "whitelist entry #{@source.inspect} lacks a host"
        end
      end
    rescue URI::Error => error
      raise ConfigurationError, "invalid whitelist entry #{@source.inspect}: #{error.message}"
    end

    def http?
      SAFE_SCHEMES.include?(scheme)
    end

    def dangerous?
      DANGEROUS_SCHEMES.include?(scheme)
    end

    def to_s
      @source
    end

    # With strict_scheme: false, an http entry also matches https URLs and
    # vice versa.
    def match?(uri, strict_scheme: true)
      return false unless scheme_matches?(uri.scheme.to_s.downcase, strict_scheme)

      if @opaque
        uri.opaque.present? and opaque_part(uri) == @opaque
      else
        uri.host.to_s.downcase == @host and
          uri.port == @port and
          segments(uri.path).first(@segments.size) == @segments
      end
    end

    private

    def scheme_matches?(other, strict_scheme)
      if strict_scheme or not http?
        other == scheme
      else
        SAFE_SCHEMES.include?(other)
      end
    end

    # The opaque part up to its query, e.g. the address of a mailto: URL.
    def opaque_part(uri)
      uri.opaque.split('?', 2).first.to_s
    end

    def segments(path)
      path.to_s.split('/').reject(&:empty?)
    end
  end
end
