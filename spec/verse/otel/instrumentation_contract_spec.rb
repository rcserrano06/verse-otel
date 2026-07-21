# frozen_string_literal: true

require "net/http"
require "opentelemetry-instrumentation-net_http"
require "opentelemetry-instrumentation-pg"

# Checks the options we hand to upstream instrumentations against the options
# those instrumentations actually declare.
#
# This matters because OTel does not reject a bad option: an unknown key is
# ignored and an out-of-range value falls back to the declared default, both
# with nothing louder than a log line. So an upstream rename would silently
# turn `db_statement: omit` into `obfuscate` and start putting SQL text in
# spans, with every one of our own specs still green.
#
# Instrumentations declare their options at class-definition time, so this
# reads the schema without the instrumented library being installed.
RSpec.describe "instrumentation option contract" do
  def declared_options(klass)
    klass::Instrumentation.instance
                          .instance_variable_get(:@options)
                          .to_h { |o| [o[:name], o] }
  end

  def options_we_send(name, **config_overrides)
    config = Verse::Otel::Config::Schema.validate(config_overrides).value
    Verse::Otel.send(:instrumentation_options, name, config)
  end

  describe "pg" do
    let(:declared) { declared_options(OpenTelemetry::Instrumentation::PG) }

    it "sends only options the instrumentation declares" do
      expect(declared.keys).to include(*options_we_send(:pg).keys)
    end

    it "sends a db_statement value the instrumentation accepts" do
      Verse::Otel::Config::DB_STATEMENT_MODES.each do |mode|
        sent = options_we_send(:pg, db_statement: mode)

        expect(declared[:db_statement][:validator]).to include(sent[:db_statement])
      end
    end

    it "offers exactly the modes the instrumentation supports" do
      # If upstream adds or drops a mode, our config schema should follow
      # rather than silently reject a valid one or accept a dead one.
      expect(Verse::Otel::Config::DB_STATEMENT_MODES)
        .to match_array(declared[:db_statement][:validator])
    end
  end

  describe "net_http" do
    let(:declared) { declared_options(OpenTelemetry::Instrumentation::Net::HTTP) }

    it "sends only options the instrumentation declares" do
      sent = options_we_send(:net_http, untraced_hosts: ["example.com"])

      expect(declared.keys).to include(*sent.keys)
    end
  end
end
