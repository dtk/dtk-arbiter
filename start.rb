require 'bundler'

Bundler.setup

require 'eventmachine'
require 'daemons'
require 'optparse'

require File.expand_path('lib/listener', File.dirname(__FILE__))
require File.expand_path('lib/utils/facts', File.dirname(__FILE__))
require File.expand_path('lib/utils/config', File.dirname(__FILE__))
require File.expand_path('lib/common/logger', File.dirname(__FILE__))


# Parsing OPTIONS
options = {}
options[:daemonize] = true
OptionParser.new do |opts|
  opts.on("-p", "--pid", "Daemon PID file") do |pid|
    options[:pid] = pid
  end
  opts.on("-d", "--development", "Development") do |_x|
    options[:daemonize] = false
    options[:development] = true
  end
end.parse!

# Load FACTS
facts = Arbiter::Utils::Facts.load_facts
unless facts['pbuilderid']
  raise "Not able to retrieve/resolve Pbuilder ID aborting listener ..."
end

Arbiter::PBUILDER_ID = facts['pbuilderid']

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
end

begin
  EM.run {
    Signal.trap('INT') { EM.stop }
    Signal.trap('TERM'){ EM.stop }

    Arbiter::Log.debug "Starting EventMachine reactor"

    EM.connect Arbiter::Utils::Config.stomp_url, Arbiter::Utils::Config.stomp_port, Arbiter::Listener
    Arbiter::Log.info "Arbiter listener has been successfully started. Listening to #{Arbiter::Utils::Config.full_url} ..."
  }
rescue Exception => e
  Arbiter::Log.fatal(e.message, e.backtrace)
  exit(1)
end
