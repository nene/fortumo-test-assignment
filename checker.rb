require 'net/http'

class SmsNotifier
  def notify(status, title, msg)
    puts "SMS: #{title} #{msg}"
  end
end

class MailNotifier
  def notify(status, title, msg)
    puts title
    puts "    " + msg
  end
end

class StatusHandler
  def initialize(conf)
    @previous_status = '200'
    @should_notify = false
    @last_non_timeout_time = Time.now
    @timeout_reporting_delay = conf[:timeout_reporting_delay]
  end

  def update(status)
    if @previous_status != status && !status.is_a?(Timeout::Error)
      @should_notify = true
      @last_non_timeout_time = Time.now
    elsif status.is_a?(Timeout::Error)
      @should_notify = Time.now > @last_non_timeout_time + @timeout_reporting_delay
    else
      @should_notify = false
    end
    @previous_status = status
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

  def report(res)
    case res
    when Net::HTTPResponse
      if res.code == '200'
        if res.body =~ @expected_content
          notify(res.code, "Server is back up", "Hurrey!")
        else
          notify(:blank, "Blank page", "Totally empty!")
        end
      else
        notify(res.code, "Server is down", "Error: #{res.code}")
      end
    when Timeout::Error
      notify(res, "Server is does not respond", "Error: Timeout")
    when Errno::ECONNREFUSED
      notify(res, "Server is down", "Error: Connection refused")
    when StandardError
      notify(res, "Error when checking server status", "Error: #{res.inspect}")
    end
  end

  def notify(status, title, msg)
    if @status_handler.update(status).should_notify?
      @notifiers.each {|n| n.notify(status, title, msg) }
    end
  end
end

class StatusMonitor
  def initialize(conf)
    @status_reporter = StatusReporter.new(conf)
    @status_reporter.add_notifiers([MailNotifier.new, SmsNotifier.new])

    @http = Net::HTTP.new(conf[:server], conf[:port])
    @http.read_timeout = conf[:request_timeout]
  end

  def start
    while true
      begin
        res = @http.request_get('/')
        @status_reporter.report(res)
      rescue StandardError => err
        @status_reporter.report(err)
      end
      sleep 1
    end
  end
end

require './conf.rb'

StatusMonitor.new(CONF).start

