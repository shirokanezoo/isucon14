require 'httpx'

module Helpers
  TEST_TARGET_URI = ENV.fetch('TEST_TARGET_URI', 'http://localhost:9292')

  def request(method, path, **options)
    uri = URI.join(TEST_TARGET_URI, path)
    HTTPX.request(method, uri, **options)
  end
end

RSpec.configure do |config|
  config.include Helpers
end
