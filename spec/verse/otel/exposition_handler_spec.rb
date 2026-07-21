# frozen_string_literal: true

class FakeHttpHook; end

class FakeExposition
  attr_reader :current_action, :hook

  def initialize(action: :show, hook: FakeHttpHook.new)
    @current_action = action
    @hook = hook
  end
end

RSpec.describe Verse::Otel::ExpositionHandler do
  let(:exposition) { FakeExposition.new }

  def run_handler(&block)
    inner = Verse::Exposition::Handler.new(block, exposition)
    described_class.new(inner, exposition).call
  end

  context "when telemetry is enabled" do
    before do
      setup_test_tracing
      Verse::Otel.enabled = true
    end

    it "wraps the call in a named span with verse attributes" do
      result = run_handler { :done }

      expect(result).to eq :done
      expect(finished_spans.size).to eq 1

      span = finished_spans.first
      expect(span.name).to eq "FakeExposition#show"
      expect(span.attributes["verse.hook"]).to eq "FakeHttpHook"
      expect(span.attributes["verse.action"]).to eq "show"
    end

    it "records exceptions on the span and re-raises" do
      expect { run_handler { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")

      span = finished_spans.first
      expect(span.status.code).to eq OpenTelemetry::Trace::Status::ERROR

      exception_event = span.events.find { |e| e.name == "exception" }
      expect(exception_event.attributes["exception.message"]).to eq "boom"
    end
  end

  context "when telemetry is disabled" do
    before { setup_test_tracing }

    it "passes through without creating spans" do
      expect(run_handler { :done }).to eq :done
      expect(finished_spans).to be_empty
    end
  end
end
