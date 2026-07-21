# verse-otel

Vendor-neutral OpenTelemetry tracing for [Verse](https://github.com/verse-rb) services.

Out of the box you get spans for:

- every exposition invocation (HTTP endpoint or event subscriber), named `MyExpo#action`;
- the event bus — producer/consumer spans with trace context carried inside
  message headers, so a trace continues from the publishing service into
  every subscriber;
- whatever OTel instrumentations you enable — scoped to what the Verse stack
  runs on: `rack`/`sinatra` (verse-http), `pg` (verse-sequel), `redis`
  (verse-redis) and `net_http` (service-to-service calls).

No backend is hardwired. Standard `OTEL_*` environment variables configure
exporters (`OTEL_TRACES_EXPORTER=console` for stdout debugging, or add
`opentelemetry-exporter-otlp` and point `OTEL_EXPORTER_OTLP_ENDPOINT` at a
collector/Tempo/Jaeger). Without an exporter, spans are dropped. For Sentry,
use [verse-sentry](https://github.com/verse-rb/verse-sentry) with
`tracing: otel`.

## Usage

```ruby
# Gemfile
gem "verse-otel"

# Instrumentations are optional — add only the ones you enable in the config
# below. Booting with an instrumentation listed but its gem missing raises,
# with a message naming the gem to add.
gem "opentelemetry-instrumentation-rack"
gem "opentelemetry-instrumentation-sinatra"
gem "opentelemetry-instrumentation-net_http"
gem "opentelemetry-instrumentation-pg"
# gem "opentelemetry-instrumentation-redis"
```

`redis` is off by default on purpose: verse-otel already emits producer and
consumer spans for the event bus, and the raw command spans underneath are
dominated by the consumer's blocking `XREADGROUP` poll.

```yaml
# config/config.yml
plugins:
  - plugin: otel
    config:
      enabled: true
      service_name_prefix: "myapp-"
      instrumentations: [rack, sinatra, net_http, pg]
      db_statement: obfuscate   # include | obfuscate | omit
```

## Extension registry

Other plugins can contribute during their `on_init`; the registry is drained
when this plugin's `on_start` configures the SDK, so declaration order does
not matter:

```ruby
Verse::Otel.add_span_processor(processor)  # extra span processors
Verse::Otel.propagator = propagator        # replace the propagator
Verse::Otel.untraced_hosts << "host"       # never trace calls to these hosts
```

## Development

```
bundle install
bundle exec rspec
```
