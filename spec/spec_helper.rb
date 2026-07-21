# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter do |file|
    file.filename !~ /lib/
  end
end

# Never let the SDK go looking for an OTLP exporter during specs.
ENV["OTEL_TRACES_EXPORTER"] = "none"

require "pry"
require "bundler"
Bundler.require

require "verse/otel"

module TelemetrySpecHelpers
  # Swap in an isolated tracer provider backed by an in-memory exporter.
  # Returns the exporter; the provider is restored after the example.
  def setup_test_tracing
    @__exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    provider.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(@__exporter)
    )

    @__previous_provider = OpenTelemetry.tracer_provider
    OpenTelemetry.tracer_provider = provider

    @__previous_propagation = OpenTelemetry.propagation
    OpenTelemetry.propagation = OpenTelemetry::Trace::Propagation::TraceContext.text_map_propagator

    @__exporter
  end

  def finished_spans
    @__exporter.finished_spans
  end

  def restore_test_tracing
    OpenTelemetry.tracer_provider = @__previous_provider if @__previous_provider
    OpenTelemetry.propagation = @__previous_propagation if @__previous_propagation
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.include TelemetrySpecHelpers

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    Verse.logger = Logger.new(IO::NULL)
  end

  config.after(:each) do
    restore_test_tracing
    Verse::Otel.reset!
  end
end
