module Redirectr
  # One entry of config.x.redirectr.whitelist: a URL of a scheme other than
  # http and https, such as "com.example.app:/oauth2redirect" or
  # "mailto:support@example.com". A URL matches when its parts match the
  # entry's: scheme, host and port exactly, the path segment by segment as
  # prefix, and an opaque part such as a mail address exactly. The entry's
  # query and fragment are ignored.
  #
  # Hosts of http and https URLs are Rails' to decide, so such entries raise
  # and point to config.action_controller.allowed_redirect_hosts.
  class WhitelistEntry
    attr_reader :scheme

    def initialize(source)
      @source = source.to_s
      uri = URI.parse(@source)
      raise ConfigurationError, "whitelist entry #{@source.inspect} lacks a scheme" if uri.scheme.nil?

      @scheme = uri.scheme.downcase
      if SAFE_SCHEMES.include?(@scheme)
        raise ConfigurationError, "config.x.redirectr.whitelist entry #{@source.inspect} names an http(s) host; " \
                                  'list http(s) hosts in config.action_controller.allowed_redirect_hosts and remove this entry'
      end

      if uri.opaque
        @opaque = opaque_part(uri)
        raise ConfigurationError, "whitelist entry #{@source.inspect} names only a scheme" if @opaque.empty?
      else
        @host     = uri.host.to_s.downcase
        @port     = uri.port
        @segments = segments(uri.path)
        if @host.empty? and @segments.empty?
          raise ConfigurationError, "whitelist entry #{@source.inspect} names only a scheme"
        end
      end
    rescue URI::Error => error
      raise ConfigurationError, "invalid whitelist entry #{@source.inspect}: #{error.message}"
    end

    def dangerous?
      DANGEROUS_SCHEMES.include?(scheme)
    end

    def to_s
      @source
    end

    def match?(uri)
      return false unless uri.scheme.to_s.downcase == scheme

      if @opaque
        uri.opaque.present? and opaque_part(uri) == @opaque
      else
        uri.host.to_s.downcase == @host and
          uri.port == @port and
          segments(uri.path).first(@segments.size) == @segments
      end
    end

    private

    # The opaque part up to its query, e.g. the address of a mailto: URL.
    def opaque_part(uri)
      uri.opaque.split('?', 2).first.to_s
    end

    def segments(path)
      path.to_s.split('/').reject(&:empty?)
    end
  end
end
