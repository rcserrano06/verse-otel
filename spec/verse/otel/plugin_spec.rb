# frozen_string_literal: true

RSpec.describe Verse::Otel::Plugin do
  let(:logger) { Logger.new(IO::NULL) }
  let(:plugin_config) do
    {
      service_name_prefix: "test-",
      instrumentations: [:net_http],
      untraced_hosts: ["config.example.com"]
    }
  end
  let(:plugin) { described_class.new("otel", plugin_config, {}, logger) }

  before do
    allow(Verse).to receive(:service_name).and_return("myservice")
    allow(Verse).to receive(:service_id).and_return("instance-1")
  end

  after do
    # Not remove_handler: it calls `.first` on every entry, and the seed
    # CheckAuthenticationHandler is stored as a bare class, not an array.
    Verse::Exposition::Base.handlers.reject! do |entry|
      entry.is_a?(Array) && entry.first == Verse::Otel::ExpositionHandler
    end
  end

  describe "#on_init" do
    it "registers the exposition handler as outermost" do
      plugin.on_init

      handlers = Verse::Exposition::Base.handlers.map { |h| h.is_a?(Array) ? h.first : h }
      expect(handlers.first).to eq Verse::Otel::ExpositionHandler
      expect(Verse::Otel.enabled?).to be true
    end

    it "patches the redis event manager when verse-redis is loaded" do
      event_manager = Class.new
      stub_const("Verse::Redis::Stream::EventManager", event_manager)

      plugin.on_init

      expect(event_manager.ancestors).to include(Verse::Otel::EventManagerPatch)
    end

    it "skips the event manager patch when verse-redis is absent" do
      hide_const("Verse::Redis") if defined?(Verse::Redis)

      expect { plugin.on_init }.not_to raise_error
      expect(Verse::Otel.enabled?).to be true
    end

    context "when disabled" do
      let(:plugin_config) { { enabled: false } }

      it "registers nothing" do
        plugin.on_init

        handlers = Verse::Exposition::Base.handlers.map { |h| h.is_a?(Array) ? h.first : h }
        expect(handlers).not_to include(Verse::Otel::ExpositionHandler)
        expect(Verse::Otel.enabled?).to be false
      end
    end

    context "with an invalid config" do
      let(:plugin_config) { { db_statement: :shout } }

      it "raises" do
        expect { plugin.on_init }.to raise_error(/Invalid verse-otel plugin config/)
      end
    end
  end

  describe "#on_start" do
    let(:contributed_processor) do
      Class.new do
        attr_reader :started

        def on_start(_span, _context) = @started = true
        def on_finish(_span); end
        def force_flush(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS
        def shutdown(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS
      end.new
    end

    let(:contributed_propagator) do
      OpenTelemetry::Trace::Propagation::TraceContext.text_map_propagator
    end

    it "configures the SDK and drains the registry" do
      plugin.on_init

      Verse::Otel.add_span_processor(contributed_processor)
      Verse::Otel.propagator = contributed_propagator
      Verse::Otel.untraced_hosts << "contributed.example.com"

      plugin.on_start(:server)

      expect(OpenTelemetry.tracer_provider).to be_a(OpenTelemetry::SDK::Trace::TracerProvider)
      expect(OpenTelemetry.tracer_provider.resource.attribute_enumerator.to_h)
        .to include("service.name" => "test-myservice", "service.instance.id" => "instance-1")

      net_http_config = OpenTelemetry::Instrumentation::Net::HTTP::Instrumentation.instance.config
      expect(net_http_config[:untraced_hosts])
        .to include("config.example.com", "contributed.example.com")

      expect(OpenTelemetry.propagation).to eq contributed_propagator

      Verse::Otel.tracer.in_span("check") {}
      expect(contributed_processor.started).to be true
    end

    context "when disabled" do
      let(:plugin_config) { { enabled: false } }

      it "does not touch the SDK" do
        plugin.on_init

        expect(OpenTelemetry::SDK).not_to receive(:configure)
        plugin.on_start(:server)
      end
    end
  end
end
