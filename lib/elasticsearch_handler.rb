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

    SocketClient.instance.subscribe_events('es_message_handler')
  end

  def start!
    raise 'Already started' unless process_thread.nil?

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
    events = SocketClient.instance.drain_events('es_message_handler')
    return unless events.present?

    info "Processing #{events.size} messages"

    es_client.bulk(
      body: events.map do |event|
        {
          index: {
            _index: ENV['ELASTICSEARCH_INDEX'],
            _type: ENV['ELASTICSEARCH_TYPE'],
            _id: UUIDTools::UUID.sha1_create(
              UUIDTools::UUID_OID_NAMESPACE,
              "#{event['time']}-#{event['deviceId']}-#{event['receiverId']}"
            ).to_s,
            data: event.transform_keys { |key| key.sub(/^_/, '') }
          }
        }
      end
    )

    info "Indexed #{events.size} messages for [#{events.map{ |e| e['deviceId'] }.uniq.join(',')}]"
  rescue StandardError => e
    error "Error encountered - #{e}"
    @es_client = nil
  end
end
