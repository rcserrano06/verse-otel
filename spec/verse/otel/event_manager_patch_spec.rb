# frozen_string_literal: true

class FakeEventManager
  Message = Struct.new(:headers)

  attr_reader :published, :dispatched

  def publish(channel, content, headers: {}, key: nil)
    @published = { channel:, content:, headers:, key: }
  end

  def publish_resource_event(resource_type:, resource_id:, event:, payload:, headers: {})
    @published = { channel: "#{resource_type}.#{event}", payload:, headers:, resource_id: }
  end

  def dispatch_message(channel, message)
    @dispatched = { channel:, message: }
  end
end

class PatchedEventManager < FakeEventManager
  prepend Verse::Otel::EventManagerPatch
end

RSpec.describe Verse::Otel::EventManagerPatch do
  let(:manager) { PatchedEventManager.new }

  context "when telemetry is enabled" do
    before do
      setup_test_tracing
      Verse::Otel.enabled = true
    end

    it "creates a producer span and injects trace headers on publish" do
      manager.publish("users:created", { id: 1 }, headers: { custom: "kept" })

      expect(manager.published[:headers]).to include(:custom, :traceparent)

      span = finished_spans.first
      expect(span.name).to eq "publish users:created"
      expect(span.kind).to eq :producer
      expect(span.attributes["messaging.destination.name"]).to eq "users:created"
    end

    it "injects headers on publish_resource_event" do
      manager.publish_resource_event(
        resource_type: "users", resource_id: "1", event: "created", payload: {}
      )

      expect(manager.published[:headers]).to include(:traceparent)
      expect(finished_spans.first.name).to eq "publish users.created"
    end

    it "continues the trace from producer to consumer" do
      manager.publish("users:created", { id: 1 })
      headers = manager.published[:headers]

      manager.dispatch_message("users:created", FakeEventManager::Message.new(headers))

      producer, consumer = finished_spans.sort_by { |s| s.kind == :producer ? 0 : 1 }
      expect(consumer.name).to eq "consume users:created"
      expect(consumer.kind).to eq :consumer
      expect(consumer.hex_trace_id).to eq producer.hex_trace_id
      expect(manager.dispatched[:channel]).to eq "users:created"
    end

    it "continues the trace across a msgpack round-trip" do
      # verse-redis packs the message and unpacks it with symbolize_keys,
      # so a consumer in another process sees symbol keys — while the W3C
      # propagator only reads string ones. Simulate that hop rather than
      # handing the producer's own hash straight to the consumer.
      manager.publish("users:created", { id: 1 })
      round_tripped = manager.published[:headers]
                             .map { |k, v| [k.to_s, v] }.to_h
                             .transform_keys(&:to_sym)

      manager.dispatch_message("users:created", FakeEventManager::Message.new(round_tripped))

      producer, consumer = finished_spans.sort_by { |s| s.kind == :producer ? 0 : 1 }
      expect(consumer.hex_trace_id).to eq producer.hex_trace_id
      expect(consumer.parent_span_id).to eq producer.span_id
    end

    it "starts a fresh trace for messages without trace headers" do
      manager.dispatch_message("legacy", FakeEventManager::Message.new(nil))

      expect(finished_spans.size).to eq 1
      expect(manager.dispatched[:channel]).to eq "legacy"
    end
  end

  context "when telemetry is disabled" do
    before { setup_test_tracing }

    it "leaves headers untouched and creates no spans" do
      manager.publish("users:created", { id: 1 }, headers: { custom: "kept" })

      expect(manager.published[:headers]).to eq({ custom: "kept" })
      expect(finished_spans).to be_empty
    end
  end
end
