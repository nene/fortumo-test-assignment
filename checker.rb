require 'net/http'
require 'ostruct'

class SmsNotifier
  def notify(status)
    puts "SMS: #{status.title} #{status.msg}"
  end
end

class MailNotifier
  def notify(status)
    puts "Email: #{status.title}"
    puts "       #{status.msg}"
  end
end

class StatusHandler
  def initialize(conf)
    @previous_status = :ok
    @should_notify = false
    @last_non_timeout_time = Time.now
    @timeout_reporting_delay = conf[:timeout_reporting_delay]
  end

  def update(status_code)
    if @previous_status != status_code && status_code != :timeout
      @should_notify = true
      @last_non_timeout_time = Time.now
    elsif status_code == :timeout
      @should_notify = Time.now > @last_non_timeout_time + @timeout_reporting_delay
    else
      @should_notify = false
    end
    @previous_status = status_code
    self
  end

  def should_notify?
    @should_notify
  end
end


class StatusReporter
  def initialize(conf)
    @notifiers = []
    @status_handler = StatusHandler.new(conf)
    @expected_content = conf[:expected_content]
  end

  def add_notifiers(notifiers)
    @notifiers += notifiers
  end

  def report(status)
    if @status_handler.update(status.code).should_notify?
      @notifiers.each {|n| n.notify(status) }
    end
  end
end

class StatusChecker
  def initialize(conf)
    @http = Net::HTTP.new(conf[:server], conf[:port])
    @http.read_timeout = conf[:request_timeout]
  end

  def check(url)
    begin
      res = @http.request_get(url)
      if res.code == '200'
        if res.body =~ @expected_content
          status(:ok, "Server is back up", "Hurrey!")
        else
          status(:blank, "Blank page", "Totally empty!")
        end
      else
        status(res.code.to_i, "Server is down", "Error: #{res.code}")
      end
    rescue Timeout::Error => err
      status(:timeout, "Server is does not respond", "Error: Timeout")
    rescue Errno::ECONNREFUSED => err
      status(:connection_refused, "Server is down", "Error: Connection refused")
    rescue StandardError => err
      status(:unknown, "Error when checking server status", "Error: #{err.inspect}")
    end
  end

  def status(code, title, msg)
    OpenStruct.new(:code => code, :title => title, :msg => msg)
  end
end

require './conf.rb'

reporter = StatusReporter.new(CONF)
reporter.add_notifiers([MailNotifier.new, SmsNotifier.new])

checker = StatusChecker.new(CONF)

while true
  reporter.report(checker.check('/'))
  sleep 1
end
