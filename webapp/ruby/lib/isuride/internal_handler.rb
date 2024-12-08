# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  module MatchingSystem
    #KOSHIKAKE_CENTER = 300
    #CHAIR_CENTER = 0

    def self.calculate_distance(a_latitude, a_longitude, b_latitude, b_longitude)
       (a_latitude - b_latitude).abs + (a_longitude - b_longitude).abs
    end

    def self.db_transaction(db,&block)
      db.query('BEGIN')
      ok = false
      begin
        retval = block.call(db)
        db.query('COMMIT')
        ok = true
        retval
      ensure
        unless ok
          db.query('ROLLBACK')
        end
      end
    end

    def self.perform(db)
      pending_rides = db.query('SELECT id,pickup_latitude,pickup_longitude,destination_latitude,destination_longitude FROM rides WHERE chair_id IS NULL order by id asc').to_a.map do |r|
        r[:ride_distance] = calculate_distance(r.fetch(:pickup_latitude), r.fetch(:pickup_longitude), r.fetch(:destination_latitude), r.fetch(:destination_longitude))
        [r[:id], r]
      end.to_h
      if pending_rides.empty?
        puts "MATCHING-LOOP:: skip=no-pending-rides"
        return
      end

      available_chairs = db.query('SELECT chairs.id,chair_models.speed,chair_locations2.latitude,chair_locations2.longitude FROM chairs INNER JOIN chair_locations2 ON chairs.id = chair_locations2.id INNER JOIN chair_models ON chairs.model = chair_models.name  WHERE chairs.is_active = TRUE AND chairs.is_busy = FALSE').to_a.map do |r|
        r[:speed] = r.fetch(:speed).to_f
        r
      end

      puts "MATCHING-LOOP:: pending_rides_count=#{pending_rides.size} available_chairs_count=#{available_chairs.size} complexity=#{pending_rides.size} available_chairs=#{available_chairs.size}"

      available_chairs.each do |chair|
        puts "MATCHING-TRY:: step=1 chair_id=#{chair.fetch(:id)}"
        candidate_ride = pending_rides.each_value.sort_by do |ride|
          cspeed = chair.fetch(:speed)
          pickup_distance = calculate_distance(chair.fetch(:latitude), chair.fetch(:longitude), ride.fetch(:pickup_latitude), ride.fetch(:pickup_longitude))
          pickup_speed = pickup_distance / cspeed
          enroute_distance = ride.fetch(:ride_distance)
          enroute_speed = enroute_distance / cspeed
          puts "MATCHING-CANDIDATE:: ride_id=#{ride.fetch(:id)} chair_id=#{chair.fetch(:id)} pickup=#{pickup_distance}|#{pickup_speed} enroute=#{enroute_distance}/#{enroute_speed} total=#{pickup_distance+enroute_distance}/#{pickup_speed+enroute_speed}"
          pickup_speed + enroute_speed
        end.first

        puts "MATCHING-TRY:: step=2 chair_id=#{chair.fetch(:id)} candidate_ride_id=#{candidate_ride&.fetch(:id)}"
        unless candidate_ride
          next
        end

        begin
          db_transaction(db) do |tx|
             chair2 = tx.xquery('SELECT id FROM chairs WHERE is_active = TRUE AND is_busy = FALSE AND id = ? LIMIT 1 for update', candidate_chair.fetch(:id)).first
             ride2 = tx.xquery('SELECT id FROM rides WHERE id = ? AND chair_id IS NULL LIMIT 1 for update', ride.fetch(:id)).first
             if chair2 && ride2
               tx.xquery("UPDATE ride_statuses SET chair_id = ? WHERE ride_id = ? and status = 'MATCHING'", chair2.fetch(:id), ride2.fetch(:id))
               tx.xquery('UPDATE chairs SET is_busy = TRUE, underway_ride_id = ? WHERE id = ?', ride2.fetch(:id), chair2.fetch(:id))
               tx.xquery('UPDATE rides SET chair_id = ? WHERE id = ?', chair2.fetch(:id), ride2.fetch(:id))
               puts "MATCHING-RESOLVE:: chair_id=#{chair2.fetch(:id)} ride_id=#{ride2.fetch(:id)} ok=true"
             else
               puts "MATCHING-RESOLVE:: chair_id=#{chair2.fetch(:id)} ride_id=#{ride2.fetch(:id)} reason=taken-after-tx"
             end
          end
          pending_rides.delete(candidate_ride.fetch(:id))
        rescue Mysql2::Error => e
          warn "MATCHING-ERROR:: chair_id=#{chair.fetch(:id)} candidate_ride_id=#{candidate_ride.fetch(:id)} exception=#{e.full_message}"
        end

        if available_rides.empty?
          puts "MATCHING-LOOP:: skip=no-more-available-rides"
          return
        end
      end
    end
  end

  class InternalHandler < BaseHandler
    # このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
    # GET /api/internal/matching
    get '/matching' do
      MatchingSystem.perform(db)
      204
    end
  end
end
