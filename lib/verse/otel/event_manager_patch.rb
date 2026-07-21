# frozen_string_literal: true

module Verse
  module Otel
    # Prepended into Verse::Redis::Stream::EventManager (or any event manager
    # with the same publish/dispatch interface) by the plugin. Creates
    # producer/consumer spans and carries the trace context inside message
    # headers, so a trace continues from the publisher into every subscriber.
    module EventManagerPatch
      def publish(channel, content, headers: {}, **kw)
        return super unless Verse::Otel.enabled?

        Verse::Otel.tracer.in_span(
          "publish #{channel}",
          kind: :producer,
          attributes: messaging_attributes(channel)
        ) do
          super(channel, content, headers: Verse::Otel.inject_headers(headers), **kw)
        end
      end

      def publish_resource_event(resource_type:, resource_id:, event:, payload:, headers: {})
        return super unless Verse::Otel.enabled?

        channel = "#{resource_type}.#{event}"

        Verse::Otel.tracer.in_span(
          "publish #{channel}",
          kind: :producer,
          attributes: messaging_attributes(channel)
        ) do
          super(
            resource_type:, resource_id:, event:, payload:,
            headers: Verse::Otel.inject_headers(headers))
        end
      end

      # Single consume entry point for both simple and stream subscribers.
      # Messages published before the rollout carry no trace headers and
      # simply start a fresh root trace.
      def dispatch_message(channel, message)
        return super unless Verse::Otel.enabled?

        context = Verse::Otel.extract_context(message.headers)

        OpenTelemetry::Context.with_current(context) do
          Verse::Otel.tracer.in_span(
            "consume #{channel}",
            kind: :consumer,
            attributes: messaging_attributes(channel)
          ) do
            super
          end
        end
      end

      private

      def messaging_attributes(channel)
        {
          "messaging.system" => "verse",
          "messaging.destination.name" => channel.to_s
        }
      end
    end
  end
end
