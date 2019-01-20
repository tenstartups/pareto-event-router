require 'bunny'

class RabbitMQHandler
  include Singleton
  include LoggingHelper

  attr_accessor :process_thread, :quit_thread

  def initialize
    # Check for required environment variables
    raise 'Missing environment RABBITMQ_URL' if ENV['RABBITMQ_URL'].nil?
    raise 'Missing environment RABBITMQ_QUEUE' if ENV['RABBITMQ_QUEUE'].nil?
  end

  def start!
    raise 'Already started' unless process_thread.nil?

    SocketClient.instance.subscribe_messages('rabbitmq_message_handler')
    self.process_thread = Thread.new do
      until quit_thread?
        message_loop
        sleep 0.05
      end
      rabbitmq_channel.close
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

  def rabbitmq_client
    @rabbitmq_client ||= Bunny.new(ENV['RABBITMQ_URL']).tap(&:start)
  end

  def rabbitmq_channel
    rabbitmq_client.create_channel
  end

  def rabbitmq_queue
    @rabbitmq_queue ||= rabbitmq_channel.queue(ENV['RABBITMQ_QUEUE'], durable: true, auto_delete: false)
  end

  def message_loop
    messages = SocketClient.instance.drain_messages('rabbitmq_message_handler')
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
      # topic = "tenants/#{event['tenantId']}" \
      #         "/transmitters/#{event['tiraid']['identifier']['type']}/#{event['tiraid']['identifier']['value']}" \
      #         '/events/rtls'

      # Publish to RabbitMQ
      info "Publishing event to #{ENV['RABBITMQ_QUEUE']} queue"
      rabbitmq_queue.publish(event.to_json)
    end
  rescue StandardError => e
    error "Error encountered - #{e}"
    rabbitmq_channel.close
    @rabbitmq_client = nil
  end
end
