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

  describe 'chair_handler' do
    # let(:chair_logged_in_headers) { { 'Cookie' => "chair_session=3013d5ec84e1b230f913a17d71ef27c8d09d777b1cce7a3c1e2ffd4040848411" } }
    # describe 'POST /api/chair/chairs' do
    #   it do
    #     response = request(:post, '/api/chair/chairs', json: {
    #       name: 'QC-L13-8361',
    #       model: 'クエストチェア Lite',
    #       chair_register_token: '7188f2fb45c7d81a6ba30d1572cfff37b3857e66f7b50513bbf89eb2c4bc0ac7'
    #     })
    #     expect(response.status).to eq(201)
    #   end
    # end

    describe 'POST /api/chair/activity' do
      it do
        response = request(:post, '/api/chair/activity', json: {
          is_active: true
        }, headers: chair_logged_in_headers)
        expect(response.status).to eq(204)
      end
    end

    describe 'POST /api/chair/coordinate' do
      it do
        response = request(:post, '/api/chair/coordinate', json: {
          latitude: 0,
          longitude: 0
        }, headers: chair_logged_in_headers)
        expect(response.status).to eq(200)
      end
    end

    describe 'GET /api/chair/notification' do
      it do
        response = request(:get, '/api/chair/notification', headers: chair_logged_in_headers)
        expect(response.status).to eq(200)
      end
    end

    describe 'POST /api/chair/rides/{ride_id}/status' do
      it do
        ride_id = '01JDMP8B58XBZJ5S7A1NW9DSZV'
        response = request(:post, "/api/chair/rides/#{ride_id}/status", json: {
          status: 'ENROUTE'
        }, headers: chair_logged_in_headers)
        # TODO: 椅子に割り当てられていないライドなのでエラー
        expect(response.status).to eq(400)
      end
    end

  end
end
