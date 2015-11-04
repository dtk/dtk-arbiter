require 'bundler'

Bundler.setup

require 'eventmachine'
require 'dotenv'
require 'daemons'
require 'optparse'

require File.expand_path('lib/listener', File.dirname(__FILE__))
require File.expand_path('lib/utils/facts', File.dirname(__FILE__))
require File.expand_path('lib/utils/config', File.dirname(__FILE__))

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
  Daemons.daemonize(app_name: 'dtk-arbiter')
  File.open(options[:pid] || '/var/run/dtk-arbiter.pid', 'w') { |f| f.puts(Process.pid) }
end

# DEVELOPMENT only
if options[:development]
  Dotenv.load
end

EM.run {
  Signal.trap('INT') { EM.stop }
  Signal.trap('TERM'){ EM.stop }

  EM.connect Arbiter::Utils::Config.stomp_url, Arbiter::Utils::Config.stomp_port, Arbiter::Listener
  puts "Arbiter listener has been successfully started. Listening to #{Arbiter::Utils::Config.full_url} ..."
}
