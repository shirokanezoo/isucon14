# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  class InternalHandler < BaseHandler
    # このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
    # GET /api/internal/matching
    get '/matching' do
      # MEMO: 一旦最も待たせているリクエストに適当な空いている椅子マッチさせる実装とする。おそらくもっといい方法があるはず…
      ride_id = db.query('SELECT id FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 1').first
      unless ride_id
        halt 204
      end

      10.times do
        matched_id = db.query('SELECT id FROM chairs WHERE is_active = TRUE AND is_busy = FALSE ORDER BY RAND() LIMIT 1').first
        unless matched_id
          puts "MATCHING:: chair_id=nil ride_id=#{ride_id.fetch(:id)} reason=no-available-chair"
          halt 204
        end

        db_transaction do |tx|
           matched = tx.xquery('SELECT * FROM chairs WHERE is_active = TRUE AND is_busy = FALSE AND id = ? LIMIT 1 for update', matched_id.fetch(:id)).first
           ride = tx.xquery('SELECT * FROM rides WHERE id = ? AND chair_is IS NULL LIMIT 1 for update', ride_id.fetch(:id)).first
           if matched && ride
             puts "MATCHING:: chair_id=#{matched.fetch(:id)} ride_id=#{ride.fetch(:id)} ok=true"
             tx.xquery('UPDATE chairs SET is_busy = TRUE WHERE id = ?', matched.fetch(:id))
             tx.xquery('UPDATE rides SET chair_id = ? WHERE id = ?', matched.fetch(:id), ride.fetch(:id))
             halt 204
           else
             puts "MATCHING:: chair_id=#{matched.fetch(:id)} ride_id=#{ride.fetch(:id)} reason=taken-after-tx"
           end
        end
      end

      204
    end
  end
end
