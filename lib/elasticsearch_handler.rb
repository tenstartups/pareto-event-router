require 'elasticsearch'
require 'typhoeus'
require 'typhoeus/adapters/faraday'
require 'uuidtools'

class ElasticsearchHandler
  include Singleton
  include LoggingHelper

  attr_accessor :process_thread, :quit_thread

  def initialize
    # Check for required environment variables
    raise 'Missing environment ELASTICSEARCH_URL' if ENV['ELASTICSEARCH_URL'].nil?
    raise 'Missing environment ELASTICSEARCH_INDEX' if ENV['ELASTICSEARCH_INDEX'].nil?
    raise 'Missing environment ELASTICSEARCH_TYPE' if ENV['ELASTICSEARCH_TYPE'].nil?
  end

  def start!
    raise 'Already started' unless process_thread.nil?

    SocketClient.instance.subscribe_messages('es_message_handler')
    self.process_thread = Thread.new do
      until quit_thread?
        message_loop
        sleep 0.05
      end
    end
  end

  def wait!
    process_thread.join
  end

  def quit!
    self.quit_thread = true
    wait!
  end

  alias quit_thread? quit_thread

  def es_client
    @es_client ||= Elasticsearch::Client.new(url: ENV['ELASTICSEARCH_URL']) do |faraday|
      faraday.ssl[:verify] = false
    end
  end

  def message_loop
    messages = SocketClient.instance.drain_messages('es_message_handler')
    return unless messages.present?

    info "Processing #{messages.size} messages"

    parsed_events = messages.map do |message|
      next if (match = /\A(?<event_type>[0-9a-z]+)(?<event_data>.*)\z/.match(message)).nil?
      next if (event_data = match[:event_data].strip).blank?

      begin
        event_json = JSON.parse(event_data)
        next unless event_json.is_a?(Array) && event_json[1].respond_to?(:key?) && event_json[1]['_tenantId']

        decodings = event_json[1]['tiraid']['radioDecodings']
        event_json[1].transform_keys { |key| key.sub(/^_/, '') }.merge(
          'radioDecodingReceiverIds' => decodings.map { |d| "#{d['identifier']['type']}/#{d['identifier']['value']}" }
        )
      rescue JSON::ParserError => e
        error "Message not valid JSON #{event_data} - #{e}"
      end
    end.compact

    return unless parsed_events.present?

    es_client.bulk(
      body: parsed_events.map do |event|
        {
          index: {
            _index: ENV['ELASTICSEARCH_INDEX'],
            _type: ENV['ELASTICSEARCH_TYPE'],
            _id: UUIDTools::UUID.sha1_create(
              UUIDTools::UUID_OID_NAMESPACE,
              "#{event['time']}-#{event['deviceId']}-#{event['receiverId']}"
            ).to_s,
            data: event
          }
        }
      end
    )

    info "Indexed #{parsed_events.size} messages for [#{parsed_events.map { |e| e['deviceId'] }.uniq.join(',')}]"
  rescue StandardError => e
    error "Error encountered - #{e}"
    @es_client = nil
  end
end
