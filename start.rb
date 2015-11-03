require 'bundler'

Bundler.setup

require 'eventmachine'
require 'dotenv'
require 'daemons'
require 'optparse'

require File.expand_path('lib/listener', File.dirname(__FILE__))
require File.expand_path('lib/utils/facts', File.dirname(__FILE__))

options = {}
OptionParser.new do |opts|
  opts.on("-p", "--pid", "Daemon PID file") do |pid|
    options[:pid] = pid
  end
end.parse!

# load environment configuration
Dotenv.load

facts = Arbiter::Utils::Facts.load_facts
unless facts['pbuilderid']
  raise "Not able to retrieve/resolve Pbuilder ID aborting listener ..."
end

Arbiter::PBUILDER_ID = facts['pbuilderid']


Daemons.daemonize(app_name: 'dtk-arbiter')
File.open(options[:pid] || '/var/run/dtk-arbiter.pid', 'w') { |f| f.puts(Process.pid) }

EM.run {
  Signal.trap('INT') { stop }
  Signal.trap('TERM'){ stop }

  EM.connect ENV['STOMP_HOST'], ENV['STOMP_PORT'], Arbiter::Listener
  puts "Arbiter listener has been successfully started. Listening to stomp://#{ENV['STOMP_HOST']}:#{ENV['STOMP_PORT']} ..."
}
