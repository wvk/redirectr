module Redirectr
  class ReferrerToken

    class GlobalVarStorage

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

  end
end