# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  class InternalHandler < BaseHandler
    # このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
    # GET /api/internal/matching
    get '/matching' do
      pending_rides = db.query('SELECT id,pickup_latitude,pickup_longitude,destination_latitude,destination_longitude FROM rides WHERE chair_id IS NULL order by id asc').to_a.map do |r|
        r[:ride_distance] = calculate_distance(r.fetch(:pickup_latitude), r.fetch(:pickup_longitude), r.fetch(:destination_latitude), r.fetch(:destination_longitude))
        r
      end
      if pending_rides.empty?
        puts "MATCHING-LOOP:: skip=no-pending-rides"
        halt 204
      end

      available_chairs = db.query('SELECT chairs.id,chair_models.speed,chair_locations2.latitude,chair_locations2.longitude FROM chairs INNER JOIN chair_locations2 ON chairs.id = chair_locations2.id INNER JOIN chair_models ON chairs.model = chair_models.name  WHERE chairs.is_active = TRUE AND chairs.is_busy = FALSE').to_a.map do |r|
        r[:speed] = r.fetch(:speed).to_f
        [r[:id], r]
      end.to_h

      puts "MATCHING-LOOP:: pending_rides_count=#{pending_rides.size} available_chairs_count=#{available_chairs.size} complexity=#{pending_rides.size} available_chairs=#{available_chairs.size}"

      pending_rides.each do |ride|
        puts "MATCHING-TRY:: step=1 ride_id=#{ride.fetch(:id)}"
        candidate_chair = available_chairs.each_value.sort_by do |c|
          cspeed = c.fetch(:speed)
          pickup_distance = calculate_distance(c.fetch(:latitude) || 0, c.fetch(:longitude) || 0, ride.fetch(:pickup_latitude), ride.fetch(:pickup_longitude))
          pickup_speed = pickup_distance / cspeed
          enroute_distance = ride.fetch(:ride_distance)
          enroute_speed = enroute_distance / cspeed
          puts "MATCHING-CANDIDATE:: ride_id=#{ride.fetch(:id)} chair_id=#{c.fetch(:id)} pickup=#{pickup_distance}|#{pickup_speed} enroute=#{enroute_distance}/#{enroute_speed} total=#{pickup_distance+enroute_distance}/#{pickup_speed+enroute_speed}"
          pickup_speed + enroute_speed
        end.first

        puts "MATCHING-TRY:: step=2 ride_id=#{ride.fetch(:id)} candidate_chair_id=#{candidate_chair&.fetch(:id)}"
        unless candidate_chair
          halt 204
        end

        begin
          updated_ride, updated_chair, updated_ride_status = db_transaction do |tx|
            chair2 = tx.xquery('SELECT id FROM chairs WHERE is_active = TRUE AND is_busy = FALSE AND id = ? LIMIT 1 for update', candidate_chair.fetch(:id)).first
            ride2 = tx.xquery('SELECT id FROM rides WHERE id = ? AND chair_id IS NULL LIMIT 1 for update', ride.fetch(:id)).first
            if chair2 && ride2
              tx.xquery("UPDATE ride_statuses SET chair_id = ? WHERE ride_id = ? and status = 'MATCHING'", chair2.fetch(:id), ride2.fetch(:id))
              tx.xquery('UPDATE chairs SET is_busy = TRUE, underway_ride_id = ? WHERE id = ?', ride2.fetch(:id), chair2.fetch(:id))
              tx.xquery('UPDATE rides SET chair_id = ? WHERE id = ?', chair2.fetch(:id), ride2.fetch(:id))
              chair2[:is_busy] = true
              chair2[:underway_ride_id] = ride2[:chair_id] = chair2.fetch(:id)
              puts "MATCHING-RESOLVE:: chair_id=#{chair2.fetch(:id)} ride_id=#{ride2.fetch(:id)} ok=true"
              [ride2, chair2, tx.xquery("SELECT * FROM ride_statuses WHERE ride_id = ? and status = 'MATCHING'", ride2.fetch(:id)).first]
            else
              puts "MATCHING-RESOLVE:: chair_id=#{chair2.fetch(:id)} ride_id=#{ride2.fetch(:id)} reason=taken-after-tx"
              available_chairs.delete(candidate_chair.fetch(:id))
              nil
            end
          end
          ride_publish(db:, ride: updated_ride, ride_status: updated_ride_status, chair: updated_chair) if updated_ride
          available_chairs.delete(candidate_chair.fetch(:id))
        rescue Mysql2::Error => e
          warn "MATCHING-ERROR:: ride_id=#{ride.fetch(:id)} candidate_chair_id=#{candidate_chair.fetch(:id)} exception=#{e.full_message}"
        end

        if available_chairs.empty?
          puts "MATCHING-LOOP:: skip=no-more-available-chairs"
          halt 204
        end

        204
      end
    end
  end
end
