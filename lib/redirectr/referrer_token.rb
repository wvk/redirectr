require 'active_model'

module Redirectr
  # A referrer URL together with its value for the referrer param: #to_s
  # returns the URL, #to_param the value the referrer format produces.
  class ReferrerToken

    extend ActiveModel::Naming

    attr_reader :url, :token

    def initialize(url, token=nil)
      @url   = url
      @token = token || ReferrerFormat.current.encode(url)
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

    # Raises Redirectr::InvalidReferrerToken for values the referrer format
    # rejects.
    def self.from_param(param)
      new ReferrerFormat.current.decode(param), param
    end

  end
end
