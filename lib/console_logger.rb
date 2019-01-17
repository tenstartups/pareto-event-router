require 'colorize'

class ConsoleLogger
  include Singleton

  attr_accessor :process_thread, :quit_thread
  attr_writer :available_colors

  def available_colors
    @available_colors ||= []
  end

  def log_colors
    @log_colors ||= {}
  end

  def log_queue
    @log_queue ||= Queue.new
  end

  def log(source_id:, severity: :info, message:)
    log_queue.push source_id: source_id, severity: severity, message: message
  end

  %i[debug info warn error].each do |severity|
    define_method :"log_#{severity}" do |source_id, message|
      log severity: severity.to_sym, source_id: source_id, message: message
    end
  end

  def start!
    raise 'Already started' unless process_thread.nil?

    self.process_thread = Thread.new do
      log!(source_id: self.class.name.split('::').last, severity: :debug, message: 'Starting processing thread')
      until quit_thread? && log_queue.empty?
        log!(**log_queue.pop) until log_queue.empty?
        sleep 0.01
      end
      log!(source_id: self.class.name.split('::').last, severity: :debug, message: 'Quitting processing thread')
    end
    log!(source_id: self.class.name.split('::').last, severity: :debug, message: 'Processing thread ready')
  end

  def wait!
    process_thread.join
  end

  def quit!
    self.quit_thread = true
    wait!
  end

  alias quit_thread? quit_thread

  private

  def format_logging?
    ENV['FORMAT_LOGGING'] == 'true'
  end

  def next_available_color
    self.available_colors = (String.colors.shuffle - %i[yellow red black white]) if available_colors.empty?
    available_colors.slice!(0)
  end

  def log_prefix(source_id)
    if format_logging?
      log_color = (log_colors[source_id] ||= next_available_color)
      "#{source_id.ljust(20)} |".colorize(log_color)
    else
      "#{source_id} -"
    end
  end

  def log!(source_id:, severity: :info, message:)
    stream, message, color = case severity
                             when :debug
                               [:stdout, message, :light_magenta]
                             when :info
                               [:stdout, message]
                             when :warn
                               [:stderr, message, :yellow]
                             when :error
                               [:stderr, message, :red]
                             else
                               [:stdout, message]
                             end
    message = "#{log_prefix(source_id)} #{format_logging? && color ? message.colorize(color) : message}"
    case stream
    when :stdout
      STDOUT.puts message
    when :stderr
      STDERR.puts message
    else
      puts message
    end
  end
end
