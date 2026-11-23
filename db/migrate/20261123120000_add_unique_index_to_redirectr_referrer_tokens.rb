class AddUniqueIndexToRedirectrReferrerTokens < ActiveRecord::Migration[7.1]
  def change
    add_index :redirectr_referrer_tokens, :token, unique: true, if_not_exists: true
  end
end
