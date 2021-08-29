module SSE
  SetRetryInterval = Struct.new(:milliseconds)

  #
  # Server-Sent Event type used by {Client}. Use {Client#on_event} to receive events.
  #
  # @!attribute type
  #   @return [Symbol] the string that appeared after `event:` in the stream;
  #     defaults to `:message` if `event:` was not specified, will never be nil
  # @!attribute data
  #   @return [String] the string that appeared after `data:` in the stream;
  #     if there were multiple `data:` lines, they are concatenated with newlines
  # @!attribute id
  #   @return [String] the string that appeared after `id:` in the stream if any, or nil
  #
  StreamEvent = Struct.new(:type, :data, :id) do
    # Type and Data should be present, and contain something
    #
    # @return [Boolean]
    def valid?
      !(self.type.nil? || self.type.empty?) &&
      !(self.data.nil? || self.data.empty?)
    end
  end

  class ChunkParser
    # Break between individual lines of an event
    LINE_BREAK = /\r?\n|\r\n?/

    # Break between individual event records
    RECORD_BREAK = /\r?\n\r?\n/

    # Seperator between event key and values
    FIELD_SEPERATOR = /: */

    def initialize(connection_body)
      # Ensure that we were given a body instead of a connection
      # response. If we were, extract the body instead.
      @connection_body = if connection_body.is_a?(HTTP::Response)
        connection_body.body
      else
        connection_body
      end
    end

    # Connection bodies from `HTTP` expose `#each` which is based on
    # received chunks from a streaming source. Each of these chunks
    # contains one or more records delimited by `RECORD_BREAK`, which
    # can then be parsed as individual events by `parse_event`.
    #
    # @param &block [Proc]
    #
    # @return [void]
    def each(&block)
      @connection_body.each do |chunk|
        chunk.split(RECORD_BREAK).each do |raw_event|
          parsed_event = parse_event(raw_event)

          # Don't yield the event unless we got something back
          yield parsed_event if parsed_event
        end
      end
    end

    # Coerce the connection body to an Array of events, rather
    # than directly iterate them via `#each`.
    #
    # @return [Array[SSE::StreamEvent, SSE::SetRetryInterval]]
    #   Can return either a StreamEvent or SetRetryInterval
    def to_a
      results = []
      each { |event| results << event }
      results
    end

    # Parses an individual record. This record can either be a
    # StreamEvent or a SetRetryInterval, and in the case of an
    # event we also need to ensure that it's valid before
    # returning it.
    #
    # @param raw_event [String]
    #   Newline delimited raw event string.
    #
    # @return [SSE::StreamEvent]
    #   A StreamEvent representing an event message.
    #
    # @return [SSE::SetRetryInterval]
    #   A SetRetryInterval representing a change to the retry
    #   interval.
    #
    # @return [nil]
    #   Neither a SetRetryInterval nor a valid StreamEvent were
    #   present, so there is no event to return.
    def parse_event(raw_event)
      event = StreamEvent.new(:message, "", nil)
      retry_interval = SetRetryInterval.new

      raw_event.split(LINE_BREAK).each do |field|
        # type: message (may be JSON-like, so keep to 2 split to prevent truncation)
        name, value = field.split(FIELD_SEPERATOR, 2)

        case name
        # Data can be broken into multiple lines. If a line is already present
        # we want to amend to it with a newline delimiter.
        when 'data'
          event.data << "\n" unless event.data.empty?
          event.data << value
        when 'event'
          event.type = value.to_sym
        when 'id'
          event.id = value
        when 'retry'
          retry_interval.milliseconds = value.to_i
        else
          # Handle the potential case of a comment, ":", or
          # an invalid record.
          next
        end
      end

      # This is a retry event, ignore other items
      return retry_interval if retry_interval.milliseconds

      # The event needs to be valid, meaning contains data
      return event if event.valid?

      nil
    end
  end
end
