module Redirectr
  # One entry of config.x.redirectr.whitelist: a URL prefix such as
  # "https://my.host.com", "com.example.app:/oauth2redirect" or "mailto:".
  # A URL matches when scheme, host, port and the leading path segments
  # match; an entry consisting of a scheme only matches every URL of that
  # scheme.
  class WhitelistEntry
    attr_reader :scheme

    def initialize(source)
      @source = source.to_s
      if @source.match?(/\A[a-z][a-z\d+.\-]*:\z/i)
        @scheme = @source.chomp(':').downcase
      else
        uri = URI.parse(@source)
        raise ConfigurationError, "whitelist entry #{@source.inspect} lacks a scheme" if uri.scheme.nil?

        @scheme   = uri.scheme.downcase
        @host     = uri.host.to_s.downcase
        @port     = uri.port
        @opaque   = uri.opaque
        @segments = segments(uri.path)
      end
    rescue URI::InvalidURIError => error
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
        uri.opaque.to_s.start_with?(@opaque)
      elsif @segments
        uri.host.to_s.downcase == @host and
          uri.port == @port and
          segments(uri.path).first(@segments.size) == @segments
      else
        true
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

    def segments(path)
      path.to_s.split('/').reject(&:empty?)
    end
  end
end
