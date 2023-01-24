module Redirectr
  class ReferrerToken

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

  end
end