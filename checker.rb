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
  def initialize
    @prev_status = OpenStruct.new(:code => :ok, :delay => 0)
    @should_notify = false
    @prev_change = Time.now
  end

  def update(new_status)
    if @prev_status.code != new_status.code
      # When status changed. Remember the status and time of the change.
      @prev_status = new_status
      @prev_change = Time.now
      # Notify immediately when status has no delay.
      @should_notify = (new_status.delay == 0) ? true : :pending
    elsif @should_notify == :pending
      # When status didn't change and reporting of the previous change
      # is still pending, notify in case enough time has passed.
      @should_notify = true if Time.now > @prev_change + new_status.delay
    else
      # Status didn't change, and we have already reported the
      # previous change.  Do nothing until next status change.
      @should_notify = false
    end

    self
  end

  def should_notify?
    @should_notify == true
  end
end


class StatusReporter
  def initialize
    @notifiers = []
    @status_handler = StatusHandler.new
  end

  def add_notifiers(notifiers)
    @notifiers += notifiers
  end

  def report(status)
    if @status_handler.update(status).should_notify?
      @notifiers.each {|n| n.notify(status) }
    end
  end
end

class StatusChecker
  def initialize(conf)
    @http = Net::HTTP.new(conf[:server], conf[:port])
    @http.read_timeout = conf[:request_timeout]
    @expected_content = conf[:expected_content]
    @timeout_reporting_delay = conf[:timeout_reporting_delay]
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
      status(:timeout, "Server does not respond", "Error: Timeout", @timeout_reporting_delay)
    rescue Errno::ECONNREFUSED => err
      status(:connection_refused, "Server is down", "Error: Connection refused")
    rescue StandardError => err
      status(:unknown, "Error when checking server status", "Error: #{err.inspect}")
    end
  end

  def status(code, title, msg, delay=0)
    OpenStruct.new(:code => code, :title => title, :msg => msg, :delay => delay)
  end
end

require './conf.rb'

reporter = StatusReporter.new
reporter.add_notifiers([MailNotifier.new, SmsNotifier.new])

checker = StatusChecker.new(CONF)

while true
  reporter.report(checker.check('/'))
  sleep CONF[:checking_interval]
end
