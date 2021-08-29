require "ld-eventsource"

describe SSE::ChunkParser do
  # Empty chunk
  let(:chunks) { [""] }

  subject { described_class.new(chunks) }

  describe '.new' do
    it 'creates an instance of a ChunkParser' do
      expect(subject).to be_a(SSE::ChunkParser)
    end
  end

  describe '#parse_event' do
    it 'parses an event with all fields' do
      parsed_event = subject.parse_event <<~EVENT
        event: abc
        data: def
        id: 1

      EVENT

      expected_event = SSE::StreamEvent.new(:abc, "def", "1")

      expect(parsed_event).to eq(expected_event)
    end

    it "parses an event with only data" do
      parsed_event = subject.parse_event <<~EVENT
        data: def

      EVENT

      expected_event = SSE::StreamEvent.new(:message, "def", nil)

      expect(parsed_event).to eq(expected_event)
    end

    it "parses an event with multi-line data" do
      parsed_event = subject.parse_event <<~EVENT
        data: def
        data: ghi

      EVENT

      expected_event = SSE::StreamEvent.new(:message, "def\nghi", nil)
      expect(parsed_event).to eq(expected_event)
    end

    it "ignores comments" do
      parsed_event = subject.parse_event <<~EVENT
        :
        data: def
        :

      EVENT

      expected_event = SSE::StreamEvent.new(:message, "def", nil)
      expect(parsed_event).to eq(expected_event)
    end

    it "parses reconnect interval" do
      parsed_event = subject.parse_event <<~EVENT
        retry: 2500

      EVENT

      expected_item = SSE::SetRetryInterval.new(2500)
      expect(parsed_event).to eq(expected_item)
    end

    it "parses JSON-like messages" do
      json = {
        key1: "value1",
        key2: "value2",
        key3: "value3",
        key4: "value4",
      }.to_json

      parsed_event = subject.parse_event <<~EVENT
        data: #{json}

      EVENT

      expected_event = SSE::StreamEvent.new(:message, json, nil)

      expect(parsed_event).to eq(expected_event)
    end
  end

  describe '#to_a' do
    it "parses multiple events" do
      chunk = <<~CHUNK
        event: abc
        data: def
        id: 1

        data: ghi

      CHUNK

      parser = described_class.new([chunk, chunk])

      expected_event_1 = SSE::StreamEvent.new(:abc, "def", "1")
      expected_event_2 = SSE::StreamEvent.new(:message, "ghi", nil)

      expect(parser.to_a).to eq([
        expected_event_1,
        expected_event_2,
        expected_event_1,
        expected_event_2
      ])
    end

    it "ignores events with no data" do
      chunk = <<~CHUNK
        event: nothing

        event: nada

      CHUNK

      parser = described_class.new([chunk])

      expect(parser.to_a).to eq([])
    end
  end
end
