require 'mqtt'

class MQTTHandler
  include Singleton
  include LoggingHelper

  attr_accessor :process_thread, :quit_thread

  def initialize
    # Check for required environment variables
    raise 'Missing environment MQTT_URL' if ENV['MQTT_URL'].nil?

    SocketClient.instance.subscribe_messages('mqtt_message_handler')
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

  def mqtt_client
    @mqtt_client ||= MQTT::Client.connect(ENV['MQTT_URL'], clean_session: true, version: '3.1.1')
  end

  def message_loop
    messages = SocketClient.instance.drain_messages('mqtt_message_handler')
    return unless messages.present?

    info "Processing #{messages.size} messages"

    parsed_events = messages.map do |message|
      next if (match = /\A(?<event_type>[0-9a-z]+)(?<event_data>.*)\z/.match(message)).nil?
      next if (event_data = match[:event_data].strip).blank?

      begin
        event_json = JSON.parse(event_data)
        next unless event_json.is_a?(Array) && event_json[1].respond_to?(:key?) && event_json[1]['_tenantId']

        event_json[1].transform_keys { |key| key.sub(/^_/, '') }
      rescue JSON::ParserError
        error "Message not valid JSON #{event_data} - #{e}"
      end
    end.compact

    return unless parsed_events.present?

    parsed_events.each do |event|
      topic = "tenants/#{event['_tenantId']}" \
              "/transmitters/#{event['tiraid']['identifier']['type']}/#{event['tiraid']['identifier']['value']}" \
              '/events/rtls'

      # Publish to MQTT
      info "Publishing event to topic #{topic}"
      mqtt_client.publish(
        topic,
        event.to_json,
        false,
        1
      )
    end
  rescue StandardError, MQTT::Exception => e
    error "Error encountered - #{e}"
    @mqtt_client = nil
  end
end
