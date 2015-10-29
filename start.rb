require 'bundler'

Bundler.setup

require 'eventmachine'
require 'dotenv'
require File.expand_path('lib/listener', File.dirname(__FILE__))
require File.expand_path('lib/utils/facts', File.dirname(__FILE__))

# load environment configuration
Dotenv.load

facts = Arbiter::Utils::Facts.load_facts
unless facts['pbuilderid']
  raise "Not able to retrieve/resolve Pbuilder ID aborting listener ..."
end

Arbiter::PBUILDER_ID = facts['pbuilderid']

# lock gemfile versions

EM.run {
  EM.connect ENV['STOMP_HOST'], ENV['STOMP_PORT'], Arbiter::Listener
}
