# frozen_string_literal: true

RSpec.describe Verse::Otel::Config do
  subject(:result) { described_class::Schema.validate(input) }

  context "with an empty config" do
    let(:input) { {} }

    it "applies the defaults" do
      expect(result).to be_success

      config = result.value
      expect(config.enabled).to be true
      expect(config.service_name_prefix).to eq ""
      expect(config.instrumentations).to eq []
      expect(config.db_statement).to eq :obfuscate
      expect(config.untraced_hosts).to eq []
    end
  end

  context "with a full config" do
    let(:input) do
      {
        enabled: false,
        service_name_prefix: "idah-",
        instrumentations: %i[rack net_http],
        db_statement: :omit,
        untraced_hosts: ["ingest.sentry.io"]
      }
    end

    it "keeps the provided values" do
      expect(result).to be_success

      config = result.value
      expect(config.enabled).to be false
      expect(config.service_name_prefix).to eq "idah-"
      expect(config.instrumentations).to eq %i[rack net_http]
      expect(config.db_statement).to eq :omit
      expect(config.untraced_hosts).to eq ["ingest.sentry.io"]
    end
  end

  context "with an invalid db_statement mode" do
    let(:input) { { db_statement: :shout } }

    it "fails validation" do
      expect(result).not_to be_success
      expect(result.errors).to have_key(:db_statement)
    end
  end
end
