class ParetoEventRouter
  include Singleton
  include LoggingHelper

  def start!
    process_threads = []

    # Start the logger loop
    process_threads << ConsoleLogger.instance.tap(&:start!)

    # Start the socket client thread
    process_threads << SocketClient.instance.tap(&:start!)

    # Start the event handler threads
    process_threads << ElasticsearchHandler.instance.tap(&:start!) if ENV['ELASTICSEARCH_URL']
    process_threads << MQTTHandler.instance.tap(&:start!) if ENV['MQTT_URL']
    process_threads << RabbitMQHandler.instance.tap(&:start!) if ENV['RABBITMQ_URL']

    # Trap CTRL-C and SIGTERM
    trap('INT') do
      warn 'CTRL-C detected, waiting for all threads to exit gracefully...'
      process_threads.reverse.each(&:quit!)
      exit(0)
    end
    trap('TERM') do
      error 'Kill detected, waiting for all threads to exit gracefully...'
      process_threads.reverse.each(&:quit!)
      exit(1)
    end

    warn 'Press CTRL-C at any time to stop all threads and exit'

    # Wait on threads
    process_threads.each(&:wait!)
  end
end
