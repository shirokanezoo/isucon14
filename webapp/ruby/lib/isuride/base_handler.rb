# frozen_string_literal: true

require 'mysql2'
require 'mysql2-cs-bind'
require 'sinatra/base'
require 'sinatra/cookies'
require 'sinatra/json'
require 'sinatra/sse'
require 'redis'

# mysql2-cs-bind gem にマイクロ秒のサポートを入れる
module Mysql2CsBindPatch
  def quote(rawvalue)
    if rawvalue.respond_to?(:strftime)
      "'#{rawvalue.strftime('%Y-%m-%d %H:%M:%S.%6N')}'"
    else
      super
    end
  end
end
Mysql2::Client.singleton_class.prepend(Mysql2CsBindPatch)

module Isuride
  class BaseHandler < Sinatra::Base
    include Sinatra::SSE

    INITIAL_FARE = 500
    FARE_PER_DISTANCE = 100

    enable :logging
    set :show_exceptions, :after_handler

    class HttpError < Sinatra::Error
      attr_reader :code

      def initialize(code, message)
        super(message || "HTTP error #{code}")
        @code = code
      end
    end
    error HttpError do
      e = env['sinatra.error']
      status e.code
      json(message: e.message)
    end

    helpers Sinatra::Cookies

    helpers do
      def bind_json(data_class)
        body = JSON.parse(request.body.tap(&:rewind).read, symbolize_names: true)
        data_class.new(**data_class.members.map { |key| [key, body[key]] }.to_h)
      end

      def redis
        Thread.current[:redis] ||= connect_redis
      end

      def connect_redis
        Redis.new(
          host: ENV.fetch('ISUCON_REDIS_HOST', '127.0.0.1'),
          port: ENV.fetch('ISUCON_REDIS_PORT', '6379').to_i,
          db: 0
        )
      end

      def db
        Thread.current[:db] ||= connect_db
      end

      def connect_db
        Mysql2::Client.new(
          host: ENV.fetch('ISUCON_DB_HOST', '127.0.0.1'),
          port: ENV.fetch('ISUCON_DB_PORT', '3306').to_i,
          username: ENV.fetch('ISUCON_DB_USER', 'isucon'),
          password: ENV.fetch('ISUCON_DB_PASSWORD', 'isucon'),
          database: ENV.fetch('ISUCON_DB_NAME', 'isuride'),
          symbolize_keys: true,
          cast_booleans: true,
          database_timezone: :utc,
          application_timezone: :utc,
        )
      end

      def db_transaction(&block)
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

      def time_msec(time)
        time.to_i*1000 + time.usec/1000
      end

      def get_latest_ride_status(tx, ride_id)
        tx.xquery('SELECT status FROM ride_statuses WHERE ride_id = ? ORDER BY created_at DESC LIMIT 1', ride_id).first.fetch(:status)
      end

      # マンハッタン距離を求める
      def calculate_distance(a_latitude, a_longitude, b_latitude, b_longitude)
        (a_latitude - b_latitude).abs + (a_longitude - b_longitude).abs
      end

      def calculate_fare(pickup_latitude, pickup_longitude, dest_latitude, dest_longitude)
        metered_fare = FARE_PER_DISTANCE * calculate_distance(pickup_latitude, pickup_longitude, dest_latitude, dest_longitude)
        INITIAL_FARE + metered_fare
      end

      def calculate_discounted_fare(tx, user_id, ride, pickup_latitude, pickup_longitude, dest_latitude, dest_longitude)
        discount =
          if !ride.nil?
            dest_latitude = ride.fetch(:destination_latitude)
            dest_longitude = ride.fetch(:destination_longitude)
            pickup_latitude = ride.fetch(:pickup_latitude)
            pickup_longitude = ride.fetch(:pickup_longitude)

            # すでにクーポンが紐づいているならそれの割引額を参照
            coupon = tx.xquery('SELECT * FROM coupons WHERE used_by = ?', ride.fetch(:id)).first
            if coupon.nil?
              0
            else
              coupon.fetch(:discount)
            end
          else
            # 初回利用クーポンを最優先で使う
            coupon = tx.xquery("SELECT * FROM coupons WHERE user_id = ? AND code = 'CP_NEW2024' AND used_by IS NULL", user_id).first
            if coupon.nil?
              # 無いなら他のクーポンを付与された順番に使う
              coupon = tx.xquery('SELECT * FROM coupons WHERE user_id = ? AND used_by IS NULL ORDER BY created_at LIMIT 1', user_id).first
              if coupon.nil?
                0
              else
                coupon.fetch(:discount)
              end
            else
              coupon.fetch(:discount)
            end
          end

        metered_fare = FARE_PER_DISTANCE * calculate_distance(pickup_latitude, pickup_longitude, dest_latitude, dest_longitude)
        discounted_metered_fare = [metered_fare - discount, 0].max

        INITIAL_FARE + discounted_metered_fare
      end

      def ride_publish(tx, ride)
        ride_user_publish(tx, ride)
        ride_chair_publish(tx, ride)
      end

      def ride_user_publish(tx, ride)
        yet_sent_ride_status = tx.xquery('SELECT * FROM ride_statuses WHERE ride_id = ? AND app_sent_at IS NULL ORDER BY created_at ASC LIMIT 1', ride.fetch(:id)).first
        status =
          if yet_sent_ride_status.nil?
            get_latest_ride_status(tx, ride.fetch(:id))
          else
            yet_sent_ride_status.fetch(:status)
          end

        fare = calculate_discounted_fare(tx, @current_user.id, ride, ride.fetch(:pickup_latitude), ride.fetch(:pickup_longitude), ride.fetch(:destination_latitude), ride.fetch(:destination_longitude))

        data = {
          ride_id: ride.fetch(:id),
          pickup_coordinate: {
            latitude: ride.fetch(:pickup_latitude),
            longitude: ride.fetch(:pickup_longitude),
          },
          destination_coordinate: {
            latitude: ride.fetch(:destination_latitude),
            longitude: ride.fetch(:destination_longitude),
          },
          fare:,
          status:,
          created_at: time_msec(ride.fetch(:created_at)),
          updated_at: time_msec(ride.fetch(:updated_at)),
        }

        unless ride.fetch(:chair_id).nil?
          chair = tx.xquery('SELECT * FROM chairs WHERE id = ?', ride.fetch(:chair_id)).first
          stats = get_chair_stats(tx, chair.fetch(:id))
          data[:chair] = {
            id: chair.fetch(:id),
            name: chair.fetch(:name),
            model: chair.fetch(:model),
            stats:,
          }
        end

        redis.publish("user_notification:#{ride.fetch(:user_id)}", JSON.dump(data))
      end

      def ride_chair_publish(tx, ride)
        yet_sent_ride_status = tx.xquery('SELECT * FROM ride_statuses WHERE ride_id = ? AND chair_sent_at IS NULL ORDER BY created_at ASC LIMIT 1', ride.fetch(:id)).first
        status =
          if yet_sent_ride_status.nil?
            get_latest_ride_status(tx, ride.fetch(:id))
          else
            yet_sent_ride_status.fetch(:status)
          end

        user = tx.xquery('SELECT * FROM users WHERE id = ? FOR SHARE', ride.fetch(:user_id)).first

        # unless yet_sent_ride_status.nil?
        #   tx.xquery('UPDATE ride_statuses SET chair_sent_at = CURRENT_TIMESTAMP(6) WHERE id = ?', yet_sent_ride_status.fetch(:id))
        #   # XXX: original ha koko de is_busy=false
        # end

        data = {
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
        }

        redis.publish(
          "chair_notification:#{ride.fetch(:chair_id)}",
          JSON.dump({
            data:,
            yet_sent_ride_status_id: yet_sent_ride_status&.fetch(:id) || '',
          })
        )
      end
    end
  end
end
