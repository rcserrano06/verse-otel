# frozen_string_literal: true

module Verse
  module Otel
    # Wraps every exposition invocation (HTTP endpoint or event subscriber)
    # in a named OpenTelemetry span. Exceptions are recorded on the span and
    # re-raised; error reporting is another gem's concern (e.g. verse-sentry).
    #
    # Registered by the plugin's on_init, which runs before exposition
    # subclasses load — they snapshot the handler list at class-load time.
    class ExpositionHandler < Verse::Exposition::Handler
      def call
        return call_next unless Verse::Otel.enabled?

        expo = exposition
        name = "#{expo.class.name}##{expo.current_action}"

        Verse::Otel.tracer.in_span(name) do |span|
          span.set_attribute("verse.hook", expo.hook.class.name)
          span.set_attribute("verse.action", expo.current_action.to_s)
          call_next
        end
      end
    end
  end
end
