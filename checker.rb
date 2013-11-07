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
  TIMEOUT_WAITING_TIME = 1

  def initialize
    @previous_status = '200'
    @should_notify = false
    @last_non_timeout_time = Time.now
  end

  def update(status)
    if @previous_status != status && !status.is_a?(Timeout::Error)
      @should_notify = true
      @last_non_timeout_time = Time.now
    elsif status.is_a?(Timeout::Error)
      @should_notify = Time.now > @last_non_timeout_time + TIMEOUT_WAITING_TIME
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
  EXPECTED_CONTENT = /Hello worlds/i

  def initialize(*notifiers)
    @notifiers = notifiers
    @status_handler = StatusHandler.new
  end

  def report(res)
    case res
    when Net::HTTPResponse
      if res.code == '200'
        if res.body =~ EXPECTED_CONTENT
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


notifiers = [MailNotifier.new, SmsNotifier.new]
status_reporter = StatusReporter.new(*notifiers)

http = Net::HTTP.new('localhost', 2000)
http.read_timeout = 1

while true
  begin
    res = http.request_get('/')
    status_reporter.report(res)
  rescue StandardError => err
    status_reporter.report(err)
  end
  sleep 1
end
