require 'pry'
require 'socket.io-client-simple'

class SocketClient
  include Singleton
  include LoggingHelper

  attr_accessor :process_thread, :quit_thread, :connect_socket_at, :last_message_received_at

  def initialize
    # Check for required environment variables
    raise 'Missing environment PARETO_URL' if ENV['PARETO_URL'].nil?
    raise 'Missing environment PARETO_API_TOKEN' if ENV['PARETO_API_TOKEN'].nil?
  end

  def subscribers
    @subscribers ||= {}
  end

  def start!
    raise 'Already started' unless process_thread.nil?

    self.process_thread = Thread.new do
      self.connect_socket_at = Time.now
      self.last_message_received_at = nil
      until quit_thread?
        listener_loop
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

  def listener_loop
    # Break out gracefully if exit signaled
    return if quit_thread?

    # Simply sleep move on if we're connected
    if connect_socket_at.nil? || Time.now < connect_socket_at
      raise StandardError, 'No message received in 60 seconds' if last_message_received_at && Time.now.to_i - last_message_received_at > 60

      return
    end

    # Open websocket connection to the Pareto server
    info 'Connecting to Pareto RTLS socket feed'
    socket = SocketIO::Client::Simple.connect(ENV['PARETO_URL'], token: ENV['PARETO_API_TOKEN'])

    client = self

    socket.websocket.on :message do |message|
      client.handle_message(message)
    end

    socket.on :connect do
      client.handle_connect
    end

    socket.on :disconnect do
      client.handle_disconnect
    end

    self.connect_socket_at = nil
  rescue StandardError => e
    error "Error encountered - #{e}"
    info 'Reconnecting to Pareto socket in 10 seconds'
    self.connect_socket_at = Time.now + 10
    self.last_message_received_at = nil
  end

  def subscribe_messages(client_id)
    subscribers[client_id] = Queue.new
    client_id
  end

  def unsubscribe_messages(client_id)
    subscribers.delete(client_id)
    client_id
  end

  def handle_connect
    info 'Connected to Pareto RTLS socket feed'
  end

  def handle_disconnect
    info 'Disconnected from Pareto RTLS socket feed, reconnecting in 10 seconds'
    self.connect_socket_at = Time.now + 10
    self.last_message_received_at = nil
  end

  def handle_message(message)
    self.last_message_received_at = Time.now.to_i
    info "Received RTLS message #{message.data.truncate(100, omission: '... (truncated)')}"
    subscribers.values.each { |q| q.push(message.data) }
  end

  def next_message(client_id)
    subscribers[client_id].pop if subscribers[client_id].length.positive?
  end

  def drain_messages(client_id)
    messages = []
    subscribers[client_id].length.times do
      messages << subscribers[client_id].pop
    end
    messages
  end
end
