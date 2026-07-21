# frozen_string_literal: true

# Guards the instrumentation-loading contract: because instrumentations are
# soft dependencies of the gem, a config naming one that is absent (or simply
# misspelled) must fail loudly at boot rather than silently drop its spans.
RSpec.describe Verse::Otel, ".setup_sdk!" do
  def configure(**overrides)
    Verse::Otel.config = Verse::Otel::Config::Schema.validate(overrides).value
    described_class.setup_sdk!(service_name: "spec")
  end

  before { setup_test_tracing }

  describe "instrumentation loading" do
    it "raises and names the known set when the config has an unknown name" do
      expect { configure(instrumentations: [:kafka]) }
        .to raise_error(ArgumentError, /Unknown instrumentation `kafka`.*rack.*sinatra.*net_http.*pg.*redis/m)
    end

    it "rejects an instrumentation dropped from the map" do
      # concurrent_ruby and faraday used to be supported; a service left
      # holding a stale config must be told, not silently untraced.
      expect { configure(instrumentations: [:concurrent_ruby]) }
        .to raise_error(ArgumentError, /Unknown instrumentation `concurrent_ruby`/)
    end

    it "re-raises with the gem to install when the instrumentation gem is absent" do
      # redis is a known name but its gem is deliberately not in this
      # gem's Gemfile, which is exactly the soft-dependency situation.
      messages = []
      allow(Verse.logger).to receive(:error) { |&block| messages << block.call }

      expect { configure(instrumentations: [:redis]) }.to raise_error(LoadError)

      expect(messages.last)
        .to match(/add `opentelemetry-instrumentation-redis` to your Gemfile.*`redis`/)
    end
  end

  describe "per-instrumentation options" do
    subject(:options) { described_class.send(:instrumentation_options, name, config) }

    let(:config) do
      Verse::Otel::Config::Schema.validate(
        { db_statement: :omit, untraced_hosts: ["config.example.com"] }
      ).value
    end

    before { described_class.untraced_hosts << "config.example.com" << "contributed.example.com" }

    context "with pg" do
      let(:name) { :pg }

      it "passes the configured db_statement mode through" do
        expect(options).to eq({ db_statement: :omit })
      end
    end

    context "with net_http" do
      let(:name) { :net_http }

      it "merges config and contributed untraced hosts without duplicates" do
        expect(options[:untraced_hosts])
          .to contain_exactly("config.example.com", "contributed.example.com")
      end
    end

    context "with an instrumentation taking no options" do
      let(:name) { :rack }

      it "passes an empty option set" do
        expect(options).to eq({})
      end
    end
  end
end
