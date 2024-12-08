require_relative './spec_helper'

RSpec.describe 'isuride' do
  before(:all) do
    response = request(:post, '/api/initialize', json: { payment_server: 'http://localhost:8080' })
    expect(response.status).to eq(200)
  end

  describe 'app_handler' do
    before(:all) do
      response = request(:post, '/api/app/users', json: {
        username: 'test_user1',
        firstname: 'John',
        lastname: 'Doe',
        date_of_birth: '1990-01-01'
      })
      expect(response.status).to eq(201)
      expect(response.headers['Set-Cookie']).to match(/app_session=([^;]+);/)
      @app_session = response.headers['Set-Cookie'].match(/app_session=([^;]+);/)[1]
    end
    let(:logged_in_headers) { { 'Cookie' => "app_session=#{@app_session}" } }

    describe 'POST /api/app/payment-methods' do
      it do
        response = request(:post, '/api/app/payment-methods', json: {
          token: '12345'
        }, headers: logged_in_headers)
        expect(response.status).to eq(204)
      end
    end

    describe 'GET /api/app/nearby-chairs' do
      it do
        response = request(:get, '/api/app/nearby-chairs', params: {
          latitude: 0,
          longitude: 0,
          distance: 50
        }, headers: logged_in_headers)
        expect(response.status).to eq(200)
      end
    end

    describe 'GET /api/app/notification' do
      it do
        response = request(:get, '/api/app/notification', headers: logged_in_headers)
        expect(response.status).to eq(200)
      end
    end

    describe 'GET /api/app/rides' do
      it do
        response = request(:get, '/api/app/rides', headers: logged_in_headers)
        expect(response.status).to eq(200)
      end
    end

    describe 'POST /api/app/rides' do
      it do
        response = request(:post, '/api/app/rides', json: {
          pickup_coordinate: {
            latitude: 0,
            longitude: 0
          },
          destination_coordinate: {
            latitude: 0,
            longitude: 0
          }
        }, headers: logged_in_headers)
        expect(response.status).to eq(202)
      end
    end

    describe 'POST /api/app/rides/estimated-fare' do
      it do
        response = request(:post, '/api/app/rides/estimated-fare', json: {
          pickup_coordinate: {
            latitude: 0,
            longitude: 0
          },
          destination_coordinate: {
            latitude: 0,
            longitude: 0
          }
        }, headers: logged_in_headers)
        expect(response.status).to eq(200)
      end
    end

    describe 'POST /api/app/rides/{ride_id}/evaluation' do
      it do
        ride_id = '01JDMP8B58XBZJ5S7A1NW9DSZV'
        response = request(:post, "/api/app/rides/#{ride_id}/evaluation", json: {
          evaluation: 5
        }, headers: logged_in_headers)
        # TODO: ARRIVED で終わってる ride がないから評価できない
        expect(response.status).to eq(400)
      end
    end

  end
end
