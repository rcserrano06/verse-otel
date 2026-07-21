# frozen_string_literal: true

module Verse
  module Otel
    # Verse plugin. Declare it in a service's config.yml:
    #
    #   plugins:
    #     - plugin: otel
    #       config:
    #         enabled: <%= !ENV["SENTRY_DSN"].to_s.empty? %>
    #         service_name_prefix: "myapp-"
    #         instrumentations: [rack, sinatra, net_http, pg]
    #         db_statement: obfuscate
    #
    # on_init registers the verse-level instrumentation (exposition handler,
    # event-manager patch) before exposition classes load; on_start configures
    # the OpenTelemetry SDK once every other plugin had a chance to contribute
    # span processors, a propagator, or untraced hosts to the Verse::Otel
    # registry.
    class Plugin < Verse::Plugin::Base
      # :nocov:
      def description
        "OpenTelemetry instrumentation for Verse"
      end
      # :nocov:

      def on_init
        @config = validate_config

        Verse::Otel.config = @config
        return unless @config.enabled

        Verse::Otel.enabled = true

        Verse::Exposition::Base.prepend_handler(ExpositionHandler)

        return unless defined?(Verse::Redis::Stream::EventManager)

        Verse::Redis::Stream::EventManager.prepend(EventManagerPatch)
      end

      def on_start(_mode)
        return unless @config.enabled

        Verse::Otel.setup_sdk!(
          service_name: "#{@config.service_name_prefix}#{Verse.service_name}",
          service_instance_id: Verse.service_id,
          environment: ENV.fetch("APP_ENVIRONMENT", "development")
        )
      end

      private

      def validate_config
        result = Config::Schema.validate(config)
        return result.value if result.success?

        raise "Invalid verse-otel plugin config: #{result.errors}"
      end
    end
  end
end
