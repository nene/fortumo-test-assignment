require 'net/http'

class ErrorMailer
  def initialize
    @previous_status = '200'
  end

  def mail(status, title, msg)
    return if @previous_status == status

    puts title
    puts "    " + msg

    @previous_status = status
  end

  def status=(status)
    @previous_status = status
  end
end

err_mailer = ErrorMailer.new
http = Net::HTTP.new('localhost', 2000)
http.read_timeout = 1

while true
  begin
    res = http.request_get('/')
    if res.code == '200'
      err_mailer.mail(res.code, "Server is back up", "Hurrey!")
    else
      err_mailer.mail(res.code, "Server is down", "Error: #{res.code}")
    end
  rescue Timeout::Error => err
    err_mailer.mail(err, "Server is does not respond", "Error: Timeout")
  rescue Errno::ECONNREFUSED => err
    err_mailer.mail(err, "Server is down", "Error: Connection refused")
  rescue StandardError => err
    err_mailer.mail(err, "Error when checking server status", "Error: #{err.inspect}")
  end
  sleep 1
end
