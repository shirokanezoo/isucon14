# frozen_string_literal: true

require 'ulid'

require 'isuride/base_handler'

module Isuride
  class ChairHandler < BaseHandler
    CurrentChair = Data.define(
      :id,
      :owner_id,
      :name,
      :model,
      :is_active,
      :is_busy,
      :underway_ride_id,
      :access_token,
      :created_at,
      :updated_at,
    )

    before do
      if request.path == '/api/chair/chairs'
        next
      end

      access_token = cookies[:chair_session]
      if access_token.nil?
        raise HttpError.new(401, 'chair_session cookie is required')
      end
      chair = db.xquery('SELECT * FROM chairs WHERE access_token = ? LIMIT 1', access_token).first
      if chair.nil?
        raise HttpError.new(401, 'invalid access token')
      end

      @current_chair = CurrentChair.new(**chair)
    end

    ChairPostChairsRequest = Data.define(:name, :model, :chair_register_token)

    # POST /api/chair/chairs
    post '/chairs' do
      req = bind_json(ChairPostChairsRequest)
      if req.name.nil? || req.model.nil? || req.chair_register_token.nil?
        raise HttpError.new(400, 'some of required fields(name, model, chair_register_token) are empty')
      end

      owner = db.xquery('SELECT * FROM owners WHERE chair_register_token = ?', req.chair_register_token).first
      if owner.nil?
        raise HttpError.new(401, 'invalid chair_register_token')
      end

      chair_id = ULID.generate
      access_token = SecureRandom.hex(32)

      db.xquery('INSERT INTO chairs (id, owner_id, name, model, is_active, access_token) VALUES (?, ?, ?, ?, ?, ?)', chair_id, owner.fetch(:id), req.name, req.model, false, access_token)
      db.xquery('INSERT INTO chair_locations2 (id) VALUES (?)', chair_id)

      cookies.set(:chair_session, httponly: false, value: access_token, path: '/')
      status(201)
      json(id: chair_id, owner_id: owner.fetch(:id))
    end

    PostChairActivityRequest = Data.define(:is_active)

    # POST /api/chair/activity
    post '/activity' do
      req = bind_json(PostChairActivityRequest)

      db.xquery('UPDATE chairs SET is_active = ? WHERE id = ?', req.is_active, @current_chair.id)

      status(204)
    end

    PostChairCoordinateRequest = Data.define(:latitude, :longitude)

    # POST /api/chair/coordinate
    post '/coordinate' do
      req = bind_json(PostChairCoordinateRequest)

      response = db_transaction do |tx|
        distance_updated_at = Time.now
        distance = 0
        location = tx.xquery('SELECT * FROM chair_locations2 WHERE id = ? LIMIT 1 FOR UPDATE', @current_chair.id).first
        if location[:latitude] && location[:longitude]
          distance = (req.latitude - location[:latitude]).abs + (req.longitude - location[:longitude]).abs + location[:total_distance]
        end

        tx.xquery(
          'UPDATE chair_locations2 SET latitude = ?, longitude = ?, total_distance = ?, total_distance_updated_at = ? WHERE id = ?',
          req.latitude, req.longitude, distance, distance_updated_at, @current_chair.id,
        )

        ride = tx.xquery('SELECT * FROM rides WHERE chair_id = ? ORDER BY updated_at DESC LIMIT 1', @current_chair.id).first
        unless ride.nil?
          status = get_latest_ride_status(tx, ride.fetch(:id))
          if status != 'COMPLETED' && status != 'CANCELED'
            if req.latitude == ride.fetch(:pickup_latitude) && req.longitude == ride.fetch(:pickup_longitude) && status == 'ENROUTE'
              tx.xquery('INSERT INTO ride_statuses (id, ride_id, user_id, chair_id, status) VALUES (?, ?, ?, ?, ?)', ULID.generate, ride.fetch(:id), ride.fetch(:user_id), ride.fetch(:chair_id), 'PICKUP')
            end

            if req.latitude == ride.fetch(:destination_latitude) && req.longitude == ride.fetch(:destination_longitude) && status == 'CARRYING'
              tx.xquery('INSERT INTO ride_statuses (id, ride_id, user_id, chair_id, status) VALUES (?, ?, ?, ?, ?)', ULID.generate, ride.fetch(:id), ride.fetch(:user_id), ride.fetch(:chair_id),'ARRIVED')
            end
          end
        end

        { recorded_at: time_msec(distance_updated_at) }
      end

      json(response)
    end

    # GET /api/chair/notification
    get '/notification' do
      response = db_transaction do |tx|
        yet_sent_ride_status = tx.xquery('SELECT * FROM ride_statuses WHERE chair_id = ? and chair_sent_at is null for share', @current_chair.id).to_a.sort_by do |s|
          s[:ride_id] # TODO: index
        end.first
        unless yet_sent_ride_status
          halt json(data: nil, retry_after_ms: 500)
        end

        status = yet_sent_ride_status.fetch(:status)

        ride = tx.xquery('SELECT * FROM rides WHERE id = ? FOR SHARE', yet_sent_ride_status.fetch(:ride_id)).first
        user = tx.xquery('SELECT * FROM users WHERE id = ? FOR SHARE', yet_sent_ride_status.fetch(:user_id)).first

        tx.xquery('UPDATE ride_statuses SET chair_sent_at = CURRENT_TIMESTAMP(6) WHERE id = ?', yet_sent_ride_status.fetch(:id))
        tx.xquery("UPDATE chairs SET is_busy = FALSE, underway_ride_id = '' where id = ? and underway_ride_id = ?", ride.fetch(:chair_id), ride.fetch(:id)) if status == 'COMPLETED'

        {
          data: {
            ride_id: ride.fetch(:id),
            user: {
              id: user.fetch(:id),
              name: "#{user.fetch(:firstname)} #{user.fetch(:lastname)}",
            },
            pickup_coordinate: {
              latitude: ride.fetch(:pickup_latitude),
              longitude: ride.fetch(:pickup_longitude),
            },
            destination_coordinate: {
              latitude: ride.fetch(:destination_latitude),
              longitude: ride.fetch(:destination_longitude),
            },
            status:,
          },
          retry_after_ms: 30,
        }
      end

      json(response)
    end

    PostChairRidesRideIDStatusRequest = Data.define(:status)

    # POST /api/chair/rides/:ride_id/status
    post '/rides/:ride_id/status' do
      ride_id = params[:ride_id]
      req = bind_json(PostChairRidesRideIDStatusRequest)

      tx=db; begin#db_transaction do |tx|
        ride = tx.xquery('SELECT * FROM rides WHERE id = ?', ride_id).first
        if ride.fetch(:chair_id) != @current_chair.id
          raise HttpError.new(400, 'not assigned to this ride')
        end

        case req.status
	# Acknowledge the ride
        when 'ENROUTE'
          tx.xquery('INSERT INTO ride_statuses (id, ride_id, user_id, chair_id, status) VALUES (?, ?, ?, ?, ?)', ULID.generate, ride.fetch(:id), ride.fetch(:user_id), ride.fetch(:chair_id),'ENROUTE')
	# After Picking up user
        when 'CARRYING'
          status = get_latest_ride_status(tx, ride.fetch(:id))
          if status != 'PICKUP'
            raise HttpError.new(400, 'chair has not arrived yet')
          end
          tx.xquery('INSERT INTO ride_statuses (id, ride_id, user_id, chair_id, status) VALUES (?, ?, ?, ?, ?)', ULID.generate, ride.fetch(:id), ride.fetch(:user_id), ride.fetch(:chair_id), 'CARRYING')
        else
          raise HttpError.new(400, 'invalid status')
        end
      end

      status(204)
    end
  end
end
