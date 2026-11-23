require 'test_helper'
require 'redirectr/referrer_token/active_record_storage'

class Redirectr::ActiveRecordStorageTest < ActiveSupport::TestCase
  test 'tokens are unique' do
    Redirectr::ReferrerToken::ActiveRecordStorage.create!(url: '/a', token: 'abc')
    assert_raises(ActiveRecord::RecordNotUnique) do
      Redirectr::ReferrerToken::ActiveRecordStorage.create!(url: '/b', token: 'abc')
    end
  end
end
