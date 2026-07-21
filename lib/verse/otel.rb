# frozen_string_literal: true

require "verse/core"
require "opentelemetry/sdk"

require_relative "otel/version"
require_relative "otel/config"
require_relative "otel/exposition_handler"
require_relative "otel/event_manager_patch"
require_relative "otel/plugin"

module Verse
  # Vendor-neutral OpenTelemetry integration for Verse.
  #
  # Other plugins (e.g. verse-sentry in otel mode) contribute to the
  # registry below during their `on_init`; the registry is drained by
  # `setup_sdk!`, which the plugin calls from `on_start` — after every
  # plugin had a chance to contribute, regardless of declaration order.
  module Otel
    extend self

    # Maps config instrumentation names to [gem to require, OTel class name].
    #
    # Scoped to what the Verse stack itself runs on: rack/sinatra come from
    # verse-http, pg from verse-sequel, redis from verse-redis. net_http is
    # the stdlib client Verse services use to call each other, and carries
    # the untraced_hosts option. Instrumentations for libraries no Verse gem
    # uses do not belong here — a service needing one can `c.use` it via a
    # contributed span processor rather than widening this table.
    INSTRUMENTATIONS = {
      rack: ["opentelemetry-instrumentation-rack", "OpenTelemetry::Instrumentation::Rack"],
      sinatra: ["opentelemetry-instrumentation-sinatra", "OpenTelemetry::Instrumentation::Sinatra"],
      net_http: ["opentelemetry-instrumentation-net_http", "OpenTelemetry::Instrumentation::Net::HTTP"],
      pg: ["opentelemetry-instrumentation-pg", "OpenTelemetry::Instrumentation::PG"],
      redis: ["opentelemetry-instrumentation-redis", "OpenTelemetry::Instrumentation::Redis"]
    }.freeze

    attr_accessor :config
    attr_writer :enabled

    # Contributed by other plugins; consumed once by setup_sdk!.
    attr_accessor :propagator

    def enabled?
      !!@enabled
    end

    def tracer
      @tracer ||= OpenTelemetry.tracer_provider.tracer("verse-otel", VERSION)
    end

    def span_processors
      @span_processors ||= []
    end

    def add_span_processor(processor)
      span_processors << processor
    end

    def untraced_hosts
      @untraced_hosts ||= []
    end

    # Configure the global OpenTelemetry SDK. Called by the plugin from
    # on_start; kept here so it can be exercised directly in tests.
    def setup_sdk!(service_name:, service_instance_id: nil, environment: nil)
      # Without an explicit exporter choice, drop spans instead of letting the
      # SDK look for an OTLP exporter gem that may not be installed. Standard
      # OTEL_* environment variables still take precedence when set.
      ENV["OTEL_TRACES_EXPORTER"] ||= "none"

      cfg = config

      # Resolve instrumentations up front. OpenTelemetry::SDK.configure wraps
      # its block in a blanket `rescue StandardError` that downgrades anything
      # raised inside to a logged ConfigurationError — and aborts the rest of
      # the configuration with it. Failing out here instead keeps a bad config
      # a hard boot error rather than a silently unconfigured SDK.
      instrumentations = resolve_instrumentations(cfg)

      OpenTelemetry::SDK.configure do |c|
        c.service_name = service_name

        resource_attributes = { "service.instance.id" => service_instance_id,
                                "deployment.environment" => environment }.compact
        unless resource_attributes.empty?
          c.resource = OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)
        end

        instrumentations.each { |klass, options| c.use klass, options }
      end

      span_processors.each do |processor|
        OpenTelemetry.tracer_provider.add_span_processor(processor)
      end

      OpenTelemetry.propagation = propagator if propagator

      Verse.logger&.info { "Verse::Otel enabled" }
    end

    # -- trace-context propagation over the event bus --

    # Merge the current trace context into event headers (producer side).
    def inject_headers(headers)
      return headers unless enabled?

      carrier = {}
      OpenTelemetry.propagation.inject(carrier)
      headers.merge(carrier.transform_keys(&:to_sym))
    end

    # Rebuild the trace context from event headers (consumer side).
    # Verse messages round-trip through msgpack with symbolized keys.
    def extract_context(headers)
      OpenTelemetry.propagation.extract((headers || {}).transform_keys(&:to_s))
    end

    # Test seam: clears all module state.
    def reset!
      @enabled = false
      @config = nil
      @tracer = nil
      @span_processors = nil
      @propagator = nil
      @untraced_hosts = nil
    end

    private

    # [[otel class name, options], ...] for every configured instrumentation.
    # Raises on an unknown name or a missing gem, before the SDK is touched.
    def resolve_instrumentations(cfg)
      cfg.instrumentations.map do |name|
        name = name.to_sym

        gem_name, klass = INSTRUMENTATIONS.fetch(name) do
          raise ArgumentError, "Unknown instrumentation `#{name}`. Known: #{INSTRUMENTATIONS.keys.join(", ")}"
        end

        begin
          # The instrumentation only installs when its target is loaded.
          require "net/http" if name == :net_http
          require gem_name
        rescue LoadError
          Verse.logger&.error { "Please add `#{gem_name}` to your Gemfile to use the `#{name}` instrumentation!" }
          raise
        end

        [klass, instrumentation_options(name, cfg)]
      end
    end

    def instrumentation_options(name, cfg)
      case name
      when :net_http
        { untraced_hosts: (cfg.untraced_hosts + untraced_hosts).uniq }
      when :pg
        { db_statement: cfg.db_statement }
      else
        {}
      end
    end
  end
end
