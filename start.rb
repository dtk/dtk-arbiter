require 'bundler'

Bundler.setup

require 'eventmachine'
require 'dotenv'
require File.expand_path('lib/listener', File.dirname(__FILE__))

# load environment configuration
Dotenv.load

# lock gemfile versions

EM.run {
  EM.connect ENV['STOMP_HOST'], ENV['STOMP_PORT'], Arbiter::Listener
}
