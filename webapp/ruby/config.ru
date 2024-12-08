# frozen_string_literal: true

$LOAD_PATH.unshift(File.join('lib', __dir__))

require 'isuride/app_handler'
require 'isuride/chair_handler'
require 'isuride/initialize_handler'
require 'isuride/internal_handler'
require 'isuride/owner_handler'

if ENV['ISU_ENABLE_DATADOG'] == 'true'
  require 'datadog'
  require 'datadog/profiling/preload'
  # require 'datadog/statsd'

  Datadog.configure do |c|
    c.env = ENV.fetch('RACK_ENV', 'development')
    c.service = 'isuride'
    c.tracing.instrument :sinatra
    c.tracing.instrument :mysql2, comment_propagation: 'full', append_comment: true
    c.tracing.sampling.default_rate = 1.0
    c.profiling.enabled = true
    c.runtime_metrics.enabled = true
    # c.runtime_metrics.statsd = Datadog::Statsd.new
  end
end

map '/api/app/' do
  run Isuride::AppHandler
end
map '/api/chair/' do
  use Isuride::ChairHandler
end
map '/api/owner/' do
  use Isuride::OwnerHandler
end
map '/api/internal/' do
  use Isuride::InternalHandler
end
run Isuride::InitializeHandler
