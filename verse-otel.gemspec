# frozen_string_literal: true

require_relative "lib/verse/otel/version"

Gem::Specification.new do |spec|
  spec.name = "verse-otel"
  spec.version = Verse::Otel::VERSION
  spec.authors = ["Ingedata"]

  spec.summary = "OpenTelemetry integration for the Verse framework"
  spec.description = "Vendor-neutral OpenTelemetry tracing for Verse services: " \
                     "spans for expositions, HTTP, SQL and the event bus, with " \
                     "trace-context propagation across services and Redis streams."
  spec.homepage = "https://github.com/verse-rb/verse-otel"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/verse-rb/verse-otel"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "opentelemetry-sdk", "~> 1.0"

  # OTel instrumentations (rack, sinatra, net_http, pg, redis) are soft
  # dependencies: none is loaded unless listed in the plugin's
  # `instrumentations:` config. Add the ones you enable to your service's
  # Gemfile — see the README.
end
