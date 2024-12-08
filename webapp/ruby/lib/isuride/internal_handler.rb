# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  class InternalHandler < BaseHandler
    # このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
    # GET /api/internal/matching
    get '/matching' do
      # MEMO: 一旦最も待たせているリクエストに適当な空いている椅子マッチさせる実装とする。おそらくもっといい方法があるはず…
      ride = db.query('SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 1').first
      unless ride
        halt 204
      end

      10.times do
        matched_id = db.query('SELECT id FROM chairs WHERE is_active = TRUE AND is_busy = FALSE ORDER BY RAND() LIMIT 1').first
        unless matched_id
          halt 204
        end

        db_transaction do |tx|
           matched = tx.xquery('SELECT * FROM chairs WHERE is_active = TRUE AND is_busy = FALSE AND id = ? LIMIT 1 for update', matched_id.fetch(:id)).first
           puts "MATCHING:: chair_id=#{matched.fetch(:id)} ride_id=#{ride.fetch(:id)}"
           if matched
             tx.xquery('UPDATE chairs SET is_busy = TRUE WHERE id = ?', matched.fetch(:id))
             tx.xquery('UPDATE rides SET chair_id = ? WHERE id = ?', matched.fetch(:id), ride.fetch(:id))
             halt 204
           end
        end
      end

      204
    end
  end
end
