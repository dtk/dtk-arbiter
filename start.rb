
require 'bundler'
Bundler.setup

require 'eventmachine'
require 'daemons'
require 'optparse'

require_relative('lib/listener')
require_relative('lib/utils/config')
require_relative('lib/common/logger')


# Parsing OPTIONS
options = {}
options[:daemonize] = true
OptionParser.new do |opts|
  opts.on("-p PIDFILE", "--pid PIDFILE", "Daemon PID file") do |pid|
    options[:pid] = pid
  end
  opts.on("-d", "--development", "Development") do |_x|
    options[:daemonize] = false
    options[:development] = true
  end
  opts.on("-f", "--foreground", "Run in foreground") do |_f|
    options[:daemonize] = false
  end
end.parse!

Arbiter::PBUILDER_ID = Arbiter::Utils::Config.pbuilderid

# DAEMONIZE
if options[:daemonize]
  Arbiter::Log.debug "Daemonizing arbiter"
  Daemons.daemonize(app_name: 'dtk-arbiter', log_dir: '/var/log/dtk', log_output: true)
  Arbiter::Log.debug "Daemonizing succesful"
  Arbiter::Log.debug "Writing pid file..."
  File.open(options[:pid] || '/var/run/dtk-arbiter.pid', 'w') { |f| f.puts(Process.pid) }
end

# DEVELOPMENT only
if options[:development]
  require 'dotenv'
  Dotenv.load
else
  # this is running as service and following ENVs are needed
  ENV['HOME'] = '/root'
  Arbiter::Log.info("DTK Arbiter running as a service, setting needed environment variables")
end

begin
  EM.run {
    Signal.trap('INT')  { EM.stop }
    Signal.trap('TERM') { EM.stop }
    Signal.trap('IOT')  { Arbiter::Log.error("Caught signal IOT(6) which could mean an error occured. Resuming DTK Arbiter normally.") }

    Arbiter::Log.debug "Starting Arbiter(EventMachine) listener, connecting to #{Arbiter::Utils::Config.full_url} ..."

    EM.connect Arbiter::Utils::Config.stomp_url, Arbiter::Utils::Config.stomp_port, Arbiter::Listener
  }
rescue Arbiter::ArbiterExit => ex
  Arbiter::Log.error("Exiting arbiter, reason: " + ex.message)
  exit(1)
rescue Exception => e
  Arbiter::Log.fatal(e.message, e.backtrace)
  exit(1)
end
