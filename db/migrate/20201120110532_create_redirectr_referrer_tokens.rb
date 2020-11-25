class CreateRedirectrReferrerTokens < ActiveRecord::Migration[6.0]
  def change
    create_table :redirectr_referrer_tokens do |t|
      t.string :url,   index: true
      t.string :token, unique: true

      t.timestamps
    end
  end
end
